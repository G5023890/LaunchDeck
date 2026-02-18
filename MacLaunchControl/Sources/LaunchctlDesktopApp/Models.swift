import Foundation

enum ScheduleMode: String, CaseIterable, Identifiable {
    case calendar
    case interval

    var id: String { rawValue }

    var title: String {
        switch self {
        case .calendar: return "По времени"
        case .interval: return "По интервалу"
        }
    }
}

enum IntervalUnit: String, CaseIterable, Identifiable {
    case minutes
    case hours
    case days

    var id: String { rawValue }

    var title: String {
        switch self {
        case .minutes: return "Минут"
        case .hours: return "Часов"
        case .days: return "Дней"
        }
    }

    var secondsMultiplier: Int {
        switch self {
        case .minutes: return 60
        case .hours: return 3600
        case .days: return 86400
        }
    }
}

struct RunningProcess: Identifiable {
    let id: Int
    let pid: Int
    let command: String
}

struct LaunchctlJob: Identifiable {
    let id: String
    let label: String
    let pid: String
    let status: String
}

struct ManagedAgent: Identifiable {
    let id: String
    let label: String
    let path: String
    let command: String
    let scheduleDescription: String
    let isLoaded: Bool
}

struct TimedLaunchItem: Identifiable {
    let id: String
    let label: String
    let path: String
    let scope: String
    let commandDisplay: String
    let commandPath: String
    let arguments: String
    let scheduleDescription: String
    let writable: Bool
    let runAtLoad: Bool
    let hour: Int?
    let minute: Int?
    let weekdays: Set<Int>
    let startIntervalSeconds: Int?
}

struct ScheduleInput {
    var label: String
    var commandPath: String
    var arguments: String
    var mode: ScheduleMode
    var hour: Int
    var minute: Int
    var weekdays: Set<Int>
    var intervalValue: Int
    var intervalUnit: IntervalUnit
    var runAtLoad: Bool

    func validate() throws {
        if label.isEmpty {
            throw LaunchControlError.validation("Укажите label")
        }
        if !label.starts(with: "com.") {
            throw LaunchControlError.validation("Label должен начинаться с com.")
        }
        if commandPath.isEmpty {
            throw LaunchControlError.validation("Укажите путь к команде")
        }

        switch mode {
        case .calendar:
            if hour < 0 || hour > 23 {
                throw LaunchControlError.validation("Hour должен быть 0..23")
            }
            if minute < 0 || minute > 59 {
                throw LaunchControlError.validation("Minute должен быть 0..59")
            }
        case .interval:
            if intervalValue < 1 {
                throw LaunchControlError.validation("Интервал должен быть >= 1")
            }
        }
    }
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
