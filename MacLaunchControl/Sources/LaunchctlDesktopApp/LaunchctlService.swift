import Foundation

struct CommandResult {
    let stdout: String
    let stderr: String
    let status: Int32
}

enum CommandRunner {
    static func run(_ launchPath: String, _ arguments: [String], timeout: TimeInterval = 8) throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        try process.run()

        var outData = Data()
        var errData = Data()
        let group = DispatchGroup()

        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            outData = outPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }

        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }

        if process.isRunning {
            process.terminate()
            throw LaunchControlError.commandFailed("Команда зависла по таймауту: \(launchPath) \(arguments.joined(separator: " "))")
        }

        process.waitUntilExit()
        group.wait()

        let stdout = String(data: outData, encoding: .utf8) ?? ""
        let stderr = String(data: errData, encoding: .utf8) ?? ""

        return CommandResult(stdout: stdout, stderr: stderr, status: process.terminationStatus)
    }
}

struct LaunchctlService {
    private let managedPrefix = "com.launchctl.schedule."

    func fetchRunningProcesses(limit: Int = 250) throws -> [RunningProcess] {
        let result = try CommandRunner.run("/bin/ps", ["-axo", "pid=,comm="])
        if result.status != 0 {
            throw LaunchControlError.commandFailed(result.stderr.isEmpty ? "ps завершился с ошибкой" : result.stderr)
        }

        return result.stdout
            .split(separator: "\n")
            .compactMap { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { return nil }
                let parts = trimmed.split(maxSplits: 1, whereSeparator: { $0.isWhitespace })
                guard parts.count == 2, let pid = Int(parts[0]) else { return nil }
                return RunningProcess(id: pid, pid: pid, command: String(parts[1]))
            }
            .prefix(limit)
            .map { $0 }
    }

    func fetchLaunchctlJobs(limit: Int = 300) throws -> [LaunchctlJob] {
        let result = try CommandRunner.run("/bin/launchctl", ["list"])
        if result.status != 0 {
            throw LaunchControlError.commandFailed(result.stderr.isEmpty ? "launchctl list завершился с ошибкой" : result.stderr)
        }

        return result.stdout
            .split(separator: "\n")
            .dropFirst()
            .compactMap { line in
                let text = line.trimmingCharacters(in: .whitespaces)
                guard !text.isEmpty else { return nil }
                let parts = text.split(whereSeparator: { $0.isWhitespace })
                guard parts.count >= 3 else { return nil }
                let pid = String(parts[0])
                let status = String(parts[1])
                let label = String(parts[2])
                return LaunchctlJob(id: label, label: label, pid: pid, status: status)
            }
            .prefix(limit)
            .map { $0 }
    }

    func fetchManagedAgents() throws -> [ManagedAgent] {
        let launchAgentsDir = try launchAgentsDirectory()
        let fileURLs = try FileManager.default.contentsOfDirectory(
            at: launchAgentsDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        let jobs = (try? fetchLaunchctlJobs(limit: 2000)) ?? []
        let loadedLabels = Set(jobs.map(\ .label))

        var agents: [ManagedAgent] = []

        for fileURL in fileURLs where fileURL.pathExtension == "plist" {
            guard let raw = try? Data(contentsOf: fileURL),
                  let plist = try? PropertyListSerialization.propertyList(from: raw, options: [], format: nil),
                  let dict = plist as? [String: Any],
                  let label = dict["Label"] as? String,
                  label.hasPrefix(managedPrefix)
            else {
                continue
            }

            let command = commandInfo(from: dict).display
            let schedule = scheduleDescription(from: dict)

            agents.append(
                ManagedAgent(
                    id: label,
                    label: label,
                    path: fileURL.path,
                    command: command,
                    scheduleDescription: schedule,
                    isLoaded: loadedLabels.contains(label)
                )
            )
        }

        return agents.sorted { $0.label < $1.label }
    }

    func fetchTimedJobs() throws -> [TimedLaunchItem] {
        let jobs = (try? fetchLaunchctlJobs(limit: 3000)) ?? []
        let loadedLabels = Set(jobs.map(\ .label))

        let dirs: [(path: String, scope: String)] = [
            ("\(NSHomeDirectory())/Library/LaunchAgents", "user"),
            ("/Library/LaunchAgents", "system-agent"),
            ("/Library/LaunchDaemons", "system-daemon")
        ]

        var items: [TimedLaunchItem] = []

        for dir in dirs {
            let root = URL(fileURLWithPath: dir.path)
            guard FileManager.default.fileExists(atPath: root.path) else { continue }

            let files = (try? FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )) ?? []

            for fileURL in files where fileURL.pathExtension == "plist" {
                guard let data = try? Data(contentsOf: fileURL),
                      let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
                      let dict = plist as? [String: Any]
                else {
                    continue
                }

                let calendars = parseStartCalendarIntervals(dict["StartCalendarInterval"])
                let startInterval = intValue(dict["StartInterval"])
                guard !calendars.isEmpty || startInterval != nil else {
                    continue
                }

                let label = (dict["Label"] as? String) ?? fileURL.deletingPathExtension().lastPathComponent
                let command = commandInfo(from: dict)
                let timerParts = timerInputParts(from: dict)
                let writable = FileManager.default.isWritableFile(atPath: fileURL.path)
                let runAtLoad = (dict["RunAtLoad"] as? Bool) ?? false
                let loadedMark = loadedLabels.contains(label) ? "loaded" : "not-loaded"

                items.append(
                    TimedLaunchItem(
                        id: "\(label)|\(fileURL.path)",
                        label: label,
                        path: fileURL.path,
                        scope: "\(dir.scope) / \(loadedMark)",
                        commandDisplay: command.display,
                        commandPath: command.path,
                        arguments: command.arguments,
                        scheduleDescription: scheduleDescription(from: dict),
                        writable: writable,
                        runAtLoad: runAtLoad,
                        hour: timerParts.hour,
                        minute: timerParts.minute,
                        weekdays: timerParts.weekdays,
                        startIntervalSeconds: timerParts.startInterval
                    )
                )
            }
        }

        return items.sorted { lhs, rhs in
            if lhs.label == rhs.label {
                return lhs.path < rhs.path
            }
            return lhs.label < rhs.label
        }
    }

    func createOrUpdateAgent(input: ScheduleInput) throws {
        try input.validate()

        let args = splitArguments(input.arguments)
        let plistURL = try plistURL(for: input.label)

        var plist: [String: Any] = [
            "Label": input.label,
            "ProgramArguments": [input.commandPath] + args,
            "RunAtLoad": input.runAtLoad,
            "StandardOutPath": "\(NSHomeDirectory())/Library/Logs/\(input.label).out.log",
            "StandardErrorPath": "\(NSHomeDirectory())/Library/Logs/\(input.label).err.log",
            "ProcessType": "Background"
        ]

        applyTimer(input: input, plist: &plist)

        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: plistURL, options: .atomic)

        try unloadIfNeeded(label: input.label)
        try bootstrap(plistPath: plistURL.path)
    }

    func updateTimer(at plistPath: String, input: ScheduleInput) throws {
        try input.validate()

        guard FileManager.default.isWritableFile(atPath: plistPath) else {
            throw LaunchControlError.validation("Нет прав на запись: \(plistPath)")
        }

        let url = URL(fileURLWithPath: plistPath)
        let data = try Data(contentsOf: url)
        guard let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            throw LaunchControlError.io("Некорректный plist: \(plistPath)")
        }

        var updated = plist
        updated["RunAtLoad"] = input.runAtLoad
        applyTimer(input: input, plist: &updated)

        let updatedData = try PropertyListSerialization.data(fromPropertyList: updated, format: .xml, options: 0)
        try updatedData.write(to: url, options: .atomic)

        let label = (updated["Label"] as? String) ?? input.label
        try reload(label: label, plistPath: plistPath)
    }

    func unload(label: String) throws {
        try unloadIfNeeded(label: label)
    }

    func removeAgent(label: String) throws {
        let url = try plistURL(for: label)
        try unloadIfNeeded(label: label)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    private func applyTimer(input: ScheduleInput, plist: inout [String: Any]) {
        switch input.mode {
        case .calendar:
            plist["StartCalendarInterval"] = buildCalendar(from: input)
            plist.removeValue(forKey: "StartInterval")
        case .interval:
            plist["StartInterval"] = input.intervalValue * input.intervalUnit.secondsMultiplier
            plist.removeValue(forKey: "StartCalendarInterval")
        }
    }

    private func buildCalendar(from input: ScheduleInput) -> [[String: Int]] {
        if input.weekdays.isEmpty {
            return [["Hour": input.hour, "Minute": input.minute]]
        }

        return input.weekdays.sorted().map { weekday in
            [
                "Weekday": weekday,
                "Hour": input.hour,
                "Minute": input.minute
            ]
        }
    }

    private func timerInputParts(from plist: [String: Any]) -> (hour: Int?, minute: Int?, weekdays: Set<Int>, startInterval: Int?) {
        let startInterval = intValue(plist["StartInterval"])
        let calendars = parseStartCalendarIntervals(plist["StartCalendarInterval"])

        guard !calendars.isEmpty else {
            return (nil, nil, [], startInterval)
        }

        var weekdays: Set<Int> = []
        for item in calendars {
            if let wd = item["Weekday"] {
                weekdays.insert(normalizeWeekday(wd))
            }
        }

        let first = calendars[0]
        return (first["Hour"], first["Minute"], weekdays, startInterval)
    }

    private func commandInfo(from plist: [String: Any]) -> (display: String, path: String, arguments: String) {
        if let args = plist["ProgramArguments"] as? [String], !args.isEmpty {
            let path = args[0]
            let tail = Array(args.dropFirst())
            return (args.joined(separator: " "), path, tail.joined(separator: " "))
        }

        if let program = plist["Program"] as? String {
            return (program, program, "")
        }

        return ("", "", "")
    }

    private func parseStartCalendarIntervals(_ raw: Any?) -> [[String: Int]] {
        if let one = raw as? [String: Any] {
            return [one.compactMapValues { intValue($0) }]
        }

        if let many = raw as? [[String: Any]] {
            return many.map { $0.compactMapValues { intValue($0) } }
        }

        return []
    }

    private func intValue(_ raw: Any?) -> Int? {
        if let intValue = raw as? Int { return intValue }
        if let number = raw as? NSNumber { return number.intValue }
        if let text = raw as? String, let parsed = Int(text) { return parsed }
        return nil
    }

    private func normalizeWeekday(_ weekday: Int) -> Int {
        if weekday == 7 { return 0 }
        return weekday
    }

    private func reload(label: String, plistPath: String) throws {
        let uid = getuid()

        if plistPath.hasPrefix("/Library/LaunchDaemons/") {
            _ = try? CommandRunner.run("/bin/launchctl", ["bootout", "system/\(label)"])
            let result = try CommandRunner.run("/bin/launchctl", ["bootstrap", "system", plistPath])
            if result.status != 0 {
                throw LaunchControlError.commandFailed(result.stderr.isEmpty ? "Не удалось перезагрузить system daemon" : result.stderr)
            }
            return
        }

        _ = try? CommandRunner.run("/bin/launchctl", ["bootout", "gui/\(uid)/\(label)"])
        let result = try CommandRunner.run("/bin/launchctl", ["bootstrap", "gui/\(uid)", plistPath])
        if result.status != 0 {
            throw LaunchControlError.commandFailed(result.stderr.isEmpty ? "Не удалось перезагрузить задачу" : result.stderr)
        }
    }

    private func scheduleDescription(from plist: [String: Any]) -> String {
        var chunks: [String] = []

        if let startInterval = intValue(plist["StartInterval"]) {
            chunks.append("every \(startInterval)s")
        }

        let calendars = parseStartCalendarIntervals(plist["StartCalendarInterval"])
        if !calendars.isEmpty {
            let calendarChunks = calendars.map { item -> String in
                let weekday = item["Weekday"]
                let hour = item["Hour"] ?? 0
                let minute = item["Minute"] ?? 0
                if let weekday {
                    return "wd=\(normalizeWeekday(weekday)) \(String(format: "%02d:%02d", hour, minute))"
                }
                return String(format: "%02d:%02d", hour, minute)
            }
            chunks.append(calendarChunks.joined(separator: ", "))
        }

        if (plist["RunAtLoad"] as? Bool) == true {
            chunks.append("RunAtLoad")
        }

        return chunks.isEmpty ? "manual" : chunks.joined(separator: "; ")
    }

    private func splitArguments(_ raw: String) -> [String] {
        raw
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
    }

    private func launchAgentsDirectory() throws -> URL {
        let url = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library")
            .appendingPathComponent("LaunchAgents")

        if !FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }

        return url
    }

    private func plistURL(for label: String) throws -> URL {
        let dir = try launchAgentsDirectory()
        return dir.appendingPathComponent("\(label).plist")
    }

    private func unloadIfNeeded(label: String) throws {
        let uid = getuid()
        _ = try? CommandRunner.run("/bin/launchctl", ["bootout", "gui/\(uid)/\(label)"])
    }

    private func bootstrap(plistPath: String) throws {
        let uid = getuid()
        let result = try CommandRunner.run("/bin/launchctl", ["bootstrap", "gui/\(uid)", plistPath])
        if result.status != 0 {
            throw LaunchControlError.commandFailed(result.stderr.isEmpty ? "launchctl bootstrap завершился с ошибкой" : result.stderr)
        }
    }
}
