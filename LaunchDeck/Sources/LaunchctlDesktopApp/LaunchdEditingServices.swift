import Foundation

protocol CommandExecuting: Sendable {
    func run(
        _ launchPath: String,
        _ arguments: [String],
        timeout: TimeInterval
    ) async throws -> CommandResult
}

extension ShellExecutor: CommandExecuting {}

protocol FileAccessService: Sendable {
    func fileExists(at url: URL) -> Bool
    func directoryExists(at url: URL) -> Bool
    func isExecutableFile(at url: URL) -> Bool
    func readData(at url: URL) throws -> Data
    func writeData(_ data: Data, to url: URL) throws
    func copyItem(at sourceURL: URL, to destinationURL: URL) throws
    func removeItem(at url: URL) throws
    func createDirectory(at url: URL) throws
    func contentsOfDirectory(at url: URL) throws -> [URL]
    func modificationDate(at url: URL) -> Date?
    func fileSize(at url: URL) -> Int64?
    func isWritableDirectory(at url: URL) -> Bool
}

struct FoundationFileAccessService: FileAccessService, @unchecked Sendable {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func fileExists(at url: URL) -> Bool {
        fileManager.fileExists(atPath: url.path)
    }

    func directoryExists(at url: URL) -> Bool {
        var isDirectory = ObjCBool(false)
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return false }
        return isDirectory.boolValue
    }

    func isExecutableFile(at url: URL) -> Bool {
        fileManager.isExecutableFile(atPath: url.path)
    }

    func readData(at url: URL) throws -> Data {
        do {
            return try Data(contentsOf: url)
        } catch {
            throw LaunchControlError.io(error.localizedDescription)
        }
    }

    func writeData(_ data: Data, to url: URL) throws {
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw LaunchControlError.io(error.localizedDescription)
        }
    }

    func copyItem(at sourceURL: URL, to destinationURL: URL) throws {
        do {
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
        } catch {
            throw LaunchControlError.io(error.localizedDescription)
        }
    }

    func removeItem(at url: URL) throws {
        do {
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
        } catch {
            throw LaunchControlError.io(error.localizedDescription)
        }
    }

    func createDirectory(at url: URL) throws {
        do {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            throw LaunchControlError.io(error.localizedDescription)
        }
    }

    func contentsOfDirectory(at url: URL) throws -> [URL] {
        do {
            return try fileManager.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
        } catch {
            throw LaunchControlError.io(error.localizedDescription)
        }
    }

    func modificationDate(at url: URL) -> Date? {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        return values?.contentModificationDate
    }

    func fileSize(at url: URL) -> Int64? {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        guard let size = values?.fileSize else { return nil }
        return Int64(size)
    }

    func isWritableDirectory(at url: URL) -> Bool {
        fileManager.isWritableFile(atPath: url.path)
    }
}

protocol LaunchctlClient: Sendable {
    func list() async throws -> CommandResult
    func bootstrap(domainTarget: String, plistPath: String) async throws -> CommandResult
    func bootout(domainTarget: String, serviceTarget: String, plistPath: String?) async throws -> CommandResult
    func kickstart(serviceTarget: String, force: Bool) async throws -> CommandResult
    func preflightPlist(at plistURL: URL) async throws -> CommandResult
}

struct DefaultLaunchctlClient: LaunchctlClient, @unchecked Sendable {
    private let runner: any CommandExecuting

    init(runner: any CommandExecuting) {
        self.runner = runner
    }

    func list() async throws -> CommandResult {
        try await runner.run("/bin/launchctl", ["list"], timeout: 20)
    }

    func bootstrap(domainTarget: String, plistPath: String) async throws -> CommandResult {
        try await runner.run("/bin/launchctl", ["bootstrap", domainTarget, plistPath], timeout: 20)
    }

    func bootout(domainTarget: String, serviceTarget: String, plistPath: String?) async throws -> CommandResult {
        if let plistPath {
            let withPath = try await runner.run("/bin/launchctl", ["bootout", domainTarget, plistPath], timeout: 20)
            if withPath.status == 0 {
                return withPath
            }

            if withPath.stderr.localizedCaseInsensitiveContains("No such process") == false {
                return withPath
            }
        }

        return try await runner.run("/bin/launchctl", ["bootout", "\(domainTarget)/\(serviceTarget)"], timeout: 20)
    }

    func kickstart(serviceTarget: String, force: Bool) async throws -> CommandResult {
        var arguments = ["kickstart"]
        if force {
            arguments.append("-k")
        }
        arguments.append(serviceTarget)
        return try await runner.run("/bin/launchctl", arguments, timeout: 20)
    }

    func preflightPlist(at plistURL: URL) async throws -> CommandResult {
        try await runner.run("/usr/bin/plutil", ["-lint", plistURL.path], timeout: 20)
    }
}

protocol PlistEditingService: Sendable {
    func loadEditableLaunchJob(
        from fileURL: URL,
        domain: LaunchDomain,
        isLoaded: Bool,
        sourceJobID: String?
    ) throws -> EditableLaunchJob

    func editableLaunchJob(from rawText: String, sourceURL: URL, domain: LaunchDomain, isLoaded: Bool, sourceJobID: String?) throws -> EditableLaunchJob
    func plistData(for job: EditableLaunchJob) throws -> Data
    func plistText(for job: EditableLaunchJob) throws -> String
}

struct FoundationPlistEditingService: PlistEditingService, @unchecked Sendable {
    private let fileAccess: any FileAccessService

    init(fileAccess: any FileAccessService) {
        self.fileAccess = fileAccess
    }

    func loadEditableLaunchJob(
        from fileURL: URL,
        domain: LaunchDomain,
        isLoaded: Bool,
        sourceJobID: String?
    ) throws -> EditableLaunchJob {
        let data = try fileAccess.readData(at: fileURL)
        return try editableLaunchJob(
            from: String(decoding: data, as: UTF8.self),
            sourceURL: fileURL,
            domain: domain,
            isLoaded: isLoaded,
            sourceJobID: sourceJobID
        )
    }

    func editableLaunchJob(
        from rawText: String,
        sourceURL: URL,
        domain: LaunchDomain,
        isLoaded: Bool,
        sourceJobID: String?
    ) throws -> EditableLaunchJob {
        let data = Data(rawText.utf8)
        let propertyList: Any
        do {
            propertyList = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        } catch {
            throw LaunchControlError.io("Invalid plist: \(sourceURL.path)")
        }

        guard let dictionary = propertyList as? [String: Any] else {
            throw LaunchControlError.io("Unexpected plist format: \(sourceURL.path)")
        }

        return try editableLaunchJob(
            from: dictionary,
            sourceURL: sourceURL,
            domain: domain,
            isLoaded: isLoaded,
            sourceJobID: sourceJobID
        )
    }

    func plistData(for job: EditableLaunchJob) throws -> Data {
        do {
            return try PropertyListSerialization.data(fromPropertyList: job.plistDictionary(), format: .xml, options: 0)
        } catch {
            throw LaunchControlError.io(error.localizedDescription)
        }
    }

    func plistText(for job: EditableLaunchJob) throws -> String {
        let data = try plistData(for: job)
        return String(decoding: data, as: UTF8.self)
    }

    private func editableLaunchJob(
        from dictionary: [String: Any],
        sourceURL: URL,
        domain: LaunchDomain,
        isLoaded: Bool,
        sourceJobID: String?
    ) throws -> EditableLaunchJob {
        guard let label = dictionary["Label"] as? String, !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LaunchControlError.validation("Label is required")
        }

        let programArguments = (dictionary["ProgramArguments"] as? [String]) ?? []
        let program = (dictionary["Program"] as? String) ?? programArguments.first
        let runAtLoad = (dictionary["RunAtLoad"] as? Bool) ?? false
        let keepAlive = parseKeepAlive(dictionary["KeepAlive"])
        let startInterval = dictionary["StartInterval"] as? Int
        let startCalendarIntervals = parseCalendarIntervals(dictionary["StartCalendarInterval"])
        let workingDirectory = dictionary["WorkingDirectory"] as? String
        let standardOutPath = dictionary["StandardOutPath"] as? String
        let standardErrorPath = dictionary["StandardErrorPath"] as? String
        let environmentVariables = (dictionary["EnvironmentVariables"] as? [String: String]) ?? [:]

        var additionalFields: [String: PlistValue] = [:]
        let surfacedKeys: Set<String> = [
            "Label",
            "Program",
            "ProgramArguments",
            "RunAtLoad",
            "KeepAlive",
            "StartInterval",
            "StartCalendarInterval",
            "WorkingDirectory",
            "StandardOutPath",
            "StandardErrorPath",
            "EnvironmentVariables"
        ]

        for (key, value) in dictionary where surfacedKeys.contains(key) == false {
            additionalFields[key] = try PlistValue.fromFoundation(value)
        }

        let modificationDate = fileAccess.modificationDate(at: sourceURL)

        return EditableLaunchJob(
            sourceJobID: sourceJobID,
            fileURL: sourceURL,
            domain: domain,
            lastModified: modificationDate,
            isLoaded: isLoaded,
            label: label,
            program: program,
            programArguments: programArguments.isEmpty ? (program.map { [$0] } ?? []) : programArguments,
            runAtLoad: runAtLoad,
            keepAlive: keepAlive,
            startInterval: startInterval,
            startCalendarIntervals: startCalendarIntervals,
            workingDirectory: workingDirectory,
            standardOutPath: standardOutPath,
            standardErrorPath: standardErrorPath,
            environmentVariables: environmentVariables,
            additionalFields: additionalFields
        )
    }

    private func parseKeepAlive(_ raw: Any?) -> LaunchdKeepAliveSetting {
        guard let raw else { return .disabled }

        if let bool = raw as? Bool {
            return bool ? .enabled : .disabled
        }

        if let dict = raw as? [String: Any] {
            var conditions: [String: Bool] = [:]
            for (key, value) in dict {
                if let bool = value as? Bool {
                    conditions[key] = bool
                }
            }
            return conditions.isEmpty ? .disabled : .conditions(conditions)
        }

        return .disabled
    }

    private func parseCalendarIntervals(_ raw: Any?) -> [CalendarSpec] {
        if let entry = raw as? [String: Any] {
            return [calendarSpec(from: entry)]
        }

        if let entries = raw as? [[String: Any]] {
            return entries.map(calendarSpec(from:))
        }

        return []
    }

    private func calendarSpec(from raw: [String: Any]) -> CalendarSpec {
        CalendarSpec(
            weekday: raw["Weekday"] as? Int,
            hour: raw["Hour"] as? Int ?? 0,
            minute: raw["Minute"] as? Int ?? 0
        )
    }
}

protocol LaunchdValidationService: Sendable {
    func validate(job: EditableLaunchJob) async throws -> LaunchdValidationReport
}

struct DefaultLaunchdValidationService: LaunchdValidationService, @unchecked Sendable {
    private let fileAccess: any FileAccessService
    private let launchctlClient: any LaunchctlClient
    private let plistEditingService: any PlistEditingService

    init(
        fileAccess: any FileAccessService,
        launchctlClient: any LaunchctlClient,
        plistEditingService: any PlistEditingService
    ) {
        self.fileAccess = fileAccess
        self.launchctlClient = launchctlClient
        self.plistEditingService = plistEditingService
    }

    func validate(job: EditableLaunchJob) async throws -> LaunchdValidationReport {
        var issues: [ValidationIssue] = []

        let trimmedLabel = job.label.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedLabel.isEmpty {
            issues.append(.init(severity: .error, title: "Label required", message: "The launchd Label cannot be empty.", path: "Label"))
        } else if trimmedLabel.contains(" ") {
            issues.append(.init(severity: .warning, title: "Label contains spaces", message: "Launchd labels are typically reverse-DNS identifiers without spaces.", path: "Label"))
        } else if !trimmedLabel.contains(".") {
            issues.append(.init(severity: .notice, title: "Label looks unusual", message: "Most launchd labels use reverse-DNS naming, such as com.example.tool.", path: "Label"))
        }

        let resolvedProgram = (job.program ?? job.programArguments.first)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let resolvedProgram, resolvedProgram.isEmpty == false {
            if resolvedProgram.hasPrefix("/") == false {
                issues.append(.init(severity: .warning, title: "Program path is relative", message: "Use an absolute executable path so launchd can resolve it reliably.", path: "Program"))
            } else if resolvedProgram.contains("..") {
                issues.append(.init(severity: .warning, title: "Program path is suspicious", message: "Paths containing `..` can be fragile and harder to reason about.", path: "Program"))
            } else if fileAccess.fileExists(at: URL(fileURLWithPath: resolvedProgram)) == false {
                issues.append(.init(severity: .error, title: "Executable missing", message: "The executable does not exist at \(resolvedProgram).", path: "Program"))
            } else if fileAccess.isExecutableFile(at: URL(fileURLWithPath: resolvedProgram)) == false {
                issues.append(.init(severity: .error, title: "Executable is not executable", message: "The file exists, but macOS does not consider it executable.", path: "Program"))
            }
        } else {
            issues.append(.init(severity: .error, title: "Program required", message: "A launchd job needs either Program or ProgramArguments with an executable first item.", path: "Program"))
        }

        if job.programArguments.isEmpty {
            issues.append(.init(severity: .warning, title: "ProgramArguments missing", message: "ProgramArguments should usually include the executable followed by its arguments.", path: "ProgramArguments"))
        } else if let resolvedProgram, job.programArguments.first != resolvedProgram {
            issues.append(.init(severity: .warning, title: "Program mismatch", message: "The first ProgramArguments entry should match the Program path.", path: "ProgramArguments"))
        }

        if let startInterval = job.startInterval {
            if startInterval <= 0 {
                issues.append(.init(severity: .error, title: "Invalid interval", message: "StartInterval must be greater than zero.", path: "StartInterval"))
            }
        }

        if !job.startCalendarIntervals.isEmpty {
            for calendarSpec in job.startCalendarIntervals {
                if calendarSpec.hour < 0 || calendarSpec.hour > 23 {
                    issues.append(.init(severity: .error, title: "Invalid schedule hour", message: "Calendar hour must be in the range 0...23.", path: "StartCalendarInterval"))
                }
                if calendarSpec.minute < 0 || calendarSpec.minute > 59 {
                    issues.append(.init(severity: .error, title: "Invalid schedule minute", message: "Calendar minute must be in the range 0...59.", path: "StartCalendarInterval"))
                }
                if let weekday = calendarSpec.weekday, (1...7).contains(weekday) == false {
                    issues.append(.init(severity: .error, title: "Invalid schedule weekday", message: "Weekday must be between 1 and 7 when specified.", path: "StartCalendarInterval"))
                }
            }
        }

        if job.startInterval != nil && !job.startCalendarIntervals.isEmpty {
            issues.append(.init(severity: .error, title: "Conflicting schedule settings", message: "Choose either StartInterval or StartCalendarInterval, not both.", path: "StartInterval"))
        }

        if let workingDirectory = job.workingDirectory {
            let url = URL(fileURLWithPath: workingDirectory)
            if fileAccess.directoryExists(at: url) == false {
                issues.append(.init(severity: .warning, title: "Working directory missing", message: "The configured WorkingDirectory does not exist.", path: "WorkingDirectory"))
            }
        }

        if let standardOutPath = job.standardOutPath {
            issues.append(contentsOf: validateLogPath(standardOutPath, field: "StandardOutPath"))
        }

        if let standardErrorPath = job.standardErrorPath {
            issues.append(contentsOf: validateLogPath(standardErrorPath, field: "StandardErrorPath"))
        }

        let inferredDomain = inferredDomain(for: job.fileURL)
        if inferredDomain != .unknown && inferredDomain != job.domain {
            issues.append(.init(
                severity: .notice,
                title: "Domain mismatch",
                message: "The plist path suggests \(inferredDomain.title), but the job metadata says \(job.domain.title).",
                path: job.fileURL.path
            ))
        }

        if let resolvedProgram, resolvedProgram.hasPrefix("/") {
            let programName = URL(fileURLWithPath: resolvedProgram).lastPathComponent.lowercased()
            let labelToken = trimmedLabel.split(separator: ".").last.map(String.init)?.lowercased() ?? trimmedLabel.lowercased()
            if labelToken.isEmpty == false, programName.isEmpty == false, programName.contains(labelToken) == false && labelToken.contains(programName) == false {
                issues.append(.init(
                    severity: .notice,
                    title: "Label/program mismatch",
                    message: "The label and executable name do not appear to describe the same service. Double-check that this plist belongs to the expected job.",
                    path: "Label"
                ))
            }
        }

        if job.keepAlive != .disabled && job.runAtLoad == false {
            issues.append(.init(severity: .notice, title: "KeepAlive without RunAtLoad", message: "The job may still launch on demand, but it will not start immediately on load.", path: "KeepAlive"))
        }

        let normalizedText = try plistEditingService.plistText(for: job)
        let temporaryURL = try temporaryValidationURL(for: job)
        defer { try? fileAccess.removeItem(at: temporaryURL) }

        try fileAccess.writeData(try plistEditingService.plistData(for: job), to: temporaryURL)
        let lint = try await launchctlClient.preflightPlist(at: temporaryURL)
        if lint.status != 0 {
            issues.append(.init(
                severity: .error,
                title: "Plist lint failed",
                message: lint.stderr.isEmpty ? lint.stdout.ifEmpty("plutil -lint failed") : lint.stderr,
                path: job.fileURL.path
            ))
        } else if lint.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            issues.append(.init(
                severity: .notice,
                title: "Plist lint completed",
                message: lint.stdout.trimmingCharacters(in: .whitespacesAndNewlines),
                path: job.fileURL.path
            ))
        }

        return LaunchdValidationReport(issues: issues.sorted(by: sortIssues), normalizedPlistText: normalizedText)
    }

    private func validateLogPath(_ path: String, field: String) -> [ValidationIssue] {
        let url = URL(fileURLWithPath: path)
        var issues: [ValidationIssue] = []

        if url.pathComponents.contains("..") {
            issues.append(.init(severity: .warning, title: "Suspicious log path", message: "The log path contains `..`, which is often a sign of a fragile configuration.", path: field))
        }

        let parentDirectory = url.deletingLastPathComponent()
        if fileAccess.directoryExists(at: parentDirectory) == false {
            issues.append(.init(severity: .warning, title: "Log directory missing", message: "The directory for \(field) does not exist.", path: field))
        } else if fileAccess.isWritableDirectory(at: parentDirectory) == false {
            issues.append(.init(severity: .warning, title: "Log directory not writable", message: "The current user may not be able to write \(field).", path: field))
        }

        return issues
    }

    private func inferredDomain(for url: URL) -> LaunchDomain {
        let path = url.path
        if path.contains("/Library/LaunchDaemons/") || path.contains("/System/Library/LaunchDaemons/") {
            return .systemDaemon
        }
        if path.contains("/Library/LaunchAgents/") || path.contains("/System/Library/LaunchAgents/") {
            return .systemAgent
        }
        if path.contains("/Users/") && path.contains("/Library/LaunchAgents/") {
            return .userAgent
        }
        return .unknown
    }

    private func temporaryValidationURL(for job: EditableLaunchJob) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("LaunchDeckValidation", isDirectory: true)
        if fileAccess.directoryExists(at: root) == false {
            try fileAccess.createDirectory(at: root)
        }

        let fileName = "\(job.label)-\(UUID().uuidString).plist"
        return root.appendingPathComponent(fileName)
    }

    private func sortIssues(_ lhs: ValidationIssue, _ rhs: ValidationIssue) -> Bool {
        if lhs.severity == rhs.severity {
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
        return severityRank(lhs.severity) < severityRank(rhs.severity)
    }

    private func severityRank(_ severity: ValidationSeverity) -> Int {
        switch severity {
        case .error:
            return 0
        case .warning:
            return 1
        case .notice:
            return 2
        }
    }
}

protocol LaunchdBackupService: Sendable {
    func createBackup(of sourceURL: URL, label: String) throws -> BackupSnapshot
    func listBackups(for sourceURL: URL) throws -> [BackupSnapshot]
    func restore(_ snapshot: BackupSnapshot, to destinationURL: URL) throws
}

struct FoundationLaunchdBackupService: LaunchdBackupService, @unchecked Sendable {
    private let fileAccess: any FileAccessService
    private let fileManager: FileManager
    private let rootDirectory: URL

    init(fileAccess: any FileAccessService, fileManager: FileManager = .default) {
        self.fileAccess = fileAccess
        self.fileManager = fileManager
        self.rootDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("LaunchDeck")
            .appendingPathComponent("Backups", isDirectory: true)
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("LaunchDeckBackups", isDirectory: true)
    }

    func createBackup(of sourceURL: URL, label: String) throws -> BackupSnapshot {
        guard fileAccess.fileExists(at: sourceURL) else {
            throw LaunchControlError.validation("Cannot create a backup because the source plist does not exist.")
        }

        let snapshotDirectory = rootDirectory
            .appendingPathComponent(sanitized(label), isDirectory: true)
        if fileAccess.directoryExists(at: snapshotDirectory) == false {
            try fileAccess.createDirectory(at: snapshotDirectory)
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let timestamp = formatter.string(from: Date())
        let snapshotURL = snapshotDirectory.appendingPathComponent("\(timestamp).plist")
        try fileAccess.copyItem(at: sourceURL, to: snapshotURL)

        let size = fileAccess.fileSize(at: snapshotURL) ?? 0
        let modified = fileAccess.modificationDate(at: snapshotURL)
        return BackupSnapshot(
            id: snapshotURL.path,
            label: label,
            sourceURL: sourceURL,
            backupURL: snapshotURL,
            createdAt: modified ?? Date(),
            fileSizeBytes: size,
            originalModificationDate: fileAccess.modificationDate(at: sourceURL)
        )
    }

    func listBackups(for sourceURL: URL) throws -> [BackupSnapshot] {
        let directory = rootDirectory.appendingPathComponent(sanitized(sourceURL.lastPathComponent.replacingOccurrences(of: ".plist", with: "")), isDirectory: true)
        guard fileAccess.directoryExists(at: directory) else { return [] }

        let urls = try fileAccess.contentsOfDirectory(at: directory).filter { $0.pathExtension == "plist" }
        return urls.compactMap { url in
            let size = fileAccess.fileSize(at: url) ?? 0
            let modified = fileAccess.modificationDate(at: url) ?? Date.distantPast
            return BackupSnapshot(
                id: url.path,
                label: sourceURL.deletingPathExtension().lastPathComponent,
                sourceURL: sourceURL,
                backupURL: url,
                createdAt: modified,
                fileSizeBytes: size,
                originalModificationDate: nil
            )
        }
        .sorted { $0.createdAt > $1.createdAt }
    }

    func restore(_ snapshot: BackupSnapshot, to destinationURL: URL) throws {
        try fileAccess.copyItem(at: snapshot.backupURL, to: destinationURL)
    }

    private func sanitized(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(.init(charactersIn: "-_."))
        return value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }.map(String.init).joined()
    }
}

protocol LaunchdApplyService: Sendable {
    func makePlan(
        for job: EditableLaunchJob,
        reloadOption: LaunchdApplyReloadOption
    ) async throws -> ApplyPlan

    func apply(_ plan: ApplyPlan) async throws -> ApplyResult

    func restore(snapshot: BackupSnapshot, to destinationURL: URL) throws
}

struct DefaultLaunchdApplyService: LaunchdApplyService, @unchecked Sendable {
    private let validationService: any LaunchdValidationService
    private let backupService: any LaunchdBackupService
    private let plistEditingService: any PlistEditingService
    private let launchctlClient: any LaunchctlClient
    private let fileAccess: any FileAccessService

    init(
        validationService: any LaunchdValidationService,
        backupService: any LaunchdBackupService,
        plistEditingService: any PlistEditingService,
        launchctlClient: any LaunchctlClient,
        fileAccess: any FileAccessService
    ) {
        self.validationService = validationService
        self.backupService = backupService
        self.plistEditingService = plistEditingService
        self.launchctlClient = launchctlClient
        self.fileAccess = fileAccess
    }

    func makePlan(
        for job: EditableLaunchJob,
        reloadOption: LaunchdApplyReloadOption
    ) async throws -> ApplyPlan {
        let report = try await validationService.validate(job: job)
        let data = try plistEditingService.plistData(for: job)
        let text = String(decoding: data, as: UTF8.self)
        return ApplyPlan(
            sourceURL: job.fileURL,
            job: job,
            validationReport: report,
            normalizedPlistData: data,
            normalizedPlistText: text,
            reloadOption: reloadOption,
            snapshotLabel: job.label
        )
    }

    func apply(_ plan: ApplyPlan) async throws -> ApplyResult {
        guard plan.validationReport.canApply else {
            throw LaunchControlError.validation("Resolve validation errors before applying the plist.")
        }

        let backup = try backupService.createBackup(of: plan.sourceURL, label: plan.snapshotLabel)

        if fileAccess.fileExists(at: plan.sourceURL) && plan.job.isLoaded {
            let unload = try await launchctlClient.bootout(
                domainTarget: plan.job.domain.bootstrapTarget,
                serviceTarget: plan.job.label,
                plistPath: plan.sourceURL.path
            )
            let unloadOutput = "\(unload.stdout)\n\(unload.stderr)".lowercased()
            if unload.status != 0,
               unloadOutput.contains("no such process") == false,
               unloadOutput.contains("could not find service") == false {
                try ensureSucceeded(unload, action: "bootout \(plan.job.label)", hint: "LaunchDeck is trying to replace the live plist safely. If the job was already gone, the backup is still available.")
            }
        }

        try fileAccess.writeData(plan.normalizedPlistData, to: plan.sourceURL)

        var didBootstrap = false
        var didKickstart = false
        var outputs: [String] = []

        switch plan.reloadOption {
        case .none:
            break
        case .bootstrap:
            didBootstrap = true
            let bootstrap = try await launchctlClient.bootstrap(
                domainTarget: plan.job.domain.bootstrapTarget,
                plistPath: plan.sourceURL.path
            )
            try ensureSucceeded(bootstrap, action: "bootstrap \(plan.job.label)", hint: "The plist was written, but launchctl refused to load it.")
            if bootstrap.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                outputs.append(bootstrap.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            if bootstrap.stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                outputs.append(bootstrap.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        case .bootstrapAndKickstart:
            didBootstrap = true
            let bootstrap = try await launchctlClient.bootstrap(
                domainTarget: plan.job.domain.bootstrapTarget,
                plistPath: plan.sourceURL.path
            )
            try ensureSucceeded(bootstrap, action: "bootstrap \(plan.job.label)", hint: "The plist was written, but launchctl refused to load it.")
            if bootstrap.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                outputs.append(bootstrap.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            if bootstrap.stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                outputs.append(bootstrap.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
            }

            didKickstart = true
            let kickstart = try await launchctlClient.kickstart(
                serviceTarget: "\(plan.job.domain.bootstrapTarget)/\(plan.job.label)",
                force: true
            )
            try ensureSucceeded(kickstart, action: "kickstart \(plan.job.label)", hint: "The job was loaded, but launchctl refused to restart it immediately.")
            if kickstart.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                outputs.append(kickstart.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            if kickstart.stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                outputs.append(kickstart.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }

        let summary = buildSummary(
            backup: backup,
            job: plan.job,
            reloadOption: plan.reloadOption,
            didBootstrap: didBootstrap,
            didKickstart: didKickstart
        )

        return ApplyResult(
            plan: plan,
            backupSnapshot: backup,
            appliedURL: plan.sourceURL,
            didBootstrap: didBootstrap,
            didKickstart: didKickstart,
            launchctlOutput: outputs.isEmpty ? nil : outputs.joined(separator: "\n"),
            summary: summary,
            issues: plan.validationReport.issues
        )
    }

    func restore(snapshot: BackupSnapshot, to destinationURL: URL) throws {
        try backupService.restore(snapshot, to: destinationURL)
    }

    private func buildSummary(
        backup: BackupSnapshot,
        job: EditableLaunchJob,
        reloadOption: LaunchdApplyReloadOption,
        didBootstrap: Bool,
        didKickstart: Bool
    ) -> String {
        var parts: [String] = []
        parts.append("Applied \(job.label)")
        parts.append("Backup saved at \(backup.backupURL.lastPathComponent)")

        switch reloadOption {
        case .none:
            parts.append("No launchctl reload was requested")
        case .bootstrap:
            parts.append(didBootstrap ? "Job bootstrapped" : "Bootstrap skipped")
        case .bootstrapAndKickstart:
            parts.append(didBootstrap ? "Job bootstrapped" : "Bootstrap skipped")
            parts.append(didKickstart ? "Job kickstarted" : "Kickstart skipped")
        }

        return parts.joined(separator: ". ") + "."
    }

    private func ensureSucceeded(_ result: CommandResult, action: String, hint: String) throws {
        guard result.status == 0 else {
            throw LaunchControlError.commandFailed(
                launchctlFriendlyCommandFailure(
                    action: action,
                    stderr: result.stderr.ifEmpty(result.stdout),
                    hint: hint
                )
            )
        }
    }
}

extension String {
    func ifEmpty(_ fallback: String) -> String {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallback : self
    }
}
