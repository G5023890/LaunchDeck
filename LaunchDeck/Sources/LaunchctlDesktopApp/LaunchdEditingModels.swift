import CoreFoundation
import Foundation

enum ValidationSeverity: String, Hashable, Codable, CaseIterable, Sendable {
    case error
    case warning
    case notice

    var title: String {
        switch self {
        case .error:
            return "Error"
        case .warning:
            return "Warning"
        case .notice:
            return "Notice"
        }
    }

    var symbol: String {
        switch self {
        case .error:
            return "xmark.octagon.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .notice:
            return "info.circle.fill"
        }
    }
}

struct ValidationIssue: Identifiable, Hashable, Sendable {
    let id: String
    let severity: ValidationSeverity
    let title: String
    let message: String
    let path: String?

    init(
        id: String = UUID().uuidString,
        severity: ValidationSeverity,
        title: String,
        message: String,
        path: String? = nil
    ) {
        self.id = id
        self.severity = severity
        self.title = title
        self.message = message
        self.path = path
    }
}

struct LaunchdValidationReport: Hashable, Sendable {
    let issues: [ValidationIssue]
    let normalizedPlistText: String

    var errors: [ValidationIssue] { issues.filter { $0.severity == .error } }
    var warnings: [ValidationIssue] { issues.filter { $0.severity == .warning } }
    var notices: [ValidationIssue] { issues.filter { $0.severity == .notice } }
    var canApply: Bool { errors.isEmpty }
    var summaryText: String {
        let parts = [
            errors.isEmpty ? nil : "\(errors.count) error" + (errors.count == 1 ? "" : "s"),
            warnings.isEmpty ? nil : "\(warnings.count) warning" + (warnings.count == 1 ? "" : "s"),
            notices.isEmpty ? nil : "\(notices.count) notice" + (notices.count == 1 ? "" : "s")
        ].compactMap { $0 }

        guard !parts.isEmpty else { return "No issues found" }
        return parts.joined(separator: ", ")
    }
}

struct BackupSnapshot: Identifiable, Hashable, Sendable {
    let id: String
    let label: String
    let sourceURL: URL
    let backupURL: URL
    let createdAt: Date
    let fileSizeBytes: Int64
    let originalModificationDate: Date?

    var sizeText: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: fileSizeBytes)
    }
}

enum LaunchdApplyReloadOption: String, Hashable, Codable, CaseIterable, Sendable {
    case none
    case bootstrap
    case bootstrapAndKickstart

    var title: String {
        switch self {
        case .none:
            return "Do not reload"
        case .bootstrap:
            return "Bootstrap after apply"
        case .bootstrapAndKickstart:
            return "Bootstrap and kickstart"
        }
    }
}

struct ApplyPlan: Hashable, Sendable {
    let sourceURL: URL
    let job: EditableLaunchJob
    let validationReport: LaunchdValidationReport
    let normalizedPlistData: Data
    let normalizedPlistText: String
    let reloadOption: LaunchdApplyReloadOption
    let snapshotLabel: String
}

struct ApplyResult: Hashable, Sendable {
    let plan: ApplyPlan
    let backupSnapshot: BackupSnapshot
    let appliedURL: URL
    let didBootstrap: Bool
    let didKickstart: Bool
    let launchctlOutput: String?
    let summary: String
    let issues: [ValidationIssue]
}

enum LaunchdKeepAliveSetting: Hashable, Sendable {
    case disabled
    case enabled
    case conditions([String: Bool])
}

struct EditableLaunchJob: Identifiable, Hashable, Sendable {
    let id: String
    var sourceJobID: String?
    var fileURL: URL
    var domain: LaunchDomain
    var lastModified: Date?
    var isLoaded: Bool
    var label: String
    var program: String?
    var programArguments: [String]
    var runAtLoad: Bool
    var keepAlive: LaunchdKeepAliveSetting
    var startInterval: Int?
    var startCalendarIntervals: [CalendarSpec]
    var workingDirectory: String?
    var standardOutPath: String?
    var standardErrorPath: String?
    var environmentVariables: [String: String]
    var additionalFields: [String: PlistValue]

    init(
        sourceJobID: String? = nil,
        fileURL: URL,
        domain: LaunchDomain,
        lastModified: Date? = nil,
        isLoaded: Bool = false,
        label: String,
        program: String?,
        programArguments: [String],
        runAtLoad: Bool,
        keepAlive: LaunchdKeepAliveSetting,
        startInterval: Int?,
        startCalendarIntervals: [CalendarSpec],
        workingDirectory: String?,
        standardOutPath: String?,
        standardErrorPath: String?,
        environmentVariables: [String: String],
        additionalFields: [String: PlistValue] = [:]
    ) {
        self.sourceJobID = sourceJobID
        self.fileURL = fileURL
        self.domain = domain
        self.lastModified = lastModified
        self.isLoaded = isLoaded
        self.label = label
        self.program = program
        self.programArguments = programArguments
        self.runAtLoad = runAtLoad
        self.keepAlive = keepAlive
        self.startInterval = startInterval
        self.startCalendarIntervals = startCalendarIntervals
        self.workingDirectory = workingDirectory
        self.standardOutPath = standardOutPath
        self.standardErrorPath = standardErrorPath
        self.environmentVariables = environmentVariables
        self.additionalFields = additionalFields
        self.id = fileURL.path
    }

    var effectiveProgramArguments: [String] {
        let resolvedProgram = program ?? programArguments.first
        guard let resolvedProgram else { return programArguments }
        let tail = programArguments.first == resolvedProgram ? Array(programArguments.dropFirst()) : programArguments
        return [resolvedProgram] + tail
    }

    var isCalendarScheduled: Bool { !startCalendarIntervals.isEmpty }
    var isIntervalScheduled: Bool { startInterval != nil }

    func plistDictionary() -> [String: Any] {
        var dictionary: [String: Any] = additionalFields.mapValues { $0.foundationValue }

        dictionary["Label"] = label
        if let program {
            dictionary["Program"] = program
        }
        if !effectiveProgramArguments.isEmpty {
            dictionary["ProgramArguments"] = effectiveProgramArguments
        }
        dictionary["RunAtLoad"] = runAtLoad

        switch keepAlive {
        case .disabled:
            if additionalFields["KeepAlive"] == nil {
                dictionary.removeValue(forKey: "KeepAlive")
            }
        case .enabled:
            dictionary["KeepAlive"] = true
        case .conditions(let conditions):
            dictionary["KeepAlive"] = conditions
        }

        if let startInterval {
            dictionary["StartInterval"] = startInterval
        } else {
            dictionary.removeValue(forKey: "StartInterval")
        }

        if !startCalendarIntervals.isEmpty {
            let mapped = startCalendarIntervals.map { calendarSpec in
                var entry: [String: Int] = [
                    "Hour": calendarSpec.hour,
                    "Minute": calendarSpec.minute
                ]
                if let weekday = calendarSpec.weekday {
                    entry["Weekday"] = weekday
                }
                return entry
            }
            dictionary["StartCalendarInterval"] = mapped.count == 1 ? mapped[0] : mapped
        } else {
            dictionary.removeValue(forKey: "StartCalendarInterval")
        }

        if let workingDirectory {
            dictionary["WorkingDirectory"] = workingDirectory
        } else {
            dictionary.removeValue(forKey: "WorkingDirectory")
        }

        if let standardOutPath {
            dictionary["StandardOutPath"] = standardOutPath
        } else {
            dictionary.removeValue(forKey: "StandardOutPath")
        }

        if let standardErrorPath {
            dictionary["StandardErrorPath"] = standardErrorPath
        } else {
            dictionary.removeValue(forKey: "StandardErrorPath")
        }

        if !environmentVariables.isEmpty {
            dictionary["EnvironmentVariables"] = environmentVariables
        } else {
            dictionary.removeValue(forKey: "EnvironmentVariables")
        }

        return dictionary
    }
}

enum PlistValue: Hashable, Sendable {
    case string(String)
    case integer(Int)
    case double(Double)
    case bool(Bool)
    case data(Data)
    case date(Date)
    case array([PlistValue])
    case dictionary([String: PlistValue])

    var foundationValue: Any {
        switch self {
        case .string(let value):
            return value
        case .integer(let value):
            return value
        case .double(let value):
            return value
        case .bool(let value):
            return value
        case .data(let value):
            return value
        case .date(let value):
            return value
        case .array(let values):
            return values.map(\.foundationValue)
        case .dictionary(let values):
            return values.mapValues(\.foundationValue)
        }
    }

    static func fromFoundation(_ value: Any) throws -> PlistValue {
        switch value {
        case let value as String:
            return .string(value)
        case let value as Int:
            return .integer(value)
        case let value as Int64:
            return .integer(Int(value))
        case let value as NSNumber:
            if CFGetTypeID(value) == CFBooleanGetTypeID() {
                return .bool(value.boolValue)
            }
            if value.doubleValue.rounded() == value.doubleValue {
                return .integer(value.intValue)
            }
            return .double(value.doubleValue)
        case let value as Bool:
            return .bool(value)
        case let value as Data:
            return .data(value)
        case let value as Date:
            return .date(value)
        case let value as [Any]:
            return .array(try value.map { try PlistValue.fromFoundation($0) })
        case let value as [String: Any]:
            var mapped: [String: PlistValue] = [:]
            for (key, nested) in value {
                mapped[key] = try PlistValue.fromFoundation(nested)
            }
            return .dictionary(mapped)
        default:
            throw LaunchControlError.validation("Unsupported plist value type: \(type(of: value))")
        }
    }

    static func fromPlistData(_ data: Data) throws -> PlistValue {
        let propertyList: Any
        do {
            propertyList = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        } catch {
            throw LaunchControlError.io(error.localizedDescription)
        }
        return try fromFoundation(propertyList)
    }

    func propertyListData(format: PropertyListSerialization.PropertyListFormat = .xml) throws -> Data {
        do {
            return try PropertyListSerialization.data(fromPropertyList: foundationValue, format: format, options: 0)
        } catch {
            throw LaunchControlError.io(error.localizedDescription)
        }
    }

    func xmlString() throws -> String {
        let data = try propertyListData()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
