import Foundation

struct ParsedLaunchAgent {
    let label: String
    let program: String
    let arguments: [String]
    let runAtLoad: Bool
    let schedule: LaunchSchedule
    let fileURL: URL
}

struct LaunchAgentParser {
    func scanScheduledAgents(loadedLabels: Set<String>, includeSystemLaunchAgents: Bool = true) throws -> [ScheduledAgent] {
        let directories = makeDirectories(includeSystemLaunchAgents: includeSystemLaunchAgents)

        var output: [ScheduledAgent] = []
        for directory in directories {
            guard FileManager.default.fileExists(atPath: directory.path) else { continue }

            let files: [URL]
            do {
                files = try FileManager.default.contentsOfDirectory(
                    at: directory,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                )
            } catch {
                throw LaunchControlError.io(error.localizedDescription)
            }

            for fileURL in files where fileURL.pathExtension == "plist" {
                guard let parsed = try parseAgent(at: fileURL) else { continue }
                guard case .none = parsed.schedule else {
                    output.append(makeScheduledAgent(from: parsed, isLoaded: loadedLabels.contains(parsed.label)))
                    continue
                }
            }
        }

        return output.sorted { lhs, rhs in
            if lhs.label == rhs.label {
                return lhs.fileURL.path < rhs.fileURL.path
            }
            return lhs.label < rhs.label
        }
    }

    func parseAgent(at fileURL: URL) throws -> ParsedLaunchAgent? {
        let dictionary = try readPlistDictionary(at: fileURL)
        guard let label = dictionary["Label"] as? String, !label.isEmpty else { return nil }

        let arguments = (dictionary["ProgramArguments"] as? [String]) ?? []
        let program = (dictionary["Program"] as? String) ?? arguments.first ?? ""
        let commandArguments = arguments.isEmpty ? [] : Array(arguments.dropFirst())
        let runAtLoad = (dictionary["RunAtLoad"] as? Bool) ?? false
        let schedule = parseSchedule(from: dictionary)

        return ParsedLaunchAgent(
            label: label,
            program: program,
            arguments: commandArguments,
            runAtLoad: runAtLoad,
            schedule: schedule,
            fileURL: fileURL
        )
    }

    func readPlistDictionary(at fileURL: URL) throws -> [String: Any] {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw LaunchControlError.io(error.localizedDescription)
        }

        let plist: Any
        do {
            plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        } catch {
            throw LaunchControlError.io("Invalid plist: \(fileURL.path)")
        }

        guard let dictionary = plist as? [String: Any] else {
            throw LaunchControlError.io("Unexpected plist format: \(fileURL.path)")
        }

        return dictionary
    }

    func parseSchedule(from dictionary: [String: Any]) -> LaunchSchedule {
        if let interval = dictionary["StartInterval"] as? Int, interval > 0 {
            return .interval(seconds: interval)
        }

        if let one = dictionary["StartCalendarInterval"] as? [String: Any] {
            let entries = parseCalendarEntries(from: [one])
            if !entries.isEmpty {
                return .calendar(entries: entries)
            }
        }

        if let many = dictionary["StartCalendarInterval"] as? [[String: Any]] {
            let entries = parseCalendarEntries(from: many)
            if !entries.isEmpty {
                return .calendar(entries: entries)
            }
        }

        return .none
    }

    func scheduleDescription(for schedule: LaunchSchedule) -> String {
        switch schedule {
        case .interval(let seconds):
            if seconds % 3600 == 0 {
                let hours = seconds / 3600
                return "Every \(hours) hour" + (hours == 1 ? "" : "s")
            }
            if seconds % 60 == 0 {
                let minutes = seconds / 60
                return "Every \(minutes) min"
            }
            return "Every \(seconds) sec"

        case .calendar(let entries):
            guard !entries.isEmpty else { return "Manual" }
            let ordered = entries.sorted { lhs, rhs in
                let w1 = lhs.weekday ?? 0
                let w2 = rhs.weekday ?? 0
                if w1 == w2 {
                    if lhs.hour == rhs.hour {
                        return lhs.minute < rhs.minute
                    }
                    return lhs.hour < rhs.hour
                }
                return w1 < w2
            }

            if let compact = compactWeekdayDescription(entries: ordered) {
                return compact
            }

            return ordered
                .map { entry in
                    let time = String(format: "%02d:%02d", entry.hour, entry.minute)
                    if let weekday = entry.weekday {
                        return "\(weekdayName(weekday)) \(time)"
                    }
                    return "Daily \(time)"
                }
                .joined(separator: ", ")

        case .none:
            return "Manual"
        }
    }

    func nextRun(for schedule: LaunchSchedule, from now: Date = Date()) -> Date? {
        let calendar = Calendar.current

        switch schedule {
        case .none:
            return nil
        case .interval(let seconds):
            return now.addingTimeInterval(TimeInterval(seconds))
        case .calendar(let entries):
            let candidates = entries.compactMap { entry -> Date? in
                var components = DateComponents()
                components.hour = entry.hour
                components.minute = entry.minute
                components.second = 0
                components.weekday = entry.weekday
                return calendar.nextDate(
                    after: now,
                    matching: components,
                    matchingPolicy: .nextTime,
                    repeatedTimePolicy: .first,
                    direction: .forward
                )
            }
            return candidates.min()
        }
    }

    func draft(from parsed: ParsedLaunchAgent) -> ScheduleDraft {
        var draft = ScheduleDraft()
        draft.label = parsed.label
        draft.commandPath = parsed.program
        draft.arguments = parsed.arguments.joined(separator: " ")
        draft.runAtLoad = parsed.runAtLoad

        switch parsed.schedule {
        case .interval(let seconds):
            draft.mode = .interval
            draft.intervalSeconds = seconds
        case .calendar(let entries):
            draft.mode = .calendar
            if let first = entries.first {
                draft.hour = first.hour
                draft.minute = first.minute
            }

            let weekdays = Set(entries.compactMap(\.weekday))
            draft.weekdays = weekdays
        case .none:
            draft.mode = .calendar
        }

        return draft
    }

    private func makeDirectories(includeSystemLaunchAgents: Bool) -> [URL] {
        var dirs = [
            URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library")
                .appendingPathComponent("LaunchAgents")
        ]

        if includeSystemLaunchAgents {
            dirs.append(URL(fileURLWithPath: "/Library/LaunchAgents"))
        }

        return dirs
    }

    private func parseCalendarEntries(from raws: [[String: Any]]) -> [CalendarSpec] {
        raws.compactMap { raw in
            let hour = raw["Hour"] as? Int ?? 0
            let minute = raw["Minute"] as? Int ?? 0
            let weekday = raw["Weekday"] as? Int
            return CalendarSpec(weekday: weekday, hour: hour, minute: minute)
        }
    }

    private func makeScheduledAgent(from parsed: ParsedLaunchAgent, isLoaded: Bool) -> ScheduledAgent {
        let mode: ScheduleMode
        switch parsed.schedule {
        case .calendar:
            mode = .calendar
        case .interval:
            mode = .interval
        case .none:
            mode = .calendar
        }

        return ScheduledAgent(
            label: parsed.label,
            mode: mode,
            scheduleDescription: scheduleDescription(for: parsed.schedule),
            nextRun: nextRun(for: parsed.schedule),
            isLoaded: isLoaded,
            fileURL: parsed.fileURL,
            commandPath: parsed.program,
            arguments: parsed.arguments,
            runAtLoad: parsed.runAtLoad
        )
    }

    private func compactWeekdayDescription(entries: [CalendarSpec]) -> String? {
        guard !entries.isEmpty else { return nil }
        let times = Set(entries.map { "\($0.hour):\($0.minute)" })
        guard times.count == 1 else { return nil }

        let weekdays = entries.compactMap(\.weekday).sorted()
        guard !weekdays.isEmpty else {
            let first = entries[0]
            return "Daily \(String(format: "%02d:%02d", first.hour, first.minute))"
        }

        let timeText = String(format: "%02d:%02d", entries[0].hour, entries[0].minute)
        if weekdays == [2, 3, 4, 5, 6] {
            return "Mon-Fri \(timeText)"
        }

        return weekdays.map(weekdayName).joined(separator: ", ") + " " + timeText
    }

    private func weekdayName(_ value: Int) -> String {
        let symbols = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        let index = max(1, min(7, value)) - 1
        return symbols[index]
    }
}
