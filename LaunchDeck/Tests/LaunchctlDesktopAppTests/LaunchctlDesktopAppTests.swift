import XCTest
@testable import LaunchctlDesktopApp

final class LaunchctlDesktopAppTests: XCTestCase {
    func testSplitShellArgumentsHandlesQuotesAndEscapes() {
        let input = #"one "two words" 'three four' five\ six"#

        let output = splitShellArguments(input)

        XCTAssertEqual(output, ["one", "two words", "three four", "five six"])
    }

    func testLaunchAgentParserReadsIntervalSchedule() throws {
        let tempURL = try makeTemporaryPlistURL()
        defer { try? FileManager.default.removeItem(at: tempURL.deletingLastPathComponent()) }

        let plist: [String: Any] = [
            "Label": "com.example.interval",
            "ProgramArguments": ["/usr/bin/say", "Hello"],
            "RunAtLoad": true,
            "StartInterval": 120
        ]
        try writePlist(plist, to: tempURL)

        let parser = LaunchAgentParser()
        let parsed = try XCTUnwrap(parser.parseAgent(at: tempURL))

        XCTAssertEqual(parsed.label, "com.example.interval")
        XCTAssertEqual(parsed.program, "/usr/bin/say")
        XCTAssertEqual(parsed.arguments, ["Hello"])
        XCTAssertTrue(parsed.runAtLoad)

        switch parsed.schedule {
        case .interval(let seconds):
            XCTAssertEqual(seconds, 120)
        default:
            XCTFail("Expected interval schedule")
        }
    }

    func testLaunchAgentWriterUpdatesProgramArgumentsAndSchedule() throws {
        let tempURL = try makeTemporaryPlistURL()
        defer { try? FileManager.default.removeItem(at: tempURL.deletingLastPathComponent()) }

        let plist: [String: Any] = [
            "Label": "com.example.agent",
            "Program": "/usr/bin/say",
            "ProgramArguments": ["/usr/bin/say", "old"],
            "RunAtLoad": false,
            "StartInterval": 60
        ]
        try writePlist(plist, to: tempURL)

        var draft = ScheduleDraft()
        draft.label = "com.example.agent"
        draft.commandPath = "/bin/echo"
        draft.arguments = #"hello "launch deck""#
        draft.runAtLoad = true
        draft.mode = .calendar
        draft.hour = 9
        draft.minute = 45
        draft.weekdays = [2, 3]

        let writer = LaunchAgentWriter()
        let parser = LaunchAgentParser()

        try writer.rewriteScheduleAndRunAtLoad(fileURL: tempURL, draft: draft, parser: parser)

        let updated = try parser.readPlistDictionary(at: tempURL)
        XCTAssertEqual(updated["Label"] as? String, "com.example.agent")
        XCTAssertEqual(updated["Program"] as? String, "/bin/echo")
        XCTAssertEqual(updated["ProgramArguments"] as? [String], ["/bin/echo", "hello", "launch deck"])
        XCTAssertEqual(updated["RunAtLoad"] as? Bool, true)

        let schedule = updated["StartCalendarInterval"]
        if let array = schedule as? [[String: Any]] {
            XCTAssertEqual(array.count, 2)
        } else {
            XCTFail("Expected calendar schedule array")
        }
        XCTAssertNil(updated["StartInterval"])
    }

    func testLaunchctlFriendlyCommandFailureAddsHelpfulContext() {
        let permission = launchctlFriendlyCommandFailure(
            action: "load com.example.agent",
            stderr: "Operation not permitted",
            hint: "System jobs often need administrator privileges."
        )

        XCTAssertTrue(permission.contains("macOS denied permission"))
        XCTAssertTrue(permission.contains("administrator privileges"))

        let stale = launchctlFriendlyCommandFailure(
            action: "unload com.example.agent",
            stderr: "Could not find service \"com.example.agent\" in domain",
            hint: "Refresh the list and try again."
        )

        XCTAssertTrue(stale.contains("not available"))
        XCTAssertTrue(stale.contains("Refresh the list"))

        let empty = launchctlFriendlyCommandFailure(
            action: "kickstart com.example.agent",
            stderr: "",
            hint: "Load the job first."
        )

        XCTAssertTrue(empty.contains("LaunchDeck could not kickstart com.example.agent"))
        XCTAssertTrue(empty.contains("Load the job first"))
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
