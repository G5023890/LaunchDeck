import XCTest
@testable import LaunchctlDesktopApp

final class LaunchJobRelationsTests: XCTestCase {
    func testSameExecutablePathProducesStrongRelation() throws {
        let selected = makeJob(
            id: "job.selected",
            label: "com.example.alpha",
            program: "/usr/bin/tool",
            standardOutPath: "/tmp/alpha.log"
        )
        let candidate = makeJob(
            id: "job.candidate",
            label: "com.example.beta",
            program: "/usr/bin/tool",
            standardOutPath: "/tmp/beta.log"
        )

        let analysis = LaunchJobRelationAnalyzer().analyze(selectedJob: selected, jobs: [selected, candidate])

        let relation = try XCTUnwrap(analysis.relatedJobs.first)
        XCTAssertEqual(analysis.relatedJobs.count, 1)
        XCTAssertEqual(relation.relatedJob.id, candidate.id)
        XCTAssertTrue(relation.reasons.contains(where: { $0.kind == .sameExecutablePath }))
        XCTAssertGreaterThanOrEqual(relation.score.value, LaunchJobRelationKind.sameExecutablePath.scoreWeight)
    }

    func testSameLabelPrefixProducesReadableRelation() throws {
        let selected = makeJob(
            id: "job.selected",
            label: "com.example.alpha.worker",
            program: "/usr/bin/alpha"
        )
        let candidate = makeJob(
            id: "job.candidate",
            label: "com.example.alpha.helper",
            program: "/usr/bin/helper"
        )

        let analysis = LaunchJobRelationAnalyzer().analyze(selectedJob: selected, jobs: [selected, candidate])

        let relation = try XCTUnwrap(analysis.relatedJobs.first)
        XCTAssertEqual(analysis.relatedJobs.count, 1)
        XCTAssertTrue(relation.reasons.contains(where: { $0.kind == .sameLabelNamespace }))
        XCTAssertEqual(relation.reasons.first(where: { $0.kind == .sameLabelNamespace })?.detail, "com.example.alpha")
    }

    func testSharedLogFileProducesRelation() throws {
        let selected = makeJob(
            id: "job.selected",
            label: "com.example.alpha",
            program: "/usr/bin/alpha",
            standardOutPath: "/tmp/shared.log"
        )
        let candidate = makeJob(
            id: "job.candidate",
            label: "com.example.beta",
            program: "/usr/bin/beta",
            standardOutPath: "/tmp/shared.log"
        )

        let analysis = LaunchJobRelationAnalyzer().analyze(selectedJob: selected, jobs: [selected, candidate])

        let relation = try XCTUnwrap(analysis.relatedJobs.first)
        XCTAssertTrue(relation.reasons.contains(where: { $0.kind == .sharedLogFile }))
        XCTAssertEqual(relation.reasons.first(where: { $0.kind == .sharedLogFile })?.detail, "StandardOutPath: /tmp/shared.log")
    }

    func testUnrelatedJobsProduceNoRelation() {
        let selected = makeJob(
            id: "job.selected",
            label: "com.example.alpha",
            program: "/usr/bin/alpha"
        )
        let candidate = makeJob(
            id: "job.candidate",
            label: "org.other.service",
            program: "/opt/other/bin/other",
            workingDirectory: "/tmp/other",
            domain: .systemDaemon,
            ownerAccountName: nil,
            groupOwnerAccountName: nil
        )

        let analysis = LaunchJobRelationAnalyzer().analyze(selectedJob: selected, jobs: [selected, candidate])

        XCTAssertTrue(analysis.relatedJobs.isEmpty)
        XCTAssertTrue(analysis.graph.edges.isEmpty)
    }

    func testOnePairCanAccumulateMultipleReasons() throws {
        let selected = makeJob(
            id: "job.selected",
            label: "com.example.alpha.worker",
            program: "/usr/bin/tool",
            standardOutPath: "/tmp/shared.log",
            workingDirectory: "/tmp/work"
        )
        let candidate = makeJob(
            id: "job.candidate",
            label: "com.example.alpha.helper",
            program: "/usr/bin/tool",
            standardOutPath: "/tmp/shared.log",
            workingDirectory: "/tmp/work"
        )

        let analysis = LaunchJobRelationAnalyzer().analyze(selectedJob: selected, jobs: [selected, candidate])
        let relation = try XCTUnwrap(analysis.relatedJobs.first)

        XCTAssertTrue(relation.reasons.contains(where: { $0.kind == .sameExecutablePath }))
        XCTAssertTrue(relation.reasons.contains(where: { $0.kind == .sameLabelNamespace }))
        XCTAssertTrue(relation.reasons.contains(where: { $0.kind == .sharedLogFile }))
        XCTAssertTrue(relation.reasons.contains(where: { $0.kind == .sharedWorkingDirectory }))
        XCTAssertGreaterThanOrEqual(relation.reasons.count, 4)
    }

    private func makeJob(
        id: String,
        label: String,
        program: String,
        standardOutPath: String? = nil,
        standardErrorPath: String? = nil,
        workingDirectory: String? = nil,
        domain: LaunchDomain = .userAgent,
        ownerAccountName: String? = "user",
        groupOwnerAccountName: String? = "staff"
    ) -> LaunchServiceJob {
        LaunchServiceJob(
            id: id,
            label: label,
            domain: domain,
            pid: nil,
            state: .loadedIdle,
            exitCode: nil,
            program: program,
            arguments: [],
            runAtLoad: true,
            keepAliveDescription: nil,
            schedule: .none,
            plistPath: "/tmp/\(label).plist",
            environmentVariables: [:],
            machServices: [],
            workingDirectory: workingDirectory,
            standardOutPath: standardOutPath,
            standardErrorPath: standardErrorPath,
            watchPaths: [],
            queueDirectories: [],
            ownerAccountName: ownerAccountName,
            groupOwnerAccountName: groupOwnerAccountName,
            rawKeys: []
        )
    }
}
