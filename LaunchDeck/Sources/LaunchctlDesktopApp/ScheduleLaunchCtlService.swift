import Foundation

struct LaunchCtlService {
    private let shell = ShellExecutor()

    func loadedLabels() async throws -> Set<String> {
        let result = try await shell.run("/bin/launchctl", ["list"], timeout: 20)
        guard result.status == 0 else {
            let errorText = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw LaunchControlError.commandFailed(errorText.isEmpty ? "launchctl list failed" : errorText)
        }

        let labels = result.stdout
            .split(separator: "\n")
            .dropFirst()
            .compactMap { line -> String? in
                let parts = line
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .split(whereSeparator: { $0.isWhitespace })
                guard parts.count >= 3 else { return nil }
                return String(parts[2])
            }

        return Set(labels)
    }

    func unload(plistURL: URL) async throws {
        let unload = try await shell.run("/bin/launchctl", ["unload", plistURL.path], timeout: 20)
        if unload.status == 0 { return }

        let errorText = unload.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if errorText.localizedCaseInsensitiveContains("No such process") {
            return
        }

        throw LaunchControlError.commandFailed(errorText.isEmpty ? "launchctl unload failed" : errorText)
    }

    func load(plistURL: URL) async throws {
        let load = try await shell.run("/bin/launchctl", ["load", plistURL.path], timeout: 20)
        guard load.status == 0 else {
            let errorText = load.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw LaunchControlError.commandFailed(errorText.isEmpty ? "launchctl load failed" : errorText)
        }
    }

    func reload(plistURL: URL) async throws {
        try await unload(plistURL: plistURL)
        try await load(plistURL: plistURL)
    }
}
