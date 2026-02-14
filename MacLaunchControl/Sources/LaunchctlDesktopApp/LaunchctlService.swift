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

            let programArgs = dict["ProgramArguments"] as? [String] ?? []
            let command = programArgs.joined(separator: " ")
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

    func createOrUpdateAgent(input: ScheduleInput) throws {
        try input.validate()

        let args = splitArguments(input.arguments)
        let plistURL = try plistURL(for: input.label)

        var startCalendar: [[String: Int]] = []
        if input.weekdays.isEmpty {
            startCalendar = [["Hour": input.hour, "Minute": input.minute]]
        } else {
            for weekday in input.weekdays.sorted() {
                startCalendar.append([
                    "Weekday": weekday,
                    "Hour": input.hour,
                    "Minute": input.minute
                ])
            }
        }

        var plist: [String: Any] = [
            "Label": input.label,
            "ProgramArguments": [input.commandPath] + args,
            "RunAtLoad": input.runAtLoad,
            "StartCalendarInterval": startCalendar,
            "StandardOutPath": "\(NSHomeDirectory())/Library/Logs/\(input.label).out.log",
            "StandardErrorPath": "\(NSHomeDirectory())/Library/Logs/\(input.label).err.log"
        ]
        plist["ProcessType"] = "Background"

        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: plistURL, options: .atomic)

        try unloadIfNeeded(label: input.label)
        try bootstrap(plistPath: plistURL.path)
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

    private func scheduleDescription(from plist: [String: Any]) -> String {
        let runAtLoad = (plist["RunAtLoad"] as? Bool) == true ? "RunAtLoad" : ""
        if let calendar = plist["StartCalendarInterval"] as? [[String: Int]], !calendar.isEmpty {
            let chunks = calendar.map { item -> String in
                let weekday = item["Weekday"]
                let hour = item["Hour"] ?? 0
                let minute = item["Minute"] ?? 0
                if let weekday {
                    return "wd=\(weekday) \(String(format: "%02d:%02d", hour, minute))"
                }
                return String(format: "%02d:%02d", hour, minute)
            }
            let main = chunks.joined(separator: ", ")
            return runAtLoad.isEmpty ? main : "\(main); \(runAtLoad)"
        }
        return runAtLoad.isEmpty ? "manual" : runAtLoad
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
