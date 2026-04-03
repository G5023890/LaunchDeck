import XCTest
@testable import LaunchctlDesktopApp

final class LaunchJobHealthEvaluatorTests: XCTestCase {
    private let evaluator = LaunchJobHealthEvaluator()

    func testHealthyKnownGoodJobProducesHealthyReport() {
        let job = makeJob(
            label: "com.example.healthy",
            program: "/usr/bin/say",
            state: .running,
            pid: 501
        )
        let diagnostics = LaunchJobRuntimeDiagnostics(
            launchdLoaded: true,
            plistIsReadable: true,
            executableExists: true,
            executableIsExecutable: true
        )

        let report = evaluator.evaluate(job: job, runtimeDiagnostics: diagnostics)

        XCTAssertEqual(report.status, LaunchJobHealthStatus.healthy)
        XCTAssertEqual(report.score, 100)
        XCTAssertTrue(report.orderedFactors.isEmpty)
        XCTAssertTrue(report.summary.contains("Healthy"))
    }

    func testMissingBinaryProducesBrokenReport() {
        let job = makeJob(
            label: "com.example.missingbinary",
            program: "/usr/local/bin/missing-tool",
            state: .loadedIdle
        )
        let diagnostics = LaunchJobRuntimeDiagnostics(
            plistIsReadable: true,
            executableExists: false,
            executableIsExecutable: false
        )

        let report = evaluator.evaluate(job: job, runtimeDiagnostics: diagnostics)

        XCTAssertEqual(report.status, .broken)
        XCTAssertTrue(report.orderedFactors.contains(where: { $0.kind == .missingExecutable }))
        XCTAssertTrue(report.summary.contains("Broken"))
        XCTAssertTrue(report.primaryExplanation?.contains("cannot be found") == true)
    }

    func testNonZeroExitCodeProducesBrokenReport() {
        let job = makeJob(
            label: "com.example.exitcode",
            program: "/usr/bin/say",
            state: .crashed,
            exitCode: 42
        )
        let report = evaluator.evaluate(job: job)

        XCTAssertEqual(report.status, .broken)
        XCTAssertTrue(report.orderedFactors.contains(where: { $0.kind == .nonZeroExitCode }))
        XCTAssertTrue(report.summary.contains("Broken"))
        XCTAssertTrue(report.primaryExplanation?.contains("42") == true)
    }

    func testAggressiveIntervalProducesWarningReport() {
        let job = makeJob(
            label: "com.example.fast",
            program: "/usr/bin/say",
            schedule: .interval(seconds: 15),
            state: .loadedIdle
        )

        let report = evaluator.evaluate(job: job)

        XCTAssertEqual(report.status, .warning)
        XCTAssertTrue(report.orderedFactors.contains(where: { $0.kind == .aggressiveInterval }))
        XCTAssertTrue(report.summary.contains("Attention recommended"))
    }

    func testSuspiciousPathProducesSuspiciousReport() {
        let job = makeJob(
            label: "com.example.suspicious",
            program: "/Users/grigorymordokhovich/Downloads/updater",
            state: .loadedIdle,
            standardOutPath: "/Users/grigorymordokhovich/Downloads/job.log"
        )

        let report = evaluator.evaluate(job: job)

        XCTAssertEqual(report.status, LaunchJobHealthStatus.suspicious)
        XCTAssertTrue(report.orderedFactors.contains(where: { $0.kind == LaunchJobRiskFactorKind.suspiciousBinaryLocation }))
        XCTAssertTrue(report.orderedFactors.contains(where: { $0.kind == LaunchJobRiskFactorKind.suspiciousLogPath }))
    }

    func testOrphanedJobProducesOrphanedReport() {
        let job = makeJob(
            label: "com.example.orphaned",
            program: "/usr/bin/say",
            plistPath: "/Library/LaunchDaemons/com.example.orphaned.plist",
            state: .loadedIdle
        )
        let diagnostics = LaunchJobRuntimeDiagnostics(
            runtimeTargetMissing: true,
            plistIsReadable: true,
            executableExists: true,
            executableIsExecutable: true
        )

        let report = evaluator.evaluate(job: job, runtimeDiagnostics: diagnostics)

        XCTAssertEqual(report.status, LaunchJobHealthStatus.orphaned)
        XCTAssertTrue(report.orderedFactors.contains(where: { $0.kind == LaunchJobRiskFactorKind.orphanedTarget }))
        XCTAssertTrue(report.summary.contains("Orphaned"))
        XCTAssertTrue(report.remediationHint?.contains("repair") == true || report.remediationHint?.contains("recreate") == true)
    }

    private func makeJob(
        label: String,
        program: String?,
        schedule: LaunchSchedule = .none,
        plistPath: String? = "/Library/LaunchDaemons/com.example.agent.plist",
        state: LaunchJobState,
        pid: Int? = nil,
        exitCode: Int? = nil,
        standardOutPath: String? = nil,
        standardErrorPath: String? = nil
    ) -> LaunchServiceJob {
        LaunchServiceJob(
            id: label,
            label: label,
            domain: .systemDaemon,
            pid: pid,
            state: state,
            exitCode: exitCode,
            program: program,
            arguments: program.map { [$0, "--flag"] } ?? [],
            runAtLoad: true,
            keepAliveDescription: nil,
            schedule: schedule,
            plistPath: plistPath,
            environmentVariables: [:],
            machServices: [],
            workingDirectory: nil,
            standardOutPath: standardOutPath,
            standardErrorPath: standardErrorPath,
            watchPaths: [],
            queueDirectories: [],
            ownerAccountName: nil,
            groupOwnerAccountName: nil,
            rawKeys: []
        )
    }
}
