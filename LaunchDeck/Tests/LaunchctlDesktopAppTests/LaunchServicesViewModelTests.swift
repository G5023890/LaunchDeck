import XCTest
@testable import LaunchctlDesktopApp

@MainActor
final class LaunchServicesViewModelTests: XCTestCase {
    func testSelectionDoesNotLoadHeavyDetailsUntilRequested() throws {
        let viewModel = makeViewModel()
        let selected = makeJob(
            id: "job.selected",
            label: "com.example.alpha",
            program: "/usr/bin/tool",
            pid: 101
        )
        let candidate = makeJob(
            id: "job.candidate",
            label: "com.example.beta",
            program: "/usr/bin/tool",
            pid: 202
        )
        let processes = [
            makeProcess(pid: 101, commandPath: "/usr/bin/tool", cpu: 2.0, memoryMB: 64),
            makeProcess(pid: 202, commandPath: "/usr/bin/tool", cpu: 4.0, memoryMB: 96)
        ]

        viewModel.jobs = [selected, candidate]
        viewModel.updateRunningProcesses(processes)
        viewModel.selectedJobID = selected.id

        XCTAssertNil(viewModel.relationAnalysis)
        XCTAssertTrue(viewModel.resourceOverlay.isEmpty)
        XCTAssertEqual(viewModel.relationDetailsPhase, .idle)
        XCTAssertEqual(viewModel.resourceDetailsPhase, .idle)
    }

    func testRequestedHeavyDetailsFollowLatestSelectionAfterDebounce() async throws {
        let viewModel = makeViewModel()
        let selected = makeJob(
            id: "job.selected",
            label: "com.example.alpha",
            program: "/usr/bin/tool",
            pid: 101
        )
        let candidate = makeJob(
            id: "job.candidate",
            label: "com.example.beta",
            program: "/usr/bin/tool",
            pid: 202
        )
        let processes = [
            makeProcess(pid: 101, commandPath: "/usr/bin/tool", cpu: 2.0, memoryMB: 64),
            makeProcess(pid: 202, commandPath: "/usr/bin/tool", cpu: 4.0, memoryMB: 96)
        ]

        viewModel.jobs = [selected, candidate]
        viewModel.updateRunningProcesses(processes)
        viewModel.selectedJobID = selected.id
        viewModel.requestRelationDetails()
        viewModel.requestResourceDetails()
        viewModel.selectedJobID = candidate.id

        try await Task.sleep(nanoseconds: 250_000_000)

        XCTAssertEqual(viewModel.selectedJobID, candidate.id)
        XCTAssertEqual(viewModel.relationDetailsPhase, .ready)
        XCTAssertEqual(viewModel.resourceDetailsPhase, .ready)
        XCTAssertEqual(viewModel.relationAnalysis?.selectedJob.id, candidate.id)
        XCTAssertEqual(viewModel.relationAnalysis?.relatedJobs.first?.relatedJob.id, selected.id)
        XCTAssertEqual(viewModel.resourceOverlay.jobID, candidate.id)
        XCTAssertEqual(viewModel.resourceOverlay.snapshot?.pidText, "202")
    }

    private func makeViewModel() -> LaunchServicesViewModel {
        let defaults = UserDefaults(suiteName: "LaunchServicesViewModelTests.\(UUID().uuidString)")!

        let viewModel = LaunchServicesViewModel(
            service: LaunchctlService(commandRunner: NullCommandRunner()),
            stateStore: LaunchDeckStateStore(defaults: defaults),
            plistEditingService: FoundationPlistEditingService(fileAccess: FoundationFileAccessService()),
            validationService: NoOpLaunchdValidationService(),
            applyService: NoOpLaunchdApplyService(),
            backupService: NoOpLaunchdBackupService()
        )

        return viewModel
    }

    private func makeJob(
        id: String,
        label: String,
        program: String,
        pid: Int
    ) -> LaunchServiceJob {
        LaunchServiceJob(
            id: id,
            label: label,
            domain: .userAgent,
            pid: pid,
            state: .running,
            exitCode: nil,
            program: program,
            arguments: [],
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
        memoryMB: Double
    ) -> RunningProcess {
        RunningProcess(
            pid: pid,
            parentPID: 1,
            user: "user",
            processState: "R",
            threadCount: 4,
            uptime: "00:00:10",
            commandPath: commandPath,
            cpu: cpu,
            memoryMB: memoryMB
        )
    }
}

private struct NullCommandRunner: CommandExecuting {
    func run(
        _ launchPath: String,
        _ arguments: [String],
        timeout: TimeInterval
    ) async throws -> CommandResult {
        CommandResult(stdout: "", stderr: "", status: 0)
    }
}

private struct NoOpLaunchdValidationService: LaunchdValidationService {
    func validate(job: EditableLaunchJob) async throws -> LaunchdValidationReport {
        LaunchdValidationReport(issues: [], normalizedPlistText: "")
    }
}

private struct NoOpLaunchdApplyService: LaunchdApplyService {
    func makePlan(
        for job: EditableLaunchJob,
        reloadOption: LaunchdApplyReloadOption
    ) async throws -> ApplyPlan {
        ApplyPlan(
            sourceURL: job.fileURL,
            job: job,
            validationReport: LaunchdValidationReport(issues: [], normalizedPlistText: ""),
            normalizedPlistData: Data(),
            normalizedPlistText: "",
            reloadOption: reloadOption,
            snapshotLabel: job.label
        )
    }

    func apply(_ plan: ApplyPlan) async throws -> ApplyResult {
        ApplyResult(
            plan: plan,
            backupSnapshot: BackupSnapshot(
                id: UUID().uuidString,
                label: plan.snapshotLabel,
                sourceURL: plan.sourceURL,
                backupURL: plan.sourceURL,
                createdAt: Date(),
                fileSizeBytes: 0,
                originalModificationDate: nil
            ),
            appliedURL: plan.sourceURL,
            didBootstrap: false,
            didKickstart: false,
            launchctlOutput: nil,
            summary: "",
            issues: []
        )
    }

    func restore(snapshot: BackupSnapshot, to destinationURL: URL) throws {}
}

private struct NoOpLaunchdBackupService: LaunchdBackupService {
    func createBackup(of sourceURL: URL, label: String) throws -> BackupSnapshot {
        BackupSnapshot(
            id: UUID().uuidString,
            label: label,
            sourceURL: sourceURL,
            backupURL: sourceURL,
            createdAt: Date(),
            fileSizeBytes: 0,
            originalModificationDate: nil
        )
    }

    func listBackups(for sourceURL: URL) throws -> [BackupSnapshot] {
        []
    }

    func restore(_ snapshot: BackupSnapshot, to destinationURL: URL) throws {}
}
