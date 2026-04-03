import Foundation

enum LaunchJobHealthStatus: String, CaseIterable, Codable, Hashable, Sendable {
    case healthy
    case warning
    case broken
    case suspicious
    case orphaned

    var title: String {
        switch self {
        case .healthy:
            return "Healthy"
        case .warning:
            return "Warning"
        case .broken:
            return "Broken"
        case .suspicious:
            return "Suspicious"
        case .orphaned:
            return "Orphaned"
        }
    }

    var symbol: String {
        switch self {
        case .healthy:
            return "checkmark.seal.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .broken:
            return "xmark.octagon.fill"
        case .suspicious:
            return "exclamationmark.shield.fill"
        case .orphaned:
            return "questionmark.folder.fill"
        }
    }
}

enum LaunchJobRiskSeverity: String, CaseIterable, Codable, Hashable, Sendable {
    case info
    case low
    case medium
    case high
    case critical

    var title: String {
        switch self {
        case .info:
            return "Info"
        case .low:
            return "Low"
        case .medium:
            return "Medium"
        case .high:
            return "High"
        case .critical:
            return "Critical"
        }
    }

    var scorePenalty: Int {
        switch self {
        case .info:
            return 0
        case .low:
            return 5
        case .medium:
            return 12
        case .high:
            return 22
        case .critical:
            return 35
        }
    }

    var rank: Int {
        switch self {
        case .info:
            return 0
        case .low:
            return 1
        case .medium:
            return 2
        case .high:
            return 3
        case .critical:
            return 4
        }
    }
}

enum LaunchJobRiskFactorKind: String, CaseIterable, Codable, Hashable, Sendable {
    case missingExecutable
    case nonExecutableBinary
    case invalidPlistPath
    case inaccessiblePlist
    case loadedStateMismatch
    case nonZeroExitCode
    case repeatedRestarts
    case suspiciousLogPath
    case suspiciousBinaryLocation
    case systemLikeLabelBackedByNonSystemBinary
    case aggressiveInterval
    case malformedConfiguration
    case missingRuntimeInfo
    case orphanedTarget
}

struct LaunchJobRiskFactor: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let kind: LaunchJobRiskFactorKind
    let severity: LaunchJobRiskSeverity
    let title: String
    let explanation: String
    let evidence: String?
    let remediationHint: String?

    init(
        kind: LaunchJobRiskFactorKind,
        severity: LaunchJobRiskSeverity,
        title: String,
        explanation: String,
        evidence: String? = nil,
        remediationHint: String? = nil
    ) {
        self.id = Self.makeID(kind: kind, evidence: evidence)
        self.kind = kind
        self.severity = severity
        self.title = title
        self.explanation = explanation
        self.evidence = evidence
        self.remediationHint = remediationHint
    }

    var scoreImpact: Int { severity.scorePenalty }

    var severityLabel: String { severity.title }

    private static func makeID(kind: LaunchJobRiskFactorKind, evidence: String?) -> String {
        let fingerprint = Self.nonEmptyTrimmedString(from: evidence) ?? "-"
        return "\(kind.rawValue)|\(fingerprint)"
    }

    private static func nonEmptyTrimmedString(from value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, trimmed.isEmpty == false else { return nil }
        return trimmed
    }
}

struct LaunchJobRuntimeDiagnostics: Hashable, Codable, Sendable {
    var launchdLoaded: Bool?
    var runtimeTargetMissing: Bool?
    var plistIsReadable: Bool?
    var executableExists: Bool?
    var executableIsExecutable: Bool?
    var recentExitCode: Int?
    var recentRestartCount: Int?
    var restartWindowSeconds: Int?

    init(
        launchdLoaded: Bool? = nil,
        runtimeTargetMissing: Bool? = nil,
        plistIsReadable: Bool? = nil,
        executableExists: Bool? = nil,
        executableIsExecutable: Bool? = nil,
        recentExitCode: Int? = nil,
        recentRestartCount: Int? = nil,
        restartWindowSeconds: Int? = nil
    ) {
        self.launchdLoaded = launchdLoaded
        self.runtimeTargetMissing = runtimeTargetMissing
        self.plistIsReadable = plistIsReadable
        self.executableExists = executableExists
        self.executableIsExecutable = executableIsExecutable
        self.recentExitCode = recentExitCode
        self.recentRestartCount = recentRestartCount
        self.restartWindowSeconds = restartWindowSeconds
    }
}

struct LaunchJobHealthReport: Hashable, Codable, Sendable {
    let status: LaunchJobHealthStatus
    let score: Int
    let orderedFactors: [LaunchJobRiskFactor]
    let summary: String
    let primaryExplanation: String?
    let remediationHint: String?

    var explanations: [String] {
        orderedFactors.map(\.explanation)
    }

    var hasFactors: Bool { orderedFactors.isEmpty == false }

    var badgeText: String {
        "\(status.title) \(score)"
    }

    static func healthy() -> LaunchJobHealthReport {
        LaunchJobHealthReport(
            status: .healthy,
            score: 100,
            orderedFactors: [],
            summary: "No operational risk factors detected.",
            primaryExplanation: nil,
            remediationHint: nil
        )
    }
}

struct LaunchJobHealthEvaluator: Sendable {
    private enum Policy {
        static let scoreFloor = 0
        static let scoreCeiling = 100
        static let aggressiveIntervalThreshold = 60
        static let severeIntervalThreshold = 30
        static let suspiciousRestartCountThreshold = 3
        static let suspiciousRestartWindowSeconds = 10 * 60
        static let systemLabelPrefixes = ["com.apple.", "com.apple"]
        static let trustedBinaryPrefixes = [
            "/System/Library/",
            "/Library/PrivilegedHelperTools/",
            "/usr/bin/",
            "/usr/sbin/",
            "/usr/libexec/",
            "/bin/"
        ]
        static let suspiciousPathFragments = [
            "/Downloads/",
            "/Desktop/",
            "/Documents/",
            "/.Trash/",
            "/tmp/",
            "/private/tmp/",
            "/var/tmp/",
            "/var/folders/"
        ]
    }

    init() {}

    func evaluate(
        job: LaunchServiceJob,
        runtimeDiagnostics: LaunchJobRuntimeDiagnostics? = nil
    ) -> LaunchJobHealthReport {
        var factors: [LaunchJobRiskFactor] = []

        evaluatePlist(job: job, runtimeDiagnostics: runtimeDiagnostics, factors: &factors)
        evaluateExecutable(job: job, runtimeDiagnostics: runtimeDiagnostics, factors: &factors)
        evaluateRuntime(job: job, runtimeDiagnostics: runtimeDiagnostics, factors: &factors)
        evaluateSchedule(job: job, factors: &factors)
        evaluatePaths(job: job, factors: &factors)
        evaluateIdentity(job: job, factors: &factors)
        evaluateOrphaning(job: job, runtimeDiagnostics: runtimeDiagnostics, factors: &factors)

        let orderedFactors = factors.sorted(by: sortFactors)
        let score = Self.score(for: orderedFactors)
        let status = Self.status(for: job, factors: orderedFactors, runtimeDiagnostics: runtimeDiagnostics)

        return LaunchJobHealthReport(
            status: status,
            score: score,
            orderedFactors: orderedFactors,
            summary: Self.summary(for: status, factors: orderedFactors, score: score),
            primaryExplanation: orderedFactors.first?.explanation,
            remediationHint: orderedFactors.compactMap(\.remediationHint).first
        )
    }

    private func evaluatePlist(
        job: LaunchServiceJob,
        runtimeDiagnostics: LaunchJobRuntimeDiagnostics?,
        factors: inout [LaunchJobRiskFactor]
    ) {
        guard let plistPath = job.plistPath?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            if job.isLoaded {
                factors.append(
                    LaunchJobRiskFactor(
                        kind: .orphanedTarget,
                        severity: .high,
                        title: "Loaded job has no plist",
                        explanation: "Launchd reports this job as loaded, but LaunchDeck cannot link it back to a plist file.",
                        evidence: "Label: \(job.label)",
                        remediationHint: "Refresh the scan or locate the source plist before attempting edits."
                    )
                )
            }
            return
        }

        if plistPath.isEmpty || plistPath.contains("..") || plistPath.hasPrefix("~/") {
            factors.append(
                LaunchJobRiskFactor(
                    kind: .invalidPlistPath,
                    severity: .critical,
                    title: "Invalid plist path",
                    explanation: "The plist path is malformed or unsafe to resolve reliably.",
                    evidence: plistPath,
                    remediationHint: "Move the plist to a stable absolute path and refresh the job scan."
                )
            )
        }

        if runtimeDiagnostics?.plistIsReadable == false {
            factors.append(
                LaunchJobRiskFactor(
                    kind: .inaccessiblePlist,
                    severity: .critical,
                    title: "Plist is inaccessible",
                    explanation: "LaunchDeck cannot read the plist at the configured path.",
                    evidence: plistPath,
                    remediationHint: "Check file ownership, permissions, and that the plist still exists."
                )
            )
        }
    }

    private func evaluateExecutable(
        job: LaunchServiceJob,
        runtimeDiagnostics: LaunchJobRuntimeDiagnostics?,
        factors: inout [LaunchJobRiskFactor]
    ) {
        guard let program = normalizedProgramPath(job.program) else {
            if job.plistPath != nil {
                factors.append(
                    LaunchJobRiskFactor(
                        kind: .malformedConfiguration,
                        severity: .critical,
                        title: "Executable target missing",
                        explanation: "The job configuration does not define a usable executable path.",
                        evidence: "Program key is empty or missing",
                        remediationHint: "Update the Program or ProgramArguments entries to point at a real executable."
                    )
                )
            }
            return
        }

        if runtimeDiagnostics?.executableExists == false {
            factors.append(
                LaunchJobRiskFactor(
                    kind: .missingExecutable,
                    severity: .critical,
                    title: "Executable missing",
                    explanation: "The configured executable cannot be found on disk.",
                    evidence: program,
                    remediationHint: "Point the job at a valid binary or reinstall the missing software."
                )
            )
        }

        if runtimeDiagnostics?.executableIsExecutable == false {
            factors.append(
                LaunchJobRiskFactor(
                    kind: .nonExecutableBinary,
                    severity: .critical,
                    title: "Executable is not runnable",
                    explanation: "The configured binary exists, but macOS cannot execute it.",
                    evidence: program,
                    remediationHint: "Fix the file permissions or replace the binary with a valid executable."
                )
            )
        }
    }

    private func evaluateRuntime(
        job: LaunchServiceJob,
        runtimeDiagnostics: LaunchJobRuntimeDiagnostics?,
        factors: inout [LaunchJobRiskFactor]
    ) {
        let effectiveExitCode = runtimeDiagnostics?.recentExitCode ?? job.exitCode
        if let effectiveExitCode, effectiveExitCode != 0 {
            factors.append(
                LaunchJobRiskFactor(
                    kind: .nonZeroExitCode,
                    severity: .critical,
                    title: "Non-zero exit code",
                    explanation: "The job exited with status \(effectiveExitCode).",
                    evidence: "Exit code \(effectiveExitCode)",
                    remediationHint: "Inspect the job's logs and launch arguments to find the runtime failure."
                )
            )
        }

        if let restartCount = runtimeDiagnostics?.recentRestartCount, restartCount >= Policy.suspiciousRestartCountThreshold {
            let window = runtimeDiagnostics?.restartWindowSeconds
            guard window.map({ $0 <= Policy.suspiciousRestartWindowSeconds }) ?? true else {
                return
            }
            let severity: LaunchJobRiskSeverity = restartCount >= 6 ? .high : .medium
            let windowText = window.map { "\($0)s" } ?? "an unknown window"
            factors.append(
                LaunchJobRiskFactor(
                    kind: .repeatedRestarts,
                    severity: severity,
                    title: "Repeated restarts",
                    explanation: "The job restarted \(restartCount) times within \(windowText).",
                    evidence: "Restarts: \(restartCount)",
                    remediationHint: "Review keep-alive behavior, crash loops, and recent plist changes."
                )
            )
        }

        if job.state == .running, job.pid == nil {
            factors.append(
                LaunchJobRiskFactor(
                    kind: .missingRuntimeInfo,
                    severity: .low,
                    title: "Missing runtime info",
                    explanation: "LaunchDeck expected a live process record, but the runtime snapshot is incomplete.",
                    evidence: "State: running",
                    remediationHint: "Refresh the scan to collect a newer launchd snapshot."
                )
            )
        }

        if job.state == .crashed, job.exitCode == nil, runtimeDiagnostics?.recentExitCode == nil {
            factors.append(
                LaunchJobRiskFactor(
                    kind: .missingRuntimeInfo,
                    severity: .low,
                    title: "Crash metadata missing",
                    explanation: "The job is marked crashed, but no exit code is available for review.",
                    evidence: "State: crashed",
                    remediationHint: "Refresh the scan or inspect launchd logs for the missing failure detail."
                )
            )
        }

        if let launchdLoaded = runtimeDiagnostics?.launchdLoaded, launchdLoaded != job.isLoaded {
            factors.append(
                LaunchJobRiskFactor(
                    kind: .loadedStateMismatch,
                    severity: .medium,
                    title: "Loaded state mismatch",
                    explanation: "Launchd's runtime state does not match LaunchDeck's view of the job.",
                    evidence: "LaunchDeck: \(job.isLoaded ? "loaded" : "unloaded"), launchd: \(launchdLoaded ? "loaded" : "unloaded")",
                    remediationHint: "Refresh the scan. If the mismatch persists, the job may have been reloaded or booted out elsewhere."
                )
            )
        }
    }

    private func evaluateSchedule(job: LaunchServiceJob, factors: inout [LaunchJobRiskFactor]) {
        switch job.schedule {
        case .interval(let seconds):
            if seconds <= Policy.severeIntervalThreshold {
                factors.append(
                    LaunchJobRiskFactor(
                        kind: .aggressiveInterval,
                        severity: .high,
                        title: "Extremely aggressive interval",
                        explanation: "The job is scheduled to run every \(seconds) seconds, which is unusually aggressive.",
                        evidence: "StartInterval \(seconds)s",
                        remediationHint: "Confirm that the interval is intentional and that the job will not overwhelm the machine."
                    )
                )
            } else if seconds <= Policy.aggressiveIntervalThreshold {
                factors.append(
                    LaunchJobRiskFactor(
                        kind: .aggressiveInterval,
                        severity: .medium,
                        title: "Aggressive interval",
                        explanation: "The job is scheduled very frequently at every \(seconds) seconds.",
                        evidence: "StartInterval \(seconds)s",
                        remediationHint: "Consider whether the service can run less often without losing reliability."
                    )
                )
            }
        case .calendar, .none:
            break
        }
    }

    private func evaluatePaths(job: LaunchServiceJob, factors: inout [LaunchJobRiskFactor]) {
        if let standardOutPath = suspiciousPath(job.standardOutPath) {
            factors.append(
                LaunchJobRiskFactor(
                    kind: .suspiciousLogPath,
                    severity: .medium,
                    title: "Suspicious log path",
                    explanation: "The standard output path points at a fragile or user-writable location.",
                    evidence: standardOutPath,
                    remediationHint: "Move logs to a stable directory such as a dedicated folder under ~/Library/Logs or /Library/Logs."
                )
            )
        }

        if let standardErrorPath = suspiciousPath(job.standardErrorPath) {
            factors.append(
                LaunchJobRiskFactor(
                    kind: .suspiciousLogPath,
                    severity: .medium,
                    title: "Suspicious error log path",
                    explanation: "The standard error path points at a fragile or user-writable location.",
                    evidence: standardErrorPath,
                    remediationHint: "Move logs to a stable directory such as a dedicated folder under ~/Library/Logs or /Library/Logs."
                )
            )
        }

        if let program = normalizedProgramPath(job.program), Self.isSuspiciousBinaryLocation(program) {
            factors.append(
                LaunchJobRiskFactor(
                    kind: .suspiciousBinaryLocation,
                    severity: .high,
                    title: "Suspicious binary location",
                    explanation: "The executable lives in a user-writable or transient location.",
                    evidence: program,
                    remediationHint: "Install the binary into a stable signed application or system location."
                )
            )
        }
    }

    private func evaluateIdentity(job: LaunchServiceJob, factors: inout [LaunchJobRiskFactor]) {
        guard let program = normalizedProgramPath(job.program) else { return }
        let isSystemLike = job.domain == .systemAgent || job.domain == .systemDaemon || Self.isSystemLikeLabel(job.label)
        guard isSystemLike else { return }

        if Self.isNonSystemBinary(program) {
            factors.append(
                LaunchJobRiskFactor(
                    kind: .systemLikeLabelBackedByNonSystemBinary,
                    severity: .high,
                    title: "System-like label with non-system binary",
                    explanation: "The label or domain looks system-owned, but the executable is not in a trusted system location.",
                    evidence: program,
                    remediationHint: "Verify that the job belongs in the system domain and that the binary comes from a trusted source."
                )
            )
        }
    }

    private func evaluateOrphaning(
        job: LaunchServiceJob,
        runtimeDiagnostics: LaunchJobRuntimeDiagnostics?,
        factors: inout [LaunchJobRiskFactor]
    ) {
        if job.plistPath == nil, job.isLoaded {
            factors.append(
                LaunchJobRiskFactor(
                    kind: .orphanedTarget,
                    severity: .high,
                    title: "Orphaned live job",
                    explanation: "Launchd has a live job record, but LaunchDeck cannot find the source plist.",
                    evidence: job.label,
                    remediationHint: "Locate the original plist or remove the stale launchd entry."
                )
            )
        }

        if runtimeDiagnostics?.runtimeTargetMissing == true, job.plistPath != nil {
            factors.append(
                LaunchJobRiskFactor(
                    kind: .orphanedTarget,
                    severity: .high,
                    title: "Orphaned configuration",
                    explanation: "The plist still exists, but the job's functional target appears to be missing.",
                    evidence: job.plistPath,
                    remediationHint: "Recreate or repair the executable target, then refresh the launchd scan."
                )
            )
        }
    }

    private func sortFactors(_ lhs: LaunchJobRiskFactor, _ rhs: LaunchJobRiskFactor) -> Bool {
        if lhs.severity.rank == rhs.severity.rank {
            if lhs.scoreImpact == rhs.scoreImpact {
                if lhs.kind.rawValue == rhs.kind.rawValue {
                    return lhs.id < rhs.id
                }
                return lhs.kind.rawValue < rhs.kind.rawValue
            }
            return lhs.scoreImpact > rhs.scoreImpact
        }
        return lhs.severity.rank > rhs.severity.rank
    }

    private static func score(for factors: [LaunchJobRiskFactor]) -> Int {
        let totalPenalty = factors.reduce(into: 0) { $0 += $1.scoreImpact }
        return max(Policy.scoreFloor, Policy.scoreCeiling - totalPenalty)
    }

    private static func status(
        for job: LaunchServiceJob,
        factors: [LaunchJobRiskFactor],
        runtimeDiagnostics: LaunchJobRuntimeDiagnostics?
    ) -> LaunchJobHealthStatus {
        if factors.contains(where: Self.isBrokenFactor) {
            return .broken
        }

        if factors.contains(where: { $0.kind == .orphanedTarget }) {
            return .orphaned
        }

        if factors.contains(where: Self.isSuspiciousFactor) {
            return .suspicious
        }

        if factors.isEmpty {
            return .healthy
        }

        let warningScore = score(for: factors)
        if warningScore >= 90, job.isLoaded == false, runtimeDiagnostics?.launchdLoaded == nil {
            return .healthy
        }
        return .warning
    }

    private static func summary(for status: LaunchJobHealthStatus, factors: [LaunchJobRiskFactor], score: Int) -> String {
        guard let firstFactor = factors.first else {
            return "Healthy with a score of \(score)/100."
        }

        let leadingExplanation = firstFactor.explanation
        switch status {
        case .healthy:
            return "Healthy with a score of \(score)/100."
        case .warning:
            return "Attention recommended: \(leadingExplanation)"
        case .broken:
            return "Broken: \(leadingExplanation)"
        case .suspicious:
            return "Suspicious: \(leadingExplanation)"
        case .orphaned:
            return "Orphaned: \(leadingExplanation)"
        }
    }

    private static func isBrokenFactor(_ factor: LaunchJobRiskFactor) -> Bool {
        switch factor.kind {
        case .missingExecutable,
             .nonExecutableBinary,
             .invalidPlistPath,
             .inaccessiblePlist,
             .nonZeroExitCode,
             .malformedConfiguration:
            return true
        case .loadedStateMismatch,
             .repeatedRestarts,
             .suspiciousLogPath,
             .suspiciousBinaryLocation,
             .systemLikeLabelBackedByNonSystemBinary,
             .aggressiveInterval,
             .missingRuntimeInfo,
             .orphanedTarget:
            return false
        }
    }

    private static func isSuspiciousFactor(_ factor: LaunchJobRiskFactor) -> Bool {
        switch factor.kind {
        case .suspiciousLogPath,
             .suspiciousBinaryLocation,
             .systemLikeLabelBackedByNonSystemBinary:
            return true
        case .missingExecutable,
             .nonExecutableBinary,
             .invalidPlistPath,
             .inaccessiblePlist,
             .loadedStateMismatch,
             .nonZeroExitCode,
             .repeatedRestarts,
             .aggressiveInterval,
             .malformedConfiguration,
             .missingRuntimeInfo,
             .orphanedTarget:
            return false
        }
    }

    private static func isSystemLikeLabel(_ label: String) -> Bool {
        Policy.systemLabelPrefixes.contains(where: { label.hasPrefix($0) })
    }

    private func normalizedProgramPath(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), trimmed.isEmpty == false else {
            return nil
        }
        return trimmed
    }

    private func suspiciousPath(_ value: String?) -> String? {
        guard let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines), raw.isEmpty == false else {
            return nil
        }

        let expanded = NSString(string: raw).expandingTildeInPath
        if expanded.contains("..") {
            return expanded
        }

        if Self.isSuspiciousBinaryLocation(expanded) {
            return expanded
        }

        return nil
    }

    private static func isSuspiciousBinaryLocation(_ path: String) -> Bool {
        let expanded = NSString(string: path).expandingTildeInPath
        return Policy.suspiciousPathFragments.contains(where: { expanded.localizedCaseInsensitiveContains($0) })
    }

    private static func isNonSystemBinary(_ path: String) -> Bool {
        let expanded = NSString(string: path).expandingTildeInPath
        return Policy.trustedBinaryPrefixes.contains(where: { expanded.hasPrefix($0) }) == false
    }
}
