import XCTest
@testable import LaunchctlDesktopApp

final class LaunchdSafeEditTests: XCTestCase {
    func testPlistEditingServiceLoadsEditableJob() throws {
        let tempURL = try makeTemporaryPlistURL()
        defer { try? FileManager.default.removeItem(at: tempURL.deletingLastPathComponent()) }

        let plist: [String: Any] = [
            "Label": "com.example.safeedit",
            "Program": "/usr/bin/say",
            "ProgramArguments": ["/usr/bin/say", "hello"],
            "RunAtLoad": true,
            "StartInterval": 300,
            "WorkingDirectory": "/tmp",
            "EnvironmentVariables": ["FOO": "BAR"]
        ]
        try writePlist(plist, to: tempURL)

        let service = FoundationPlistEditingService(fileAccess: FoundationFileAccessService())
        let job = try service.loadEditableLaunchJob(
            from: tempURL,
            domain: .userAgent,
            isLoaded: false,
            sourceJobID: nil
        )

        XCTAssertEqual(job.label, "com.example.safeedit")
        XCTAssertEqual(job.program, "/usr/bin/say")
        XCTAssertEqual(job.programArguments, ["/usr/bin/say", "hello"])
        XCTAssertTrue(job.runAtLoad)
        XCTAssertEqual(job.startInterval, 300)
        XCTAssertEqual(job.workingDirectory, "/tmp")
        XCTAssertEqual(job.environmentVariables["FOO"], "BAR")
    }

    func testValidationReportsMissingExecutableAndScheduleConflict() async throws {
        let tempURL = try makeTemporaryPlistURL()
        defer { try? FileManager.default.removeItem(at: tempURL.deletingLastPathComponent()) }

        let job = EditableLaunchJob(
            fileURL: tempURL,
            domain: .userAgent,
            label: "com.example.safeedit",
            program: "/does/not/exist",
            programArguments: ["/does/not/exist", "hello"],
            runAtLoad: true,
            keepAlive: .enabled,
            startInterval: 120,
            startCalendarIntervals: [CalendarSpec(weekday: 2, hour: 9, minute: 0)],
            workingDirectory: "/tmp",
            standardOutPath: "/tmp/safeedit.out",
            standardErrorPath: "/tmp/safeedit.err",
            environmentVariables: [:]
        )

        let plistEditingService = FoundationPlistEditingService(fileAccess: FoundationFileAccessService())
        let validationService = DefaultLaunchdValidationService(
            fileAccess: FoundationFileAccessService(),
            launchctlClient: MockLaunchctlClient(preflightStatus: 0),
            plistEditingService: plistEditingService
        )

        let report = try await validationService.validate(job: job)

        XCTAssertFalse(report.canApply)
        XCTAssertTrue(report.errors.contains(where: { $0.title == "Executable missing" }))
        XCTAssertTrue(report.errors.contains(where: { $0.title == "Conflicting schedule settings" }))
    }

    func testBackupServiceCreatesAndRestoresSnapshot() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sourceURL = tempDir.appendingPathComponent("com.example.safeedit.plist")
        let initialPlist: [String: Any] = [
            "Label": "com.example.safeedit",
            "Program": "/usr/bin/say",
            "ProgramArguments": ["/usr/bin/say", "hello"]
        ]
        try writePlist(initialPlist, to: sourceURL)

        let fileAccess = FoundationFileAccessService()
        let backupService = FoundationLaunchdBackupService(fileAccess: fileAccess)

        let snapshot = try backupService.createBackup(of: sourceURL, label: "com.example.safeedit")
        XCTAssertTrue(fileAccess.fileExists(at: snapshot.backupURL))

        let updatedPlist: [String: Any] = [
            "Label": "com.example.safeedit",
            "Program": "/usr/bin/say",
            "ProgramArguments": ["/usr/bin/say", "updated"]
        ]
        try writePlist(updatedPlist, to: sourceURL)

        try backupService.restore(snapshot, to: sourceURL)
        let restoredData = try fileAccess.readData(at: sourceURL)
        let restoredPlist = try PropertyListSerialization.propertyList(from: restoredData, options: [], format: nil) as? [String: Any]
        XCTAssertEqual(restoredPlist?["ProgramArguments"] as? [String], ["/usr/bin/say", "hello"])
    }

    func testApplyPlanGenerationUsesValidationAndNormalizedPreview() async throws {
        let tempURL = try makeTemporaryPlistURL()
        defer { try? FileManager.default.removeItem(at: tempURL.deletingLastPathComponent()) }

        let plist: [String: Any] = [
            "Label": "com.example.safeedit",
            "Program": "/usr/bin/say",
            "ProgramArguments": ["/usr/bin/say", "hello"],
            "RunAtLoad": true
        ]
        try writePlist(plist, to: tempURL)

        let fileAccess = FoundationFileAccessService()
        let plistEditingService = FoundationPlistEditingService(fileAccess: fileAccess)
        let validationService = DefaultLaunchdValidationService(
            fileAccess: fileAccess,
            launchctlClient: MockLaunchctlClient(preflightStatus: 0),
            plistEditingService: plistEditingService
        )
        let backupService = FoundationLaunchdBackupService(fileAccess: fileAccess)
        let applyService = DefaultLaunchdApplyService(
            validationService: validationService,
            backupService: backupService,
            plistEditingService: plistEditingService,
            launchctlClient: MockLaunchctlClient(preflightStatus: 0),
            fileAccess: fileAccess
        )

        let job = try plistEditingService.loadEditableLaunchJob(
            from: tempURL,
            domain: .userAgent,
            isLoaded: false,
            sourceJobID: nil
        )

        let plan = try await applyService.makePlan(for: job, reloadOption: .none)

        XCTAssertEqual(plan.sourceURL, tempURL)
        XCTAssertTrue(plan.validationReport.canApply)
        XCTAssertTrue(plan.normalizedPlistText.contains("com.example.safeedit"))
        XCTAssertEqual(plan.reloadOption, .none)
    }

    private func makeTemporaryPlistURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("sample.plist")
    }

    private func writePlist(_ plist: [String: Any], to url: URL) throws {
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: url)
    }
}

private struct MockLaunchctlClient: LaunchctlClient {
    let preflightStatus: Int32

    func list() async throws -> CommandResult {
        CommandResult(stdout: "", stderr: "", status: 0)
    }

    func bootstrap(domainTarget: String, plistPath: String) async throws -> CommandResult {
        CommandResult(stdout: "", stderr: "", status: 0)
    }

    func bootout(domainTarget: String, serviceTarget: String, plistPath: String?) async throws -> CommandResult {
        CommandResult(stdout: "", stderr: "", status: 0)
    }

    func kickstart(serviceTarget: String, force: Bool) async throws -> CommandResult {
        CommandResult(stdout: "", stderr: "", status: 0)
    }

    func preflightPlist(at plistURL: URL) async throws -> CommandResult {
        CommandResult(stdout: "", stderr: "", status: preflightStatus)
    }
}

