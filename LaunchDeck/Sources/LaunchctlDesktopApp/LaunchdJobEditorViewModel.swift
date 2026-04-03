import Foundation
import SwiftUI

enum LaunchdEditorMode: String, CaseIterable, Identifiable, Sendable {
    case structured
    case raw

    var id: String { rawValue }

    var title: String {
        switch self {
        case .structured:
            return "Structured"
        case .raw:
            return "Raw"
        }
    }
}

enum LaunchdKeepAliveEditorMode: String, CaseIterable, Identifiable, Sendable {
    case disabled
    case enabled
    case flags

    var id: String { rawValue }

    var title: String {
        switch self {
        case .disabled:
            return "Off"
        case .enabled:
            return "On"
        case .flags:
            return "Flags"
        }
    }
}

struct LaunchdCalendarRow: Identifiable, Hashable, Sendable {
    let id: String
    var weekday: Int
    var hour: Int
    var minute: Int

    init(id: String = UUID().uuidString, weekday: Int = 1, hour: Int = 0, minute: Int = 0) {
        self.id = id
        self.weekday = weekday
        self.hour = hour
        self.minute = minute
    }
}

struct LaunchdEnvironmentRow: Identifiable, Hashable, Sendable {
    let id: String
    var key: String
    var value: String

    init(id: String = UUID().uuidString, key: String = "", value: String = "") {
        self.id = id
        self.key = key
        self.value = value
    }
}

@MainActor
final class LaunchdJobEditorViewModel: ObservableObject, Identifiable {
    let id: String
    let sourceJob: LaunchServiceJob

    @Published var editorMode: LaunchdEditorMode = .structured
    @Published var label: String = ""
    @Published var program: String = ""
    @Published var programArgumentsText: String = ""
    @Published var runAtLoad: Bool = false
    @Published var keepAliveMode: LaunchdKeepAliveEditorMode = .disabled
    @Published var keepAliveFlagsText: String = ""
    @Published var startIntervalText: String = ""
    @Published var calendarRows: [LaunchdCalendarRow] = []
    @Published var workingDirectory: String = ""
    @Published var standardOutPath: String = ""
    @Published var standardErrorPath: String = ""
    @Published var environmentRows: [LaunchdEnvironmentRow] = []
    @Published var rawText: String = ""
    @Published var validationReport: LaunchdValidationReport?
    @Published var normalizedPreview: String = ""
    @Published var latestBackups: [BackupSnapshot] = []
    @Published var applySummary: String = ""
    @Published var errorMessage: String = ""
    @Published var isLoading = false
    @Published var isValidating = false
    @Published var isApplying = false
    @Published var shouldReloadAfterApply = true
    @Published var shouldKickstartAfterApply = false
    @Published var selectedBackupID: BackupSnapshot.ID?

    private let plistEditingService: any PlistEditingService
    private let validationService: any LaunchdValidationService
    private let applyService: any LaunchdApplyService
    private let backupService: any LaunchdBackupService
    private var originalAdditionalFields: [String: PlistValue] = [:]

    init(
        sourceJob: LaunchServiceJob,
        plistEditingService: any PlistEditingService,
        validationService: any LaunchdValidationService,
        applyService: any LaunchdApplyService,
        backupService: any LaunchdBackupService
    ) {
        self.sourceJob = sourceJob
        self.plistEditingService = plistEditingService
        self.validationService = validationService
        self.applyService = applyService
        self.backupService = backupService
        self.id = sourceJob.plistPath ?? sourceJob.label

        label = sourceJob.label
        program = sourceJob.program ?? ""
        programArgumentsText = sourceJob.arguments.joined(separator: "\n")
        runAtLoad = sourceJob.runAtLoad ?? false
        startIntervalText = ""
        workingDirectory = ""
        standardOutPath = ""
        standardErrorPath = ""
        shouldReloadAfterApply = sourceJob.isLoaded
    }

    var title: String {
        sourceJob.label
    }

    var fileURL: URL? {
        guard let path = sourceJob.plistPath else { return nil }
        return URL(fileURLWithPath: path)
    }

    var latestBackup: BackupSnapshot? {
        latestBackups.first
    }

    var issueCountsText: String {
        guard let report = validationReport else { return "Not validated yet" }
        return report.summaryText
    }

    var hasErrors: Bool {
        validationReport?.canApply == false
    }

    func load() async {
        guard let fileURL else {
            errorMessage = "No plist file path is available for this job."
            return
        }

        isLoading = true
        errorMessage = ""

        do {
            let loaded = try plistEditingService.loadEditableLaunchJob(
                from: fileURL,
                domain: sourceJob.domain,
                isLoaded: sourceJob.isLoaded,
                sourceJobID: sourceJob.id
            )
            applyEditableJob(loaded)
            originalAdditionalFields = loaded.additionalFields
            latestBackups = try backupService.listBackups(for: fileURL)
            selectedBackupID = latestBackups.first?.id
            await dryRun()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func switchMode(to mode: LaunchdEditorMode) {
        guard mode != editorMode else { return }

        switch mode {
        case .structured:
            if let parsed = try? parseRawDraft() {
                applyEditableJob(parsed)
            }
        case .raw:
            if let current = try? buildEditableJob(fromStructuredFields: true) {
                rawText = (try? plistEditingService.plistText(for: current)) ?? rawText
            }
        }

        editorMode = mode
    }

    func addCalendarRow() {
        calendarRows.append(.init())
    }

    func removeCalendarRow(at offsets: IndexSet) {
        calendarRows.remove(atOffsets: offsets)
    }

    func addEnvironmentRow() {
        environmentRows.append(.init())
    }

    func removeEnvironmentRow(at offsets: IndexSet) {
        environmentRows.remove(atOffsets: offsets)
    }

    func dryRun() async {
        isValidating = true
        errorMessage = ""

        do {
            let job = try currentEditableJob()
            let report = try await validationService.validate(job: job)
            validationReport = report
            normalizedPreview = report.normalizedPlistText
        } catch {
            validationReport = nil
            errorMessage = error.localizedDescription
        }

        isValidating = false
    }

    func makeApplyPlan() async throws -> ApplyPlan {
        let job = try currentEditableJob()
        let reloadOption: LaunchdApplyReloadOption
        if shouldReloadAfterApply {
            reloadOption = shouldKickstartAfterApply ? .bootstrapAndKickstart : .bootstrap
        } else {
            reloadOption = .none
        }
        return try await applyService.makePlan(for: job, reloadOption: reloadOption)
    }

    func applyChanges() async {
        isApplying = true
        errorMessage = ""

        do {
            let plan = try await makeApplyPlan()
            let result = try await applyService.apply(plan)
            applySummary = result.summary
            validationReport = plan.validationReport
            normalizedPreview = plan.normalizedPlistText
            latestBackups = try backupService.listBackups(for: plan.sourceURL)
            selectedBackupID = latestBackups.first?.id
            if let fileURL {
                let refreshed = try plistEditingService.loadEditableLaunchJob(
                    from: fileURL,
                    domain: sourceJob.domain,
                    isLoaded: sourceJob.isLoaded,
                    sourceJobID: sourceJob.id
                )
                applyEditableJob(refreshed)
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isApplying = false
    }

    func restoreSelectedBackup() async {
        guard let fileURL else {
            errorMessage = "No plist file path is available for rollback."
            return
        }
        guard let backup = selectedBackup else {
            errorMessage = "Select a backup to restore."
            return
        }

        isApplying = true
        errorMessage = ""

        do {
            try applyService.restore(snapshot: backup, to: fileURL)
            latestBackups = try backupService.listBackups(for: fileURL)
            let refreshed = try plistEditingService.loadEditableLaunchJob(
                from: fileURL,
                domain: sourceJob.domain,
                isLoaded: sourceJob.isLoaded,
                sourceJobID: sourceJob.id
            )
            applyEditableJob(refreshed)
            await dryRun()
            applySummary = "Restored \(backup.backupURL.lastPathComponent) to \(sourceJob.label)."
        } catch {
            errorMessage = error.localizedDescription
        }

        isApplying = false
    }

    func applyEditableJob(_ job: EditableLaunchJob) {
        label = job.label
        program = job.program ?? ""
        programArgumentsText = job.programArguments.dropFirst().joined(separator: "\n")
        runAtLoad = job.runAtLoad
        switch job.keepAlive {
        case .disabled:
            keepAliveMode = .disabled
            keepAliveFlagsText = ""
        case .enabled:
            keepAliveMode = .enabled
            keepAliveFlagsText = ""
        case .conditions(let conditions):
            keepAliveMode = .flags
            keepAliveFlagsText = conditions
                .sorted(by: { $0.key < $1.key })
                .map { "\($0.key)=\($0.value ? "true" : "false")" }
                .joined(separator: ", ")
        }
        if let startInterval = job.startInterval {
            startIntervalText = String(startInterval)
        } else {
            startIntervalText = ""
        }
        calendarRows = job.startCalendarIntervals.map { LaunchdCalendarRow(weekday: $0.weekday ?? 1, hour: $0.hour, minute: $0.minute) }
        workingDirectory = job.workingDirectory ?? ""
        standardOutPath = job.standardOutPath ?? ""
        standardErrorPath = job.standardErrorPath ?? ""
        environmentRows = job.environmentVariables.sorted(by: { $0.key < $1.key }).map { LaunchdEnvironmentRow(key: $0.key, value: $0.value) }
        rawText = (try? plistEditingService.plistText(for: job)) ?? rawText
        normalizedPreview = rawText
        validationReport = nil
        originalAdditionalFields = job.additionalFields
    }

    private var selectedBackup: BackupSnapshot? {
        latestBackups.first { $0.id == selectedBackupID } ?? latestBackup
    }

    private func currentEditableJob() throws -> EditableLaunchJob {
        switch editorMode {
        case .structured:
            return try buildEditableJob(fromStructuredFields: true)
        case .raw:
            return try parseRawDraft()
        }
    }

    private func parseRawDraft() throws -> EditableLaunchJob {
        guard let fileURL else {
            throw LaunchControlError.validation("No plist file path is available.")
        }
        return try plistEditingService.editableLaunchJob(
            from: rawText,
            sourceURL: fileURL,
            domain: sourceJob.domain,
            isLoaded: sourceJob.isLoaded,
            sourceJobID: sourceJob.id
        )
    }

    private func buildEditableJob(fromStructuredFields: Bool) throws -> EditableLaunchJob {
        guard let fileURL else {
            throw LaunchControlError.validation("No plist file path is available.")
        }

        let programText = program.trimmingCharacters(in: .whitespacesAndNewlines)
        let args = programArgumentsText
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }

        let keepAlive: LaunchdKeepAliveSetting
        switch keepAliveMode {
        case .disabled:
            keepAlive = .disabled
        case .enabled:
            keepAlive = .enabled
        case .flags:
            var flags: [String: Bool] = [:]
            for rawPair in keepAliveFlagsText.split(separator: ",") {
                let pieces = rawPair.split(separator: "=", maxSplits: 1).map(String.init)
                guard pieces.count == 2 else { continue }
                let key = pieces[0].trimmingCharacters(in: .whitespacesAndNewlines)
                let value = pieces[1].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if key.isEmpty == false {
                    flags[key] = (value == "true" || value == "yes" || value == "1")
                }
            }
            keepAlive = flags.isEmpty ? .disabled : .conditions(flags)
        }

        let trimmedIntervalText = startIntervalText.trimmingCharacters(in: .whitespacesAndNewlines)
        let startInterval: Int?
        if trimmedIntervalText.isEmpty {
            startInterval = nil
        } else if let value = Int(trimmedIntervalText) {
            startInterval = value
        } else {
            throw LaunchControlError.validation("Start Interval must be a whole number.")
        }
        let calendarSpecs = calendarRows.compactMap { row -> CalendarSpec? in
            let isBlank = row.weekday == 1 && row.hour == 0 && row.minute == 0
            if isBlank, calendarRows.count == 0 {
                return nil
            }
            guard row.hour >= 0, row.hour <= 23, row.minute >= 0, row.minute <= 59 else { return nil }
            return CalendarSpec(weekday: row.weekday == 0 ? nil : row.weekday, hour: row.hour, minute: row.minute)
        }

        let environmentVariables = environmentRows.reduce(into: [String: String]()) { result, row in
            let key = row.key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard key.isEmpty == false else { return }
            result[key] = row.value
        }

        let additionalFields = originalAdditionalFields

        return EditableLaunchJob(
            sourceJobID: sourceJob.id,
            fileURL: fileURL,
            domain: sourceJob.domain,
            lastModified: nil,
            isLoaded: sourceJob.isLoaded,
            label: label.trimmingCharacters(in: .whitespacesAndNewlines),
            program: programText.isEmpty ? nil : programText,
            programArguments: programText.isEmpty ? args : ([programText] + args),
            runAtLoad: runAtLoad,
            keepAlive: keepAlive,
            startInterval: startInterval,
            startCalendarIntervals: calendarSpecs,
            workingDirectory: workingDirectory.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            standardOutPath: standardOutPath.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            standardErrorPath: standardErrorPath.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            environmentVariables: environmentVariables,
            additionalFields: additionalFields
        )
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
