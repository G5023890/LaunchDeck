import Foundation

struct LaunchJobProcessResolution: Hashable, Sendable {
    enum Confidence: String, CaseIterable, Hashable, Sendable {
        case exact
        case likely
        case uncertain
        case none

        var title: String {
            switch self {
            case .exact:
                return "Exact"
            case .likely:
                return "Likely"
            case .uncertain:
                return "Uncertain"
            case .none:
                return "Not Found"
            }
        }
    }

    enum MatchKind: String, CaseIterable, Hashable, Sendable {
        case directPID
        case executablePath
        case labelCorrelation
    }

    let process: RunningProcess?
    let confidence: Confidence
    let matchedBy: MatchKind?
    let reason: String
    let candidateCount: Int

    var isAssociated: Bool { process != nil }
    var isUncertain: Bool { confidence == .uncertain }
}

struct LaunchJobResourceSnapshot: Hashable, Sendable {
    let timestamp: Date
    let jobID: String
    let label: String
    let reportedPID: Int?
    let resolution: LaunchJobProcessResolution
    let cpu: Double?
    let memoryMB: Double?
    let uptime: String?
    let processState: String?
    let executablePath: String?
    let childProcessCount: Int?
    let openFilesCount: Int?

    var pidText: String {
        if let pid = resolution.process?.pid ?? reportedPID {
            return String(pid)
        }
        return "-"
    }

    var cpuText: String {
        guard let cpu else { return "-" }
        return String(format: "%.1f%%", cpu)
    }

    var memoryText: String {
        guard let memoryMB else { return "-" }
        if memoryMB >= 1024 {
            return String(format: "%.2f GB", memoryMB / 1024)
        }
        return String(format: "%.1f MB", memoryMB)
    }

    var uptimeText: String { uptime ?? "-" }

    var stateText: String { processState ?? "-" }

    var childProcessCountText: String {
        childProcessCount.map(String.init) ?? "-"
    }

    var openFilesCountText: String {
        openFilesCount.map(String.init) ?? "-"
    }

    var executablePathText: String {
        executablePath ?? "-"
    }
}

struct LaunchJobResourceTrend: Hashable, Sendable {
    enum Direction: String, CaseIterable, Hashable, Sendable {
        case rising
        case falling
        case stable

        var symbol: String {
            switch self {
            case .rising:
                return "arrow.up.right"
            case .falling:
                return "arrow.down.right"
            case .stable:
                return "minus"
            }
        }
    }

    let windowSeconds: Int
    let sampleCount: Int
    let currentCPU: Double
    let averageCPU: Double
    let cpuDelta: Double
    let currentMemoryMB: Double
    let averageMemoryMB: Double
    let memoryDelta: Double

    var cpuDirection: Direction {
        Self.direction(for: cpuDelta)
    }

    var memoryDirection: Direction {
        Self.direction(for: memoryDelta)
    }

    private static func direction(for delta: Double) -> Direction {
        if abs(delta) < 0.05 {
            return .stable
        }
        return delta > 0 ? .rising : .falling
    }
}

struct LaunchJobResourceTimeline: Hashable, Sendable {
    struct Sample: Identifiable, Hashable, Sendable {
        let timestamp: Date
        let cpu: Double
        let memoryMB: Double

        var id: TimeInterval { timestamp.timeIntervalSinceReferenceDate }
    }

    private(set) var samples: [Sample] = []
    var retentionWindow: TimeInterval = 300
    var maximumSamples: Int = 180

    mutating func reset() {
        samples.removeAll(keepingCapacity: true)
    }

    mutating func append(snapshot: LaunchJobResourceSnapshot) {
        guard let cpu = snapshot.cpu, let memoryMB = snapshot.memoryMB else { return }
        samples.append(Sample(timestamp: snapshot.timestamp, cpu: cpu, memoryMB: memoryMB))
        prune(keepingLatestAt: snapshot.timestamp)
    }

    func trend(windowSeconds: Int, now: Date = Date()) -> LaunchJobResourceTrend? {
        guard let latest = samples.last else { return nil }

        let cutoff = now.addingTimeInterval(TimeInterval(-windowSeconds))
        let windowSamples = samples.filter { $0.timestamp >= cutoff }
        guard let first = windowSamples.first else { return nil }

        let cpuValues = windowSamples.map(\.cpu)
        let memoryValues = windowSamples.map(\.memoryMB)

        let averageCPU = cpuValues.reduce(0, +) / Double(cpuValues.count)
        let averageMemory = memoryValues.reduce(0, +) / Double(memoryValues.count)

        return LaunchJobResourceTrend(
            windowSeconds: windowSeconds,
            sampleCount: windowSamples.count,
            currentCPU: latest.cpu,
            averageCPU: averageCPU,
            cpuDelta: latest.cpu - first.cpu,
            currentMemoryMB: latest.memoryMB,
            averageMemoryMB: averageMemory,
            memoryDelta: latest.memoryMB - first.memoryMB
        )
    }

    private mutating func prune(keepingLatestAt timestamp: Date) {
        let cutoff = timestamp.addingTimeInterval(-retentionWindow)
        samples.removeAll { $0.timestamp < cutoff }
        if samples.count > maximumSamples {
            samples = Array(samples.suffix(maximumSamples))
        }
    }
}

struct ResourceOverlayViewModel: Hashable, Sendable {
    let jobID: String?
    let label: String?
    let resolution: LaunchJobProcessResolution?
    let snapshot: LaunchJobResourceSnapshot?
    let timeline: LaunchJobResourceTimeline

    static let empty = ResourceOverlayViewModel(
        jobID: nil,
        label: nil,
        resolution: nil,
        snapshot: nil,
        timeline: LaunchJobResourceTimeline()
    )

    var isEmpty: Bool { snapshot == nil }

    var confidenceText: String? {
        resolution?.confidence.title
    }

    var uncertaintyText: String? {
        guard let resolution, resolution.confidence != .exact else { return nil }
        return resolution.reason
    }

    var oneMinuteTrend: LaunchJobResourceTrend? {
        timeline.trend(windowSeconds: 60)
    }

    var fiveMinuteTrend: LaunchJobResourceTrend? {
        timeline.trend(windowSeconds: 300)
    }
}

struct LaunchJobProcessResolver: Sendable {
    func resolve(job: LaunchServiceJob, runningProcesses: [RunningProcess]) -> LaunchJobProcessResolution {
        let processesByPID = Dictionary(uniqueKeysWithValues: runningProcesses.map { ($0.pid, $0) })

        if let pid = job.pid, let process = processesByPID[pid] {
            let supportsExecutableMatch = Self.matchesExecutable(job: job, process: process)
            let confidence: LaunchJobProcessResolution.Confidence = supportsExecutableMatch ? .exact : .likely
            let reason = supportsExecutableMatch
                ? "Matched launchd PID \(pid) and executable metadata."
                : "Matched launchd PID \(pid); executable metadata does not fully align."

            return LaunchJobProcessResolution(
                process: process,
                confidence: confidence,
                matchedBy: .directPID,
                reason: reason,
                candidateCount: 1
            )
        }

        let executableMatches = runningProcesses.filter { process in
            Self.matchesExecutable(job: job, process: process)
        }
        if executableMatches.count == 1, let process = executableMatches.first {
            let path = process.binaryPath ?? process.commandPath
            return LaunchJobProcessResolution(
                process: process,
                confidence: .exact,
                matchedBy: .executablePath,
                reason: "Matched executable path \(path).",
                candidateCount: 1
            )
        }
        if executableMatches.count > 1, let process = executableMatches.first {
            let path = process.binaryPath ?? process.commandPath
            return LaunchJobProcessResolution(
                process: process,
                confidence: .uncertain,
                matchedBy: .executablePath,
                reason: "Multiple processes match executable path \(path).",
                candidateCount: executableMatches.count
            )
        }

        let labelMatches = runningProcesses.filter { process in
            Self.matchesLabel(job: job, process: process)
        }
        if labelMatches.count == 1, let process = labelMatches.first {
            return LaunchJobProcessResolution(
                process: process,
                confidence: .likely,
                matchedBy: .labelCorrelation,
                reason: "Matched process name to label suffix.",
                candidateCount: 1
            )
        }
        if labelMatches.count > 1, let process = labelMatches.first {
            return LaunchJobProcessResolution(
                process: process,
                confidence: .uncertain,
                matchedBy: .labelCorrelation,
                reason: "Multiple processes loosely match the label suffix.",
                candidateCount: labelMatches.count
            )
        }

        return LaunchJobProcessResolution(
            process: nil,
            confidence: .none,
            matchedBy: nil,
            reason: job.pid != nil
                ? "No live process matched PID \(job.pidText)."
                : "No live process matched this launchd job.",
            candidateCount: 0
        )
    }

    private static func matchesExecutable(job: LaunchServiceJob, process: RunningProcess) -> Bool {
        let jobExecutablePaths = normalizedExecutablePaths(for: job)
        guard !jobExecutablePaths.isEmpty else { return false }

        if let binaryPath = process.binaryPath, jobExecutablePaths.contains(Self.normalizePath(binaryPath)) {
            return true
        }

        let processPath = Self.normalizePath(process.commandPath)
        return jobExecutablePaths.contains(processPath)
    }

    private static func matchesLabel(job: LaunchServiceJob, process: RunningProcess) -> Bool {
        let suffix = normalizedLabelSuffix(for: job.label)
        guard !suffix.isEmpty else { return false }

        let processName = process.processName.lowercased()
        if processName == suffix {
            return true
        }

        if let binaryName = process.binaryPath.map({ URL(fileURLWithPath: $0).lastPathComponent.lowercased() }) {
            return binaryName == suffix
        }

        return false
    }

    private static func normalizedExecutablePaths(for job: LaunchServiceJob) -> Set<String> {
        var paths: Set<String> = []
        if let program = job.program, program.hasPrefix("/") {
            paths.insert(normalizePath(program))
        }
        if let firstArgument = job.arguments.first, firstArgument.hasPrefix("/") {
            paths.insert(normalizePath(firstArgument))
        }
        return paths
    }

    private static func normalizedLabelSuffix(for label: String) -> String {
        label
            .split(separator: ".")
            .last
            .map(String.init)?
            .lowercased() ?? label.lowercased()
    }

    private static func normalizePath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }
}

extension RunningProcess {
    var processStateText: String? {
        guard let processState else { return nil }

        let trimmed = processState.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        switch trimmed.uppercased() {
        case "R":
            return "Running"
        case "S":
            return "Sleeping"
        case "I":
            return "Idle"
        case "T":
            return "Stopped"
        case "U":
            return "Uninterruptible"
        case "Z":
            return "Zombie"
        default:
            return trimmed
        }
    }
}
