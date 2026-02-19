import Foundation

struct LaunchAgentWriter {
    func rewriteScheduleAndRunAtLoad(fileURL: URL, draft: ScheduleDraft, parser: LaunchAgentParser) throws {
        var dictionary = try parser.readPlistDictionary(at: fileURL)

        dictionary["Label"] = draft.label
        dictionary["RunAtLoad"] = draft.runAtLoad
        switch draft.mode {
        case .calendar:
            dictionary.removeValue(forKey: "StartInterval")
            dictionary["StartCalendarInterval"] = makeCalendarValue(hour: draft.hour, minute: draft.minute, weekdays: draft.weekdays)
        case .interval:
            dictionary.removeValue(forKey: "StartCalendarInterval")
            dictionary["StartInterval"] = draft.intervalSeconds
        }

        try write(dictionary: dictionary, to: fileURL)
    }

    func createOrRewriteInUserLaunchAgents(draft: ScheduleDraft, parser: LaunchAgentParser) throws -> URL {
        let valid = try draft.validated()
        let directory = try ensureUserLaunchAgentsDirectory()
        let fileURL = directory.appendingPathComponent("\(valid.label).plist")

        var dictionary: [String: Any]
        if FileManager.default.fileExists(atPath: fileURL.path) {
            dictionary = try parser.readPlistDictionary(at: fileURL)
        } else {
            dictionary = [
                "Label": valid.label,
                "ProgramArguments": [valid.commandPath] + splitArguments(valid.arguments),
                "ProcessType": "Background",
                "StandardOutPath": "\(NSHomeDirectory())/Library/Logs/\(valid.label).out.log",
                "StandardErrorPath": "\(NSHomeDirectory())/Library/Logs/\(valid.label).err.log"
            ]
        }

        dictionary["Label"] = valid.label

        if let existingProgramArgs = dictionary["ProgramArguments"] as? [String], !existingProgramArgs.isEmpty {
            if existingProgramArgs.first?.isEmpty == false {
                dictionary["ProgramArguments"] = [valid.commandPath] + splitArguments(valid.arguments)
            }
        } else {
            dictionary["ProgramArguments"] = [valid.commandPath] + splitArguments(valid.arguments)
        }

        dictionary["RunAtLoad"] = valid.runAtLoad

        switch valid.mode {
        case .calendar:
            dictionary.removeValue(forKey: "StartInterval")
            dictionary["StartCalendarInterval"] = makeCalendarValue(
                hour: valid.hour,
                minute: valid.minute,
                weekdays: valid.weekdays
            )
        case .interval:
            dictionary.removeValue(forKey: "StartCalendarInterval")
            dictionary["StartInterval"] = valid.intervalSeconds
        }

        try write(dictionary: dictionary, to: fileURL)
        return fileURL
    }

    private func makeCalendarValue(hour: Int, minute: Int, weekdays: Set<Int>) -> Any {
        if weekdays.isEmpty {
            return ["Hour": hour, "Minute": minute]
        }

        return weekdays.sorted().map { weekday in
            ["Weekday": weekday, "Hour": hour, "Minute": minute]
        }
    }

    private func write(dictionary: [String: Any], to fileURL: URL) throws {
        let data: Data
        do {
            data = try PropertyListSerialization.data(fromPropertyList: dictionary, format: .xml, options: 0)
        } catch {
            throw LaunchControlError.io(error.localizedDescription)
        }

        do {
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw LaunchControlError.io(error.localizedDescription)
        }
    }

    private func ensureUserLaunchAgentsDirectory() throws -> URL {
        let directory = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library")
            .appendingPathComponent("LaunchAgents")

        if !FileManager.default.fileExists(atPath: directory.path) {
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            } catch {
                throw LaunchControlError.io(error.localizedDescription)
            }
        }

        return directory
    }

    private func splitArguments(_ raw: String) -> [String] {
        raw
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
    }
}
