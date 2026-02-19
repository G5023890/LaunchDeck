import Foundation

struct LaunchctlService {
    private let shell = ShellExecutor()
    private let managedPrefix = "com.launchctl.schedule."

    func fetchRunningProcesses(limit: Int = 400) async throws -> [RunningProcess] {
        let result = try await shell.run("/bin/ps", ["-axo", "pid=,ppid=,user=,pcpu=,rss=,etime=,comm="])
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
            urls = try FileManager.default.contentsOfDirectory(
                at: agentsDir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
        } catch {
            throw LaunchControlError.io(error.localizedDescription)
        }

        var agents: [ManagedAgent] = []

        for url in urls where url.pathExtension == "plist" {
            guard let entry = parsePlist(at: url, domain: .userAgent),
                  entry.label.hasPrefix(managedPrefix)
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
        let result = try await shell.run("/bin/kill", [signal, "\(pid)"])
        guard result.status == 0 else {
            throw LaunchControlError.commandFailed(result.stderr.ifEmpty("kill failed"))
        }
    }

    func revealBinary(path: String) async throws {
        let result = try await shell.run("/usr/bin/open", ["-R", path])
        guard result.status == 0 else {
            throw LaunchControlError.commandFailed(result.stderr.ifEmpty("Failed to reveal file"))
        }
    }

    func load(_ job: LaunchServiceJob) async throws {
        guard let plistPath = job.plistPath else {
            throw LaunchControlError.validation("No plist path available for this job")
        }

        let target = job.domain.bootstrapTarget
        let result = try await shell.run("/bin/launchctl", ["bootstrap", target, plistPath], timeout: 20)
        guard result.status == 0 else {
            throw LaunchControlError.commandFailed(result.stderr.ifEmpty("bootstrap failed"))
        }
    }

    func unload(_ job: LaunchServiceJob) async throws {
        let target = job.domain.bootstrapTarget

        let firstAttempt: CommandResult
        if let plistPath = job.plistPath {
            firstAttempt = try await shell.run("/bin/launchctl", ["bootout", target, plistPath], timeout: 20)
        } else {
            firstAttempt = try await shell.run("/bin/launchctl", ["bootout", "\(target)/\(job.label)"], timeout: 20)
        }

        if firstAttempt.status == 0 || firstAttempt.stderr.localizedCaseInsensitiveContains("No such process") {
            return
        }

        throw LaunchControlError.commandFailed(firstAttempt.stderr.ifEmpty("bootout failed"))
    }

    func kickstart(_ job: LaunchServiceJob) async throws {
        let target = job.domain.bootstrapTarget
        let result = try await shell.run(
            "/bin/launchctl",
            ["kickstart", "-k", "\(target)/\(job.label)"],
            timeout: 20
        )
        guard result.status == 0 else {
            throw LaunchControlError.commandFailed(result.stderr.ifEmpty("kickstart failed"))
        }
    }

    func openPlistInEditor(_ job: LaunchServiceJob) async throws {
        guard let plistPath = job.plistPath else {
            throw LaunchControlError.validation("No plist path available for this job")
        }
        let result = try await shell.run("/usr/bin/open", ["-a", "TextEdit", plistPath])
        guard result.status == 0 else {
            throw LaunchControlError.commandFailed(result.stderr.ifEmpty("Failed to open plist"))
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
            "ProgramArguments": [valid.commandPath] + splitArguments(valid.arguments),
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

        let job = LaunchServiceJob(
            id: valid.label,
            label: valid.label,
            domain: .userAgent,
            pid: nil,
            state: .unloaded,
            exitCode: nil,
            program: valid.commandPath,
            arguments: splitArguments(valid.arguments),
            runAtLoad: valid.runAtLoad,
            keepAliveDescription: nil,
            schedule: .none,
            plistPath: plistURL.path,
            environmentVariables: [:],
            machServices: [],
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
            rawKeys: []
        )
        try await unload(job)
    }

    func removeManagedAgent(label: String) async throws {
        let plistURL = try plistURL(for: label)
        try await unloadManagedAgent(label: label)

        if FileManager.default.fileExists(atPath: plistURL.path) {
            do {
                try FileManager.default.removeItem(at: plistURL)
            } catch {
                throw LaunchControlError.io(error.localizedDescription)
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
                let result = try await shell.run(path, args, timeout: 20)
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
        let result = try await shell.run("/bin/launchctl", ["list"], timeout: 20)
        guard result.status == 0 else {
            throw LaunchControlError.commandFailed(result.stderr.ifEmpty("launchctl list failed"))
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
            guard FileManager.default.fileExists(atPath: folder.path) else { continue }
            guard let urls = try? FileManager.default.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else {
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
        guard let data = try? Data(contentsOf: url) else { return nil }
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

    private func splitArguments(_ raw: String) -> [String] {
        raw
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
    }

    private func launchAgentsDirectory() throws -> URL {
        let dir = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library")
            .appendingPathComponent("LaunchAgents")

        if !FileManager.default.fileExists(atPath: dir.path) {
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            } catch {
                throw LaunchControlError.io(error.localizedDescription)
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

        let fields = text.split(maxSplits: 6, whereSeparator: { $0.isWhitespace })
        guard fields.count >= 7 else { return nil }
        guard let pid = Int(fields[0]) else { return nil }
        let parentPID = Int(fields[1])
        let user = String(fields[2]).isEmpty ? nil : String(fields[2])
        let threadCount: Int? = nil
        let uptime = String(fields[5]).isEmpty ? nil : String(fields[5])

        let cpuRaw = Double(fields[3]) ?? 0
        let rssKB = Double(fields[4]) ?? 0
        let command = String(fields[6])

        return RunningProcess(
            pid: pid,
            parentPID: parentPID,
            user: user,
            threadCount: threadCount,
            uptime: uptime,
            commandPath: command,
            cpu: cpuRaw,
            memoryMB: rssKB / 1024
        )
    }
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
    let rawKeys: [String]
}

private extension String {
    func ifEmpty(_ fallback: String) -> String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : self
    }
}
