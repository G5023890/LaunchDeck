import Foundation

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

struct ScheduleInput {
    var label: String
    var commandPath: String
    var arguments: String
    var hour: Int
    var minute: Int
    var weekdays: Set<Int>
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
        if hour < 0 || hour > 23 {
            throw LaunchControlError.validation("Hour должен быть 0..23")
        }
        if minute < 0 || minute > 59 {
            throw LaunchControlError.validation("Minute должен быть 0..59")
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
