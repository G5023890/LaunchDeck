import Foundation

struct LaunchctlService: @unchecked Sendable {
    private let commandRunner: any CommandExecuting
    private let fileAccess: any FileAccessService
    private let launchctlClient: any LaunchctlClient
    static let managedPrefix = "com.launchctl.schedule."

    init(
        commandRunner: any CommandExecuting = ShellExecutor(),
        fileAccess: any FileAccessService = FoundationFileAccessService(),
        launchctlClient: (any LaunchctlClient)? = nil
    ) {
        self.commandRunner = commandRunner
        self.fileAccess = fileAccess
        self.launchctlClient = launchctlClient ?? DefaultLaunchctlClient(runner: commandRunner)
    }

    func fetchRunningProcesses(limit: Int = 400) async throws -> [RunningProcess] {
        let result = try await commandRunner.run("/bin/ps", ["-axo", "pid=,ppid=,user=,state=,pcpu=,rss=,etime=,comm="], timeout: 20)
        guard result.status == 0 else {
            throw LaunchControlError.commandFailed(result.stderr.ifEmpty("ps failed"))
        }

        let parsed = result.stdout
            .split(separator: "\n")
            .compactMap(parseProcessLine)
            .sorted { lhs, rhs in
                if lhs.cpu == rhs.cpu {
                    return lhs.pid < rhs.pid
                }
                return lhs.cpu > rhs.cpu
            }

        return Array(parsed.prefix(limit))
    }

    func fetchLaunchServices(limit: Int = 1500) async throws -> [LaunchServiceJob] {
        async let loadedTask = fetchLoadedLaunchRecords(limit: limit)
        let plistEntries = scanKnownPlists()
        let loadedRecords = try await loadedTask

        let loadedMap = Dictionary(uniqueKeysWithValues: loadedRecords.map { ($0.label, $0) })
        var jobs: [LaunchServiceJob] = []
        var attachedLabels = Set<String>()

        for entry in plistEntries {
            let loaded = loadedMap[entry.label]
            let pid = loaded?.pid
            let exitCode = loaded?.exitCode
            let state = stateFor(pid: pid, exitCode: exitCode, loaded: loaded != nil)

            jobs.append(
                LaunchServiceJob(
                    id: "\(entry.domain.rawValue)::\(entry.label)::\(entry.path)",
                    label: entry.label,
                    domain: entry.domain,
                    pid: pid,
                    state: state,
                    exitCode: exitCode,
                    program: entry.program,
                    arguments: entry.arguments,
                    runAtLoad: entry.runAtLoad,
                    keepAliveDescription: entry.keepAliveDescription,
                    schedule: entry.schedule,
                    plistPath: entry.path,
                    environmentVariables: entry.environmentVariables,
                    machServices: entry.machServices,
                    workingDirectory: entry.workingDirectory,
                    standardOutPath: entry.standardOutPath,
                    standardErrorPath: entry.standardErrorPath,
                    watchPaths: entry.watchPaths,
                    queueDirectories: entry.queueDirectories,
                    ownerAccountName: entry.ownerAccountName,
                    groupOwnerAccountName: entry.groupOwnerAccountName,
                    rawKeys: entry.rawKeys
                )
            )

            attachedLabels.insert(entry.label)
        }

        for loaded in loadedRecords where !attachedLabels.contains(loaded.label) {
            let state = stateFor(pid: loaded.pid, exitCode: loaded.exitCode, loaded: true)
            jobs.append(
                LaunchServiceJob(
                    id: "unknown::\(loaded.label)",
                    label: loaded.label,
                    domain: .unknown,
                    pid: loaded.pid,
                    state: state,
                    exitCode: loaded.exitCode,
                    program: nil,
                    arguments: [],
                    runAtLoad: nil,
                    keepAliveDescription: nil,
                    schedule: .none,
                    plistPath: nil,
                    environmentVariables: [:],
                    machServices: [],
                    workingDirectory: nil,
                    standardOutPath: nil,
                    standardErrorPath: nil,
                    watchPaths: [],
                    queueDirectories: [],
                    ownerAccountName: nil,
                    groupOwnerAccountName: nil,
                    rawKeys: []
                )
            )
        }

        let sorted = jobs.sorted { lhs, rhs in
            if lhs.label == rhs.label {
                return lhs.domain.title < rhs.domain.title
            }
            return lhs.label < rhs.label
        }

        return Array(sorted.prefix(limit))
    }

    func fetchManagedAgents() async throws -> [ManagedAgent] {
        let loaded = try await fetchLoadedLaunchRecords(limit: 4000)
        let loadedLabels = Set(loaded.map(\.label))

        let agentsDir = try launchAgentsDirectory()
        let urls: [URL]
        do {
            urls = try fileAccess.contentsOfDirectory(at: agentsDir)
        } catch {
            throw error
        }

        var agents: [ManagedAgent] = []

        for url in urls where url.pathExtension == "plist" {
            guard let entry = parsePlist(at: url, domain: .userAgent),
                  entry.label.hasPrefix(Self.managedPrefix)
            else {
                continue
            }

            let executable = entry.program ?? ""
            let args = entry.arguments.isEmpty ? "" : " " + entry.arguments.joined(separator: " ")

            agents.append(
                ManagedAgent(
                    id: entry.label,
                    label: entry.label,
                    plistPath: entry.path,
                    command: executable + args,
                    schedule: entry.schedule,
                    runAtLoad: entry.runAtLoad ?? false,
                    isLoaded: loadedLabels.contains(entry.label)
                )
            )
        }

        return agents.sorted { $0.label < $1.label }
    }

    func killProcess(pid: Int, force: Bool) async throws {
        let signal = force ? "-KILL" : "-TERM"
        let result = try await commandRunner.run("/bin/kill", [signal, "\(pid)"], timeout: 10)
        guard result.status == 0 else {
            throw LaunchControlError.commandFailed(
                launchctlFriendlyCommandFailure(
                    action: force ? "force kill process \(pid)" : "terminate process \(pid)",
                    stderr: result.stderr,
                    hint: "If this is a protected process, try another account or confirm that the job is not relaunching immediately."
                )
            )
        }
    }

    func revealBinary(path: String) async throws {
        let result = try await commandRunner.run("/usr/bin/open", ["-R", path], timeout: 10)
        guard result.status == 0 else {
            throw LaunchControlError.commandFailed(
                launchctlFriendlyCommandFailure(
                    action: "reveal file",
                    stderr: result.stderr,
                    hint: "Check that the path still exists and that Finder has permission to access it."
                )
            )
        }
    }

    func load(_ job: LaunchServiceJob) async throws {
        guard let plistPath = job.plistPath else {
            throw LaunchControlError.validation("No plist path available for this job")
        }

        let result = try await launchctlClient.bootstrap(domainTarget: job.domain.bootstrapTarget, plistPath: plistPath)
        guard result.status == 0 else {
            throw LaunchControlError.commandFailed(
                launchctlFriendlyCommandFailure(
                    action: "load \(job.label)",
                    stderr: result.stderr,
                    hint: job.domain == .systemAgent || job.domain == .systemDaemon
                        ? "System jobs often need administrator privileges or a signed plist placed in a system location."
                        : "Make sure the plist path is valid and the label is unique."
                )
            )
        }
    }

    func unload(_ job: LaunchServiceJob) async throws {
        let firstAttempt = try await launchctlClient.bootout(
            domainTarget: job.domain.bootstrapTarget,
            serviceTarget: job.label,
            plistPath: job.plistPath
        )

        if firstAttempt.status == 0 || firstAttempt.stderr.localizedCaseInsensitiveContains("No such process") {
            return
        }

        throw LaunchControlError.commandFailed(
            launchctlFriendlyCommandFailure(
                action: "unload \(job.label)",
                stderr: firstAttempt.stderr,
                hint: job.domain == .systemAgent || job.domain == .systemDaemon
                    ? "System jobs can fail to unload if they were loaded by another session or if permissions are restricted."
                    : "Refresh the list and try again if the job disappeared after a restart."
            )
        )
    }

    func kickstart(_ job: LaunchServiceJob) async throws {
        let result = try await launchctlClient.kickstart(
            serviceTarget: "\(job.domain.bootstrapTarget)/\(job.label)",
            force: true
        )
        guard result.status == 0 else {
            throw LaunchControlError.commandFailed(
                launchctlFriendlyCommandFailure(
                    action: "kickstart \(job.label)",
                    stderr: result.stderr,
                    hint: job.isLoaded
                        ? "The job is loaded, but launchctl may still refuse if the service cannot be restarted in its current domain."
                        : "Load the job first, then try kickstart again."
                )
            )
        }
    }

    func openPlistInEditor(_ job: LaunchServiceJob) async throws {
        guard let plistPath = job.plistPath else {
            throw LaunchControlError.validation("No plist path available for this job")
        }
        let result = try await commandRunner.run("/usr/bin/open", ["-a", "TextEdit", plistPath], timeout: 10)
        guard result.status == 0 else {
            throw LaunchControlError.commandFailed(
                launchctlFriendlyCommandFailure(
                    action: "open plist in TextEdit",
                    stderr: result.stderr,
                    hint: "If TextEdit cannot open the file, try revealing the plist in Finder and opening it manually."
                )
            )
        }
    }

    func revealJobFile(_ job: LaunchServiceJob) async throws {
        if let plistPath = job.plistPath {
            try await revealBinary(path: plistPath)
            return
        }
        if let program = job.program, program.hasPrefix("/") {
            try await revealBinary(path: program)
            return
        }
        throw LaunchControlError.validation("Nothing to reveal for this job")
    }

    func createOrUpdateManagedAgent(from draft: ScheduleDraft) async throws {
        let valid = try draft.validated()
        let plistURL = try plistURL(for: valid.label)

        var plist: [String: Any] = [
            "Label": valid.label,
            "ProgramArguments": [valid.commandPath] + splitShellArguments(valid.arguments),
            "RunAtLoad": valid.runAtLoad,
            "ProcessType": "Background",
            "StandardOutPath": "\(NSHomeDirectory())/Library/Logs/\(valid.label).out.log",
            "StandardErrorPath": "\(NSHomeDirectory())/Library/Logs/\(valid.label).err.log"
        ]

        switch valid.mode {
        case .calendar:
            plist["StartCalendarInterval"] = makeCalendarEntries(
                hour: valid.hour,
                minute: valid.minute,
                weekdays: valid.weekdays
            )
        case .interval:
            plist["StartInterval"] = valid.intervalSeconds
        }

        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        do {
            try data.write(to: plistURL, options: .atomic)
        } catch {
            throw LaunchControlError.io(error.localizedDescription)
        }

        let stdoutPath = "\(NSHomeDirectory())/Library/Logs/\(valid.label).out.log"
        let stderrPath = "\(NSHomeDirectory())/Library/Logs/\(valid.label).err.log"

        let job = LaunchServiceJob(
            id: valid.label,
            label: valid.label,
            domain: .userAgent,
            pid: nil,
            state: .unloaded,
            exitCode: nil,
            program: valid.commandPath,
            arguments: splitShellArguments(valid.arguments),
            runAtLoad: valid.runAtLoad,
            keepAliveDescription: nil,
            schedule: .none,
            plistPath: plistURL.path,
            environmentVariables: [:],
            machServices: [],
            workingDirectory: nil,
            standardOutPath: stdoutPath,
            standardErrorPath: stderrPath,
            watchPaths: [],
            queueDirectories: [],
            ownerAccountName: nil,
            groupOwnerAccountName: nil,
            rawKeys: []
        )

        try await unload(job)
        try await load(job)
    }

    func unloadManagedAgent(label: String) async throws {
        let plistURL = try plistURL(for: label)
        let job = LaunchServiceJob(
            id: label,
            label: label,
            domain: .userAgent,
            pid: nil,
            state: .unloaded,
            exitCode: nil,
            program: nil,
            arguments: [],
            runAtLoad: nil,
            keepAliveDescription: nil,
            schedule: .none,
            plistPath: plistURL.path,
            environmentVariables: [:],
            machServices: [],
            workingDirectory: nil,
            standardOutPath: nil,
            standardErrorPath: nil,
            watchPaths: [],
            queueDirectories: [],
            ownerAccountName: nil,
            groupOwnerAccountName: nil,
            rawKeys: []
        )
        try await unload(job)
    }

    func removeManagedAgent(label: String) async throws {
        let plistURL = try plistURL(for: label)
        try await unloadManagedAgent(label: label)

        if fileAccess.fileExists(at: plistURL) {
            do {
                try fileAccess.removeItem(at: plistURL)
            } catch {
                throw error
            }
        }
    }

    func diagnosticsSnapshot() async -> String {
        var lines: [String] = []
        lines.append("launchctl diagnostics")
        lines.append("Generated: \(Date().formatted(date: .abbreviated, time: .standard))")

        let commands: [(String, [String])] = [
            ("/usr/bin/whoami", []),
            ("/bin/launchctl", ["manageruid"]),
            ("/bin/launchctl", ["managerpid"]),
            ("/bin/launchctl", ["list"])
        ]

        for (path, args) in commands {
            do {
                let result = try await commandRunner.run(path, args, timeout: 20)
                lines.append("\n$ \(path) \(args.joined(separator: " "))")
                lines.append("status=\(result.status)")
                lines.append(result.stdout.ifEmpty("(no stdout)").trimmingCharacters(in: .whitespacesAndNewlines))
                if !result.stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    lines.append("stderr: \(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))")
                }
            } catch {
                lines.append("\n$ \(path) \(args.joined(separator: " "))")
                lines.append("failed: \(error.localizedDescription)")
            }
        }

        return lines.joined(separator: "\n")
    }

    private func fetchLoadedLaunchRecords(limit: Int) async throws -> [LoadedLaunchRecord] {
        let result = try await launchctlClient.list()
        guard result.status == 0 else {
            throw LaunchControlError.commandFailed(
                launchctlFriendlyCommandFailure(
                    action: "read launchctl list",
                    stderr: result.stderr,
                    hint: "This usually indicates a temporary launchd or permission issue. Refresh and try again."
                )
            )
        }

        let records = result.stdout
            .split(separator: "\n")
            .dropFirst()
            .compactMap { line -> LoadedLaunchRecord? in
                let values = line
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .split(whereSeparator: { $0.isWhitespace })

                guard values.count >= 3 else { return nil }

                let pidValue = String(values[0])
                let exitValue = String(values[1])
                let label = String(values[2])

                let pid = pidValue == "-" ? nil : Int(pidValue)
                let exit = exitValue == "-" ? nil : Int(exitValue)

                return LoadedLaunchRecord(label: label, pid: pid, exitCode: exit)
            }
            .prefix(limit)

        return Array(records)
    }

    private func scanKnownPlists() -> [PlistEntry] {
        let userDir = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library")
            .appendingPathComponent("LaunchAgents")

        let locations: [(LaunchDomain, URL)] = [
            (.userAgent, userDir),
            (.systemAgent, URL(fileURLWithPath: "/Library/LaunchAgents")),
            (.systemAgent, URL(fileURLWithPath: "/System/Library/LaunchAgents")),
            (.systemDaemon, URL(fileURLWithPath: "/Library/LaunchDaemons")),
            (.systemDaemon, URL(fileURLWithPath: "/System/Library/LaunchDaemons"))
        ]

        var entries: [PlistEntry] = []
        for (domain, folder) in locations {
            guard fileAccess.fileExists(at: folder) else { continue }
            guard let urls = try? fileAccess.contentsOfDirectory(at: folder) else {
                continue
            }

            for url in urls where url.pathExtension == "plist" {
                guard let parsed = parsePlist(at: url, domain: domain) else { continue }
                entries.append(parsed)
            }
        }

        return entries
    }

    private func parsePlist(at url: URL, domain: LaunchDomain) -> PlistEntry? {
        guard let data = try? fileAccess.readData(at: url) else { return nil }
        guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) else {
            return nil
        }
        guard let dict = plist as? [String: Any] else { return nil }
        guard let label = dict["Label"] as? String, !label.isEmpty else { return nil }

        let programArgs = (dict["ProgramArguments"] as? [String]) ?? []
        let program = (dict["Program"] as? String) ?? programArgs.first
        let arguments = programArgs.isEmpty ? [] : Array(programArgs.dropFirst())

        let runAtLoad = dict["RunAtLoad"] as? Bool
        let keepAliveDescription = keepAliveText(from: dict["KeepAlive"])
        let schedule = parseSchedule(from: dict)
        let environmentVariables = (dict["EnvironmentVariables"] as? [String: String]) ?? [:]
        let machServices = ((dict["MachServices"] as? [String: Any]) ?? [:]).keys.sorted()
        let workingDirectory = dict["WorkingDirectory"] as? String
        let standardOutPath = dict["StandardOutPath"] as? String
        let standardErrorPath = dict["StandardErrorPath"] as? String
        let watchPaths = (dict["WatchPaths"] as? [String]) ?? []
        let queueDirectories = (dict["QueueDirectories"] as? [String]) ?? []
        let fileAttributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let ownerAccountName = fileAttributes?[.ownerAccountName] as? String
        let groupOwnerAccountName = fileAttributes?[.groupOwnerAccountName] as? String
        let rawKeys = dict.keys.sorted()

        return PlistEntry(
            label: label,
            domain: domain,
            path: url.path,
            program: program,
            arguments: arguments,
            runAtLoad: runAtLoad,
            keepAliveDescription: keepAliveDescription,
            schedule: schedule,
            environmentVariables: environmentVariables,
            machServices: machServices,
            workingDirectory: workingDirectory,
            standardOutPath: standardOutPath,
            standardErrorPath: standardErrorPath,
            watchPaths: watchPaths,
            queueDirectories: queueDirectories,
            ownerAccountName: ownerAccountName,
            groupOwnerAccountName: groupOwnerAccountName,
            rawKeys: rawKeys
        )
    }

    private func parseSchedule(from dict: [String: Any]) -> LaunchSchedule {
        if let interval = dict["StartInterval"] as? Int, interval > 0 {
            return .interval(seconds: interval)
        }

        if let single = dict["StartCalendarInterval"] as? [String: Any] {
            let entries = parseCalendarEntries([single])
            if !entries.isEmpty {
                return .calendar(entries: entries)
            }
        }

        if let many = dict["StartCalendarInterval"] as? [[String: Any]] {
            let entries = parseCalendarEntries(many)
            if !entries.isEmpty {
                return .calendar(entries: entries)
            }
        }

        return .none
    }

    private func parseCalendarEntries(_ raws: [[String: Any]]) -> [CalendarSpec] {
        raws.compactMap { raw in
            let hour = (raw["Hour"] as? Int) ?? 0
            let minute = (raw["Minute"] as? Int) ?? 0
            let weekday = raw["Weekday"] as? Int
            return CalendarSpec(weekday: weekday, hour: hour, minute: minute)
        }
    }

    private func keepAliveText(from value: Any?) -> String? {
        guard let value else { return nil }

        if let boolValue = value as? Bool {
            return boolValue ? "true" : "false"
        }

        if let dictionary = value as? [String: Any] {
            return dictionary.keys.sorted().joined(separator: ", ")
        }

        return String(describing: value)
    }

    private func makeCalendarEntries(hour: Int, minute: Int, weekdays: Set<Int>) -> [[String: Int]] {
        if weekdays.isEmpty {
            return [["Hour": hour, "Minute": minute]]
        }

        return weekdays.sorted().map { weekday in
            ["Weekday": weekday, "Hour": hour, "Minute": minute]
        }
    }

    private func launchAgentsDirectory() throws -> URL {
        let dir = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library")
            .appendingPathComponent("LaunchAgents")

        if !fileAccess.fileExists(at: dir) {
            do {
                try fileAccess.createDirectory(at: dir)
            } catch {
                throw error
            }
        }

        return dir
    }

    private func plistURL(for label: String) throws -> URL {
        let dir = try launchAgentsDirectory()
        return dir.appendingPathComponent("\(label).plist")
    }

    private func stateFor(pid: Int?, exitCode: Int?, loaded: Bool) -> LaunchJobState {
        if let pid, pid > 0 {
            return .running
        }
        if loaded {
            if let exitCode, exitCode != 0 {
                return .crashed
            }
            return .loadedIdle
        }
        return .unloaded
    }

    private func parseProcessLine(_ line: Substring) -> RunningProcess? {
        let text = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        let fields = text.split(maxSplits: 7, whereSeparator: { $0.isWhitespace })
        guard fields.count >= 8 else { return nil }
        guard let pid = Int(fields[0]) else { return nil }
        let parentPID = Int(fields[1])
        let user = String(fields[2]).isEmpty ? nil : String(fields[2])
        let processState = String(fields[3]).isEmpty ? nil : String(fields[3])
        let threadCount: Int? = nil
        let uptime = String(fields[6]).isEmpty ? nil : String(fields[6])

        let cpuRaw = Double(fields[4]) ?? 0
        let rssKB = Double(fields[5]) ?? 0
        let command = String(fields[7])

        return RunningProcess(
            pid: pid,
            parentPID: parentPID,
            user: user,
            processState: processState,
            threadCount: threadCount,
            uptime: uptime,
            commandPath: command,
            cpu: cpuRaw,
            memoryMB: rssKB / 1024
        )
    }

}

func launchctlFriendlyCommandFailure(action: String, stderr: String, hint: String) -> String {
    let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
    let lowered = trimmed.lowercased()

    let reason: String
    if lowered.contains("permission denied") || lowered.contains("operation not permitted") {
        reason = "macOS denied permission while trying to \(action)."
    } else if lowered.contains("no such process") || lowered.contains("could not find service") {
        reason = "The target was not available when LaunchDeck tried to \(action)."
    } else if lowered.contains("input/output error") {
        reason = "launchd returned an I/O error while trying to \(action)."
    } else if lowered.contains("already loaded") || lowered.contains("already exists") {
        reason = "Launchctl reported that the service is already in the requested state."
    } else if !trimmed.isEmpty {
        reason = trimmed
    } else {
        reason = "LaunchDeck could not \(action)."
    }

    return "\(reason) \(hint)"
}

private struct PlistEntry {
    let label: String
    let domain: LaunchDomain
    let path: String
    let program: String?
    let arguments: [String]
    let runAtLoad: Bool?
    let keepAliveDescription: String?
    let schedule: LaunchSchedule
    let environmentVariables: [String: String]
    let machServices: [String]
    let workingDirectory: String?
    let standardOutPath: String?
    let standardErrorPath: String?
    let watchPaths: [String]
    let queueDirectories: [String]
    let ownerAccountName: String?
    let groupOwnerAccountName: String?
    let rawKeys: [String]
}
