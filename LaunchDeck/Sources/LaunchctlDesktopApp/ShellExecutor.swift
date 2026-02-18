import Foundation

actor ShellExecutor {
    func run(
        _ launchPath: String,
        _ arguments: [String],
        timeout: TimeInterval = 10
    ) async throws -> CommandResult {
        try await Task.detached(priority: .userInitiated) {
            try Self.runBlocking(launchPath, arguments, timeout: timeout)
        }.value
    }

    private static func runBlocking(
        _ launchPath: String,
        _ arguments: [String],
        timeout: TimeInterval
    ) throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        let outBuffer = LockedBuffer()
        let errBuffer = LockedBuffer()
        outPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if !chunk.isEmpty {
                outBuffer.append(chunk)
            }
        }
        errPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if !chunk.isEmpty {
                errBuffer.append(chunk)
            }
        }

        try process.run()

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning, Date() < deadline {
            usleep(50_000)
        }

        if process.isRunning {
            process.terminate()
            throw LaunchControlError.commandFailed(
                "Command timeout: \(launchPath) \(arguments.joined(separator: " "))"
            )
        }

        process.waitUntilExit()
        outPipe.fileHandleForReading.readabilityHandler = nil
        errPipe.fileHandleForReading.readabilityHandler = nil
        outBuffer.append(outPipe.fileHandleForReading.readDataToEndOfFile())
        errBuffer.append(errPipe.fileHandleForReading.readDataToEndOfFile())

        let stdout = String(data: outBuffer.data, encoding: .utf8) ?? ""
        let stderr = String(data: errBuffer.data, encoding: .utf8) ?? ""

        return CommandResult(stdout: stdout, stderr: stderr, status: process.terminationStatus)
    }
}

private final class LockedBuffer: @unchecked Sendable {
    private var storage = Data()
    private let lock = NSLock()

    var data: Data {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        lock.lock()
        storage.append(chunk)
        lock.unlock()
    }
}
