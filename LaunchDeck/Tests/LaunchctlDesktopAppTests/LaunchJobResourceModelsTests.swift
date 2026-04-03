import XCTest
@testable import LaunchctlDesktopApp

final class LaunchJobResourceModelsTests: XCTestCase {
    func testResolverUsesDirectPIDWhenAvailable() throws {
        let job = makeJob(
            id: "job.selected",
            label: "com.example.alpha",
            program: "/usr/bin/tool",
            pid: 4242
        )
        let process = makeProcess(pid: 4242, commandPath: "/usr/bin/tool", cpu: 7.5, memoryMB: 96)

        let resolution = LaunchJobProcessResolver().resolve(job: job, runningProcesses: [process])

        XCTAssertEqual(resolution.process?.pid, 4242)
        XCTAssertEqual(resolution.confidence, .exact)
        XCTAssertEqual(resolution.matchedBy, .directPID)
        XCTAssertTrue(resolution.reason.contains("PID"))
    }

    func testResolverMarksAmbiguousExecutableMatchAsUncertain() throws {
        let job = makeJob(
            id: "job.selected",
            label: "com.example.alpha",
            program: "/usr/bin/tool"
        )
        let processA = makeProcess(pid: 100, commandPath: "/usr/bin/tool", cpu: 3.2, memoryMB: 42)
        let processB = makeProcess(pid: 101, commandPath: "/usr/bin/tool", cpu: 1.1, memoryMB: 40)

        let resolution = LaunchJobProcessResolver().resolve(job: job, runningProcesses: [processA, processB])

        XCTAssertEqual(resolution.confidence, .uncertain)
        XCTAssertEqual(resolution.matchedBy, .executablePath)
        XCTAssertEqual(resolution.candidateCount, 2)
        XCTAssertTrue(resolution.reason.contains("Multiple processes"))
    }

    func testOverlayEmptyStateIsExplicit() {
        let overlay = ResourceOverlayViewModel.empty

        XCTAssertTrue(overlay.isEmpty)
        XCTAssertNil(overlay.snapshot)
        XCTAssertNil(overlay.confidenceText)
    }

    func testOverlayRunningStateExposesCurrentMetricsAndTrend() {
        let process = makeProcess(pid: 77, commandPath: "/usr/bin/tool", cpu: 12.5, memoryMB: 256, state: "S")
        let resolution = LaunchJobProcessResolution(
            process: process,
            confidence: .exact,
            matchedBy: .directPID,
            reason: "Matched launchd PID 77 and executable metadata.",
            candidateCount: 1
        )
        let now = Date()
        var timeline = LaunchJobResourceTimeline()
        timeline.append(snapshot: LaunchJobResourceSnapshot(
            timestamp: now.addingTimeInterval(-40),
            jobID: "job.selected",
            label: "com.example.alpha",
            reportedPID: 77,
            resolution: resolution,
            cpu: 10.0,
            memoryMB: 200,
            uptime: "00:00:10",
            processState: "Sleeping",
            executablePath: "/usr/bin/tool",
            childProcessCount: 1,
            openFilesCount: nil
        ))
        timeline.append(snapshot: LaunchJobResourceSnapshot(
            timestamp: now.addingTimeInterval(-10),
            jobID: "job.selected",
            label: "com.example.alpha",
            reportedPID: 77,
            resolution: resolution,
            cpu: 12.5,
            memoryMB: 256,
            uptime: "00:00:20",
            processState: "Sleeping",
            executablePath: "/usr/bin/tool",
            childProcessCount: 1,
            openFilesCount: nil
        ))

        let snapshot = LaunchJobResourceSnapshot(
            timestamp: now,
            jobID: "job.selected",
            label: "com.example.alpha",
            reportedPID: 77,
            resolution: resolution,
            cpu: 12.5,
            memoryMB: 256,
            uptime: "00:00:20",
            processState: "Sleeping",
            executablePath: "/usr/bin/tool",
            childProcessCount: 1,
            openFilesCount: nil
        )

        let overlay = ResourceOverlayViewModel(
            jobID: "job.selected",
            label: "com.example.alpha",
            resolution: resolution,
            snapshot: snapshot,
            timeline: timeline
        )

        XCTAssertFalse(overlay.isEmpty)
        XCTAssertEqual(overlay.snapshot?.pidText, "77")
        XCTAssertEqual(overlay.snapshot?.cpuText, "12.5%")
        XCTAssertEqual(overlay.snapshot?.stateText, "Sleeping")
        XCTAssertEqual(overlay.oneMinuteTrend?.sampleCount, 2)
        XCTAssertEqual(overlay.oneMinuteTrend?.currentCPU, 12.5)
    }

    func testTimelineAggregationComputesAverageAndDelta() {
        var timeline = LaunchJobResourceTimeline()
        let resolution = LaunchJobProcessResolution(
            process: makeProcess(pid: 1, commandPath: "/usr/bin/tool", cpu: 0, memoryMB: 0),
            confidence: .exact,
            matchedBy: .directPID,
            reason: "Matched launchd PID 1 and executable metadata.",
            candidateCount: 1
        )

        timeline.append(snapshot: LaunchJobResourceSnapshot(
            timestamp: Date(timeIntervalSinceReferenceDate: 100),
            jobID: "job.selected",
            label: "com.example.alpha",
            reportedPID: 1,
            resolution: resolution,
            cpu: 2,
            memoryMB: 20,
            uptime: "00:00:10",
            processState: "Running",
            executablePath: "/usr/bin/tool",
            childProcessCount: nil,
            openFilesCount: nil
        ))
        timeline.append(snapshot: LaunchJobResourceSnapshot(
            timestamp: Date(timeIntervalSinceReferenceDate: 110),
            jobID: "job.selected",
            label: "com.example.alpha",
            reportedPID: 1,
            resolution: resolution,
            cpu: 6,
            memoryMB: 40,
            uptime: "00:00:20",
            processState: "Running",
            executablePath: "/usr/bin/tool",
            childProcessCount: nil,
            openFilesCount: nil
        ))

        let trend = timeline.trend(windowSeconds: 60, now: Date(timeIntervalSinceReferenceDate: 120))

        XCTAssertEqual(trend?.sampleCount, 2)
        XCTAssertEqual(trend?.averageCPU ?? -1, 4, accuracy: 0.001)
        XCTAssertEqual(trend?.cpuDelta ?? -1, 4, accuracy: 0.001)
        XCTAssertEqual(trend?.averageMemoryMB ?? -1, 30, accuracy: 0.001)
        XCTAssertEqual(trend?.memoryDelta ?? -1, 20, accuracy: 0.001)
    }

    private func makeJob(
        id: String,
        label: String,
        program: String?,
        pid: Int? = nil
    ) -> LaunchServiceJob {
        LaunchServiceJob(
            id: id,
            label: label,
            domain: .userAgent,
            pid: pid,
            state: pid == nil ? .loadedIdle : .running,
            exitCode: nil,
            program: program,
            arguments: program.map { [$0] } ?? [],
            runAtLoad: true,
            keepAliveDescription: nil,
            schedule: .none,
            plistPath: "/tmp/\(label).plist",
            environmentVariables: [:],
            machServices: [],
            workingDirectory: nil,
            standardOutPath: nil,
            standardErrorPath: nil,
            watchPaths: [],
            queueDirectories: [],
            ownerAccountName: nil,
            groupOwnerAccountName: nil,
            rawKeys: []
        )
    }

    private func makeProcess(
        pid: Int,
        commandPath: String,
        cpu: Double,
        memoryMB: Double,
        state: String? = "R"
    ) -> RunningProcess {
        RunningProcess(
            pid: pid,
            parentPID: 1,
            user: "user",
            processState: state,
            threadCount: 4,
            uptime: "00:00:10",
            commandPath: commandPath,
            cpu: cpu,
            memoryMB: memoryMB
        )
    }
}
