import Foundation

struct LaunchJobRelationAnalysis: Hashable, Sendable {
    let selectedJob: LaunchServiceJob
    let relatedJobs: [LaunchJobRelation]
    let graph: RelationGraph
}

struct LaunchJobRelationGroup: Identifiable, Hashable, Sendable {
    let kind: LaunchJobRelationKind
    let relations: [LaunchJobRelation]

    var id: String { kind.rawValue }
}

enum LaunchJobRelationKind: String, CaseIterable, Identifiable, Codable, Hashable, Sendable {
    case sameExecutablePath
    case sameExecutableDirectory
    case sameLabelNamespace
    case sharedWatchPath
    case sharedQueueDirectory
    case sharedLogFile
    case sharedWorkingDirectory
    case sharedEnvironmentSignature
    case sameOwnerScope
    case sameManagedOrigin
    case sameRuntimeProcessFamily

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sameExecutablePath:
            return "Executable Path"
        case .sameExecutableDirectory:
            return "Executable Directory"
        case .sameLabelNamespace:
            return "Label Family"
        case .sharedWatchPath:
            return "Watch Paths"
        case .sharedQueueDirectory:
            return "Queue Directories"
        case .sharedLogFile:
            return "Log Files"
        case .sharedWorkingDirectory:
            return "Working Directory"
        case .sharedEnvironmentSignature:
            return "Environment"
        case .sameOwnerScope:
            return "Owner / Domain"
        case .sameManagedOrigin:
            return "Managed Origin"
        case .sameRuntimeProcessFamily:
            return "Runtime Family"
        }
    }

    var scoreWeight: Int {
        switch self {
        case .sameExecutablePath:
            return 100
        case .sameExecutableDirectory:
            return 72
        case .sameLabelNamespace:
            return 34
        case .sharedWatchPath:
            return 48
        case .sharedQueueDirectory:
            return 50
        case .sharedLogFile:
            return 42
        case .sharedWorkingDirectory:
            return 28
        case .sharedEnvironmentSignature:
            return 24
        case .sameOwnerScope:
            return 18
        case .sameManagedOrigin:
            return 82
        case .sameRuntimeProcessFamily:
            return 64
        }
    }
}

struct LaunchJobRelationScore: Hashable, Codable, Comparable, Sendable {
    let value: Int

    var priority: String {
        switch value {
        case 80...:
            return "High"
        case 45..<80:
            return "Medium"
        default:
            return "Low"
        }
    }

    static func < (lhs: LaunchJobRelationScore, rhs: LaunchJobRelationScore) -> Bool {
        lhs.value < rhs.value
    }
}

struct LaunchJobRelationReason: Hashable, Codable, Sendable {
    let kind: LaunchJobRelationKind
    let summary: String
    let detail: String?

    init(kind: LaunchJobRelationKind, summary: String, detail: String? = nil) {
        self.kind = kind
        self.summary = summary
        self.detail = detail
    }
}

struct LaunchJobRelation: Identifiable, Hashable, Sendable {
    let selectedJobID: String
    let relatedJob: LaunchServiceJob
    let score: LaunchJobRelationScore
    let reasons: [LaunchJobRelationReason]

    var id: String { "\(selectedJobID)::\(relatedJob.id)" }

    var primaryKind: LaunchJobRelationKind {
        reasons.max(by: { $0.kind.scoreWeight < $1.kind.scoreWeight })?.kind ?? .sameOwnerScope
    }

    var kinds: [LaunchJobRelationKind] {
        var seen = Set<LaunchJobRelationKind>()
        return reasons.compactMap { reason in
            guard seen.insert(reason.kind).inserted else { return nil }
            return reason.kind
        }
    }
}

struct RelationGraphNode: Identifiable, Hashable, Sendable {
    let id: String
    let label: String
    let subtitle: String?
    let score: Int
    let isSelected: Bool
}

struct RelationGraphEdge: Identifiable, Hashable, Sendable {
    let id: String
    let sourceID: String
    let targetID: String
    let kind: LaunchJobRelationKind
    let score: Int
    let label: String
}

struct RelationGraph: Hashable, Sendable {
    let nodes: [RelationGraphNode]
    let edges: [RelationGraphEdge]
}

struct LaunchJobRelationAnalyzer: Sendable {
    func makeIndex(
        jobs: [LaunchServiceJob],
        runningProcesses: [RunningProcess] = []
    ) -> Index {
        Index(jobs: jobs, runningProcesses: runningProcesses)
    }

    func analyze(
        selectedJob: LaunchServiceJob,
        jobs: [LaunchServiceJob],
        runningProcesses: [RunningProcess] = []
    ) -> LaunchJobRelationAnalysis {
        let index = makeIndex(jobs: jobs, runningProcesses: runningProcesses)
        return index.analysis(for: selectedJob)
    }

    struct Index {
        let jobsByID: [String: LaunchServiceJob]
        let runningProcessByPID: [Int: RunningProcess]
        let executablePathIndex: [String: [String]]
        let executableDirectoryIndex: [String: [String]]
        let labelPrefixIndex: [String: [String]]
        let watchPathIndex: [String: [String]]
        let queueDirectoryIndex: [String: [String]]
        let logPathIndex: [String: [String]]
        let workingDirectoryIndex: [String: [String]]
        let environmentSignatureIndex: [String: [String]]
        let ownerDomainIndex: [String: [String]]
        let managedOriginIndex: [String: [String]]
        let runtimeFamilyIndex: [String: [String]]
        let runtimeFamilyByPID: [Int: String]
        let runtimeFamilyDisplayNames: [String: String]

        init(jobs: [LaunchServiceJob], runningProcesses: [RunningProcess]) {
            var jobsByID: [String: LaunchServiceJob] = [:]
            let runningProcessByPID = Dictionary(uniqueKeysWithValues: runningProcesses.map { ($0.pid, $0) })
            var executablePathIndex: [String: [String]] = [:]
            var executableDirectoryIndex: [String: [String]] = [:]
            var labelPrefixIndex: [String: [String]] = [:]
            var watchPathIndex: [String: [String]] = [:]
            var queueDirectoryIndex: [String: [String]] = [:]
            var logPathIndex: [String: [String]] = [:]
            var workingDirectoryIndex: [String: [String]] = [:]
            var environmentSignatureIndex: [String: [String]] = [:]
            var ownerDomainIndex: [String: [String]] = [:]
            var managedOriginIndex: [String: [String]] = [:]

            for job in jobs {
                jobsByID[job.id] = job

                if let path = Self.observableExecutablePath(for: job, runningProcessByPID: runningProcessByPID) {
                    executablePathIndex[path, default: []].append(job.id)
                    let directory = URL(fileURLWithPath: path).deletingLastPathComponent().path
                    executableDirectoryIndex[directory, default: []].append(job.id)
                }

                for prefix in Self.labelPrefixes(for: job.label) {
                    labelPrefixIndex[prefix, default: []].append(job.id)
                }

                for path in job.watchPaths.compactMap(Self.canonicalPath) {
                    watchPathIndex[path, default: []].append(job.id)
                }

                for path in job.queueDirectories.compactMap(Self.canonicalPath) {
                    queueDirectoryIndex[path, default: []].append(job.id)
                }

                for path in [job.standardOutPath, job.standardErrorPath].compactMap(Self.canonicalPath) {
                    logPathIndex[path, default: []].append(job.id)
                }

                if let workingDirectory = Self.canonicalPath(job.workingDirectory) {
                    workingDirectoryIndex[workingDirectory, default: []].append(job.id)
                }

                let envSignature = Self.environmentSignature(for: job.environmentVariables)
                if let envSignature {
                    environmentSignatureIndex[envSignature, default: []].append(job.id)
                }

                for key in Self.ownerDomainKeys(for: job) {
                    ownerDomainIndex[key, default: []].append(job.id)
                }

                if let managedOrigin = Self.managedOriginKey(for: job) {
                    managedOriginIndex[managedOrigin, default: []].append(job.id)
                }
            }

            let runtimeMap = Self.runtimeFamilies(from: runningProcesses)
            self.jobsByID = jobsByID
            self.runningProcessByPID = runningProcessByPID
            self.executablePathIndex = executablePathIndex
            self.executableDirectoryIndex = executableDirectoryIndex
            self.labelPrefixIndex = labelPrefixIndex
            self.watchPathIndex = watchPathIndex
            self.queueDirectoryIndex = queueDirectoryIndex
            self.logPathIndex = logPathIndex
            self.workingDirectoryIndex = workingDirectoryIndex
            self.environmentSignatureIndex = environmentSignatureIndex
            self.ownerDomainIndex = ownerDomainIndex
            self.managedOriginIndex = managedOriginIndex
            self.runtimeFamilyIndex = runtimeMap.index
            self.runtimeFamilyByPID = runtimeMap.byPID
            self.runtimeFamilyDisplayNames = runtimeMap.displayNames
        }

        func analysis(for selectedJob: LaunchServiceJob) -> LaunchJobRelationAnalysis {
            var contributions: [String: [LaunchJobRelationReasonContribution]] = [:]

            func addReasons(
                for jobIDs: [String]?,
                kind: LaunchJobRelationKind,
                makeReason: (LaunchServiceJob) -> LaunchJobRelationReasonContribution?
            ) {
                guard let jobIDs else { return }
                for jobID in jobIDs where jobID != selectedJob.id {
                    guard let job = jobsByID[jobID], let reason = makeReason(job) else { continue }
                    contributions[jobID, default: []].append(reason)
                }
            }

            if let selectedPath = Self.observableExecutablePath(for: selectedJob, runningProcessByPID: runningProcessByPID) {
                addReasons(for: executablePathIndex[selectedPath], kind: .sameExecutablePath) { job in
                    let candidatePath = Self.observableExecutablePath(for: job, runningProcessByPID: runningProcessByPID) ?? ""
                    return .init(
                        kind: .sameExecutablePath,
                        score: LaunchJobRelationKind.sameExecutablePath.scoreWeight,
                        summary: "Shares executable path",
                        detail: candidatePath
                    )
                }

                let selectedDirectory = URL(fileURLWithPath: selectedPath).deletingLastPathComponent().path
                addReasons(for: executableDirectoryIndex[selectedDirectory], kind: .sameExecutableDirectory) { job in
                    guard let candidatePath = Self.observableExecutablePath(for: job, runningProcessByPID: runningProcessByPID) else { return nil }
                    return .init(
                        kind: .sameExecutableDirectory,
                        score: LaunchJobRelationKind.sameExecutableDirectory.scoreWeight,
                        summary: "Shares executable directory",
                        detail: URL(fileURLWithPath: candidatePath).deletingLastPathComponent().path
                    )
                }
            }

            let selectedPrefixes = Self.labelPrefixes(for: selectedJob.label)
            var bestLabelMatches: [String: (prefix: String, depth: Int)] = [:]
            for prefix in selectedPrefixes {
                guard let jobIDs = labelPrefixIndex[prefix] else { continue }
                let depth = prefix.components(separatedBy: ".").count
                for jobID in jobIDs where jobID != selectedJob.id {
                    if let current = bestLabelMatches[jobID], current.depth >= depth {
                        continue
                    }
                    bestLabelMatches[jobID] = (prefix, depth)
                }
            }

            for (jobID, match) in bestLabelMatches {
                contributions[jobID, default: []].append(
                    .init(
                        kind: .sameLabelNamespace,
                        score: LaunchJobRelationKind.sameLabelNamespace.scoreWeight + match.depth * 4,
                        summary: "Shares label family",
                        detail: match.prefix
                    )
                )
            }

            for path in selectedJob.watchPaths.compactMap(Self.canonicalPath) {
                addReasons(for: watchPathIndex[path], kind: .sharedWatchPath) { _ in
                    .init(kind: .sharedWatchPath, score: LaunchJobRelationKind.sharedWatchPath.scoreWeight, summary: "Shares watch path", detail: path)
                }
            }

            for path in selectedJob.queueDirectories.compactMap(Self.canonicalPath) {
                addReasons(for: queueDirectoryIndex[path], kind: .sharedQueueDirectory) { _ in
                    .init(kind: .sharedQueueDirectory, score: LaunchJobRelationKind.sharedQueueDirectory.scoreWeight, summary: "Uses queue directory", detail: path)
                }
            }

            for path in [selectedJob.standardOutPath, selectedJob.standardErrorPath].compactMap(Self.canonicalPath) {
                addReasons(for: logPathIndex[path], kind: .sharedLogFile) { job in
                    let field: String
                    if Self.canonicalPath(selectedJob.standardOutPath) == path {
                        field = "StandardOutPath"
                    } else {
                        field = "StandardErrorPath"
                    }
                    return .init(kind: .sharedLogFile, score: LaunchJobRelationKind.sharedLogFile.scoreWeight, summary: "Shares log file", detail: "\(field): \(path)")
                }
            }

            if let workingDirectory = Self.canonicalPath(selectedJob.workingDirectory) {
                addReasons(for: workingDirectoryIndex[workingDirectory], kind: .sharedWorkingDirectory) { _ in
                    .init(kind: .sharedWorkingDirectory, score: LaunchJobRelationKind.sharedWorkingDirectory.scoreWeight, summary: "Shares working directory", detail: workingDirectory)
                }
            }

            let selectedEnvironmentSignature = Self.environmentSignature(for: selectedJob.environmentVariables)
            if let selectedEnvironmentSignature {
                addReasons(for: environmentSignatureIndex[selectedEnvironmentSignature], kind: .sharedEnvironmentSignature) { _ in
                    .init(
                        kind: .sharedEnvironmentSignature,
                        score: LaunchJobRelationKind.sharedEnvironmentSignature.scoreWeight,
                        summary: "Shares environment signature",
                        detail: "\(selectedJob.environmentVariables.count) variables"
                    )
                }
            }

            for key in Self.ownerDomainKeys(for: selectedJob) {
                addReasons(for: ownerDomainIndex[key], kind: .sameOwnerScope) { job in
                    let sameOwner = selectedJob.ownerAccountName != nil && selectedJob.ownerAccountName == job.ownerAccountName
                    let sameDomain = selectedJob.domain == job.domain
                    guard sameOwner || sameDomain else { return nil }

                    var parts: [String] = []
                    if sameDomain {
                        parts.append("Domain: \(selectedJob.domain.title)")
                    }
                    if sameOwner, let owner = selectedJob.ownerAccountName {
                        parts.append("Owner: \(owner)")
                    }

                    let bonus = (sameOwner ? 8 : 0) + (sameDomain ? 4 : 0)
                    return .init(
                        kind: .sameOwnerScope,
                        score: LaunchJobRelationKind.sameOwnerScope.scoreWeight + bonus,
                        summary: "Shares owner or domain scope",
                        detail: parts.joined(separator: ", ")
                    )
                }
            }

            if let managedOrigin = Self.managedOriginKey(for: selectedJob) {
                addReasons(for: managedOriginIndex[managedOrigin], kind: .sameManagedOrigin) { _ in
                    .init(
                        kind: .sameManagedOrigin,
                        score: LaunchJobRelationKind.sameManagedOrigin.scoreWeight,
                        summary: "LaunchDeck-managed origin",
                        detail: managedOrigin
                    )
                }
            }

            if let selectedRuntimeFamily = Self.runtimeFamilyKey(for: selectedJob, runtimeFamilyByPID: runtimeFamilyByPID) {
                addReasons(for: runtimeFamilyIndex[selectedRuntimeFamily], kind: .sameRuntimeProcessFamily) { _ in
                    .init(
                        kind: .sameRuntimeProcessFamily,
                        score: LaunchJobRelationKind.sameRuntimeProcessFamily.scoreWeight,
                        summary: "Same runtime process family",
                        detail: runtimeFamilyDisplayNames[selectedRuntimeFamily]
                    )
                }
            }

            let relations = contributions
                .compactMap { jobID, reasons -> LaunchJobRelation? in
                    guard let job = jobsByID[jobID] else { return nil }
                    let sortedReasons = reasons.sorted { lhs, rhs in
                        if lhs.kind.scoreWeight == rhs.kind.scoreWeight {
                            return lhs.summary < rhs.summary
                        }
                        return lhs.kind.scoreWeight > rhs.kind.scoreWeight
                    }
                    let totalScore = sortedReasons.reduce(0) { $0 + $1.score }
                    return LaunchJobRelation(
                        selectedJobID: selectedJob.id,
                        relatedJob: job,
                        score: LaunchJobRelationScore(value: totalScore),
                        reasons: sortedReasons.map { LaunchJobRelationReason(kind: $0.kind, summary: $0.summary, detail: $0.detail) }
                    )
                }
                .sorted {
                    if $0.score.value == $1.score.value {
                        return $0.relatedJob.label.localizedCaseInsensitiveCompare($1.relatedJob.label) == .orderedAscending
                    }
                    return $0.score.value > $1.score.value
                }

            let graph = makeGraph(selectedJob: selectedJob, relations: relations)
            return LaunchJobRelationAnalysis(selectedJob: selectedJob, relatedJobs: relations, graph: graph)
        }

        private func makeGraph(selectedJob: LaunchServiceJob, relations: [LaunchJobRelation]) -> RelationGraph {
            let nodes = [
                RelationGraphNode(
                    id: selectedJob.id,
                    label: selectedJob.label,
                    subtitle: selectedJob.program ?? selectedJob.plistPath,
                    score: 0,
                    isSelected: true
                )
            ] + relations.map {
                RelationGraphNode(
                    id: $0.relatedJob.id,
                    label: $0.relatedJob.label,
                    subtitle: $0.reasons.first?.summary,
                    score: $0.score.value,
                    isSelected: false
                )
            }

            let edges = relations.map { relation in
                let reason = relation.reasons.first
                return RelationGraphEdge(
                    id: "\(selectedJob.id)->\(relation.relatedJob.id)",
                    sourceID: selectedJob.id,
                    targetID: relation.relatedJob.id,
                    kind: reason?.kind ?? relation.primaryKind,
                    score: relation.score.value,
                    label: reason?.summary ?? relation.primaryKind.title
                )
            }

            return RelationGraph(nodes: nodes, edges: edges)
        }

        private static func runtimeFamilies(from processes: [RunningProcess]) -> (index: [String: [String]], byPID: [Int: String], displayNames: [String: String]) {
            let processesByPID = Dictionary(uniqueKeysWithValues: processes.map { ($0.pid, $0) })
            var index: [String: [String]] = [:]
            var byPID: [Int: String] = [:]
            var displayNames: [String: String] = [:]

            for process in processes {
                guard let signature = Self.runtimeFamilySignature(for: process, processesByPID: processesByPID) else { continue }
                index[signature.key, default: []].append(signature.jobKey)
                byPID[process.pid] = signature.key
                displayNames[signature.key] = signature.displayName
            }

            return (index, byPID, displayNames)
        }

        private static func runtimeFamilySignature(
            for process: RunningProcess,
            processesByPID: [Int: RunningProcess]
        ) -> (key: String, jobKey: String, displayName: String)? {
            var ancestors: [String] = []
            var visited = Set<Int>()
            var currentPID = process.parentPID

            while let pid = currentPID, visited.insert(pid).inserted, let parent = processesByPID[pid] {
                let component = Self.normalizedProcessComponent(parent)
                guard component.isEmpty == false else { break }
                if component == "launchd" {
                    break
                }
                ancestors.append(component)
                currentPID = parent.parentPID
            }

            guard ancestors.isEmpty == false else { return nil }
            let key = ancestors.joined(separator: " > ")
            let displayName = ancestors.first ?? key
            return (key: key, jobKey: String(process.pid), displayName: displayName)
        }

        private static func runtimeFamilyKey(for job: LaunchServiceJob, runtimeFamilyByPID: [Int: String]) -> String? {
            guard let pid = job.pid else { return nil }
            return runtimeFamilyByPID[pid]
        }

        private static func observableExecutablePath(
            for job: LaunchServiceJob,
            runningProcessByPID: [Int: RunningProcess]
        ) -> String? {
            if let path = Self.canonicalPath(job.program) {
                return path
            }
            guard let pid = job.pid, let process = runningProcessByPID[pid] else { return nil }
            guard let path = Self.canonicalPath(process.binaryPath ?? process.commandPath) else { return nil }
            return path
        }

        private static func ownerDomainKeys(for job: LaunchServiceJob) -> [String] {
            var keys: [String] = [job.domain.rawValue]
            if let owner = job.ownerAccountName, owner.isEmpty == false {
                keys.append("owner::\(owner)")
            }
            return keys
        }

        private static func managedOriginKey(for job: LaunchServiceJob) -> String? {
            guard job.label.hasPrefix(LaunchctlService.managedPrefix) else { return nil }
            return "launchdeck::\(LaunchctlService.managedPrefix)"
        }

        private static func canonicalPath(_ path: String?) -> String? {
            guard let path = path?.trimmingCharacters(in: .whitespacesAndNewlines), path.isEmpty == false else { return nil }
            guard path.hasPrefix("/") else { return nil }
            return URL(fileURLWithPath: path).standardizedFileURL.path
        }

        private static func labelPrefixes(for label: String) -> [String] {
            let components = label.split(separator: ".").map(String.init)
            guard components.count >= 2 else { return [] }

            var prefixes: [String] = []
            if components.count == 2 {
                prefixes.append(components.joined(separator: "."))
                return prefixes
            }

            for end in stride(from: components.count - 1, through: 2, by: -1) {
                prefixes.append(components[0..<end].joined(separator: "."))
            }

            return prefixes
        }

        private static func environmentSignature(for variables: [String: String]) -> String? {
            guard variables.isEmpty == false else { return nil }
            return variables
                .sorted(by: { $0.key < $1.key })
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: "\u{1f}")
        }

        private static func normalizedProcessComponent(_ process: RunningProcess) -> String {
            let path = process.binaryPath ?? process.commandPath
            let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false else { return "" }
            return URL(fileURLWithPath: trimmed).lastPathComponent
        }
    }

    private struct LaunchJobRelationReasonContribution {
        let kind: LaunchJobRelationKind
        let score: Int
        let summary: String
        let detail: String?
    }
}
