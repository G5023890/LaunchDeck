import Foundation

enum SidebarSection: String, CaseIterable, Identifiable {
    case processes
    case launchServices
    case userAgents
    case systemAgents
    case systemDaemons
    case schedules
    case diagnostics

    var id: String { rawValue }

    var title: String {
        switch self {
        case .processes:
            return "Processes"
        case .launchServices:
            return "Launch Services"
        case .userAgents:
            return "User Agents"
        case .systemAgents:
            return "System Agents"
        case .systemDaemons:
            return "System Daemons"
        case .schedules:
            return "Schedules"
        case .diagnostics:
            return "Diagnostics"
        }
    }

    var symbol: String {
        switch self {
        case .processes:
            return "waveform.path.ecg"
        case .launchServices:
            return "shippingbox"
        case .userAgents:
            return "person.crop.square"
        case .systemAgents:
            return "externaldrive.badge.person.crop"
        case .systemDaemons:
            return "server.rack"
        case .schedules:
            return "calendar.badge.clock"
        case .diagnostics:
            return "stethoscope"
        }
    }
}

struct RunningProcess: Identifiable, Hashable {
    let pid: Int
    let command: String
    let cpu: Double
    let memoryMB: Double

    var id: Int { pid }

    var pidText: String { String(pid) }

    var cpuText: String { String(format: "%.1f%%", cpu) }

    var memoryText: String { String(format: "%.1f MB", memoryMB) }

    var binaryPath: String? {
        let first = command.split(separator: " ").first.map(String.init) ?? command
        return first.hasPrefix("/") ? first : nil
    }
}

enum LaunchDomain: String, CaseIterable, Codable, Hashable {
    case userAgent
    case systemAgent
    case systemDaemon
    case unknown

    var title: String {
        switch self {
        case .userAgent:
            return "User"
        case .systemAgent:
            return "System Agent"
        case .systemDaemon:
            return "System Daemon"
        case .unknown:
            return "Unknown"
        }
    }

    var bootstrapTarget: String {
        switch self {
        case .userAgent:
            return "gui/\(getuid())"
        case .systemAgent, .systemDaemon:
            return "system"
        case .unknown:
            return "gui/\(getuid())"
        }
    }
}

enum LaunchJobState: String, Codable, Hashable {
    case running
    case loadedIdle
    case crashed
    case unloaded

    var title: String {
        switch self {
        case .running:
            return "Running"
        case .loadedIdle:
            return "Loaded"
        case .crashed:
            return "Crashed"
        case .unloaded:
            return "Unloaded"
        }
    }

    var symbol: String {
        switch self {
        case .running:
            return "play.fill"
        case .loadedIdle:
            return "pause.fill"
        case .crashed:
            return "xmark.octagon.fill"
        case .unloaded:
            return "tray"
        }
    }
}

struct CalendarSpec: Hashable, Codable {
    let weekday: Int?
    let hour: Int
    let minute: Int
}

enum LaunchSchedule: Hashable, Codable {
    case interval(seconds: Int)
    case calendar(entries: [CalendarSpec])
    case none

    var modeTitle: String {
        switch self {
        case .interval:
            return "Interval"
        case .calendar:
            return "Calendar"
        case .none:
            return "Manual"
        }
    }
}

struct LaunchServiceJob: Identifiable, Hashable {
    let id: String
    let label: String
    let domain: LaunchDomain
    let pid: Int?
    let state: LaunchJobState
    let exitCode: Int?
    let program: String?
    let arguments: [String]
    let runAtLoad: Bool?
    let keepAliveDescription: String?
    let schedule: LaunchSchedule
    let plistPath: String?

    var pidText: String { pid.map(String.init) ?? "-" }

    var exitCodeText: String { exitCode.map(String.init) ?? "-" }
}

struct ManagedAgent: Identifiable, Hashable {
    let id: String
    let label: String
    let plistPath: String
    let command: String
    let schedule: LaunchSchedule
    let runAtLoad: Bool
    let isLoaded: Bool

    var modeTitle: String { schedule.modeTitle }
}

enum ScheduleBuilderMode: String, CaseIterable, Identifiable {
    case calendar
    case interval

    var id: String { rawValue }

    var title: String {
        switch self {
        case .calendar:
            return "Calendar"
        case .interval:
            return "Interval"
        }
    }
}

struct ScheduleDraft {
    var label: String = "com.launchctl.schedule.sample"
    var commandPath: String = "/usr/bin/say"
    var arguments: String = "Launch control ready"
    var runAtLoad: Bool = false

    var mode: ScheduleBuilderMode = .calendar
    var hour: Int = 9
    var minute: Int = 0
    var weekdays: Set<Int> = [2, 3, 4, 5, 6]

    var intervalSeconds: Int = 900

    func validated() throws -> ScheduleDraft {
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPath = commandPath.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedLabel.isEmpty {
            throw LaunchControlError.validation("Label is required")
        }
        if !trimmedLabel.hasPrefix("com.") {
            throw LaunchControlError.validation("Label must start with com.")
        }
        if trimmedPath.isEmpty {
            throw LaunchControlError.validation("Command path is required")
        }
        if mode == .interval, intervalSeconds < 60 {
            throw LaunchControlError.validation("Interval must be >= 60 seconds")
        }
        if mode == .calendar {
            if hour < 0 || hour > 23 {
                throw LaunchControlError.validation("Hour must be in 0...23")
            }
            if minute < 0 || minute > 59 {
                throw LaunchControlError.validation("Minute must be in 0...59")
            }
        }

        var copy = self
        copy.label = trimmedLabel
        copy.commandPath = trimmedPath
        copy.arguments = arguments.trimmingCharacters(in: .whitespacesAndNewlines)
        return copy
    }
}

struct CommandResult {
    let stdout: String
    let stderr: String
    let status: Int32
}

enum LaunchControlError: LocalizedError {
    case commandFailed(String)
    case validation(String)
    case io(String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let text):
            return text
        case .validation(let text):
            return text
        case .io(let text):
            return text
        }
    }
}

struct LoadedLaunchRecord {
    let label: String
    let pid: Int?
    let exitCode: Int?
}
