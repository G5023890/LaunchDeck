import Foundation
import SwiftUI

@MainActor
final class DiagnosticsViewModel: ObservableObject {
    @Published var consoleText = ""
    @Published var isLoading = false
    @Published var statusMessage = ""
    @Published var errorMessage = ""

    private let service: LaunchctlService

    init(service: LaunchctlService) {
        self.service = service
    }

    func captureSnapshot(processCount: Int, launchJobCount: Int) {
        Task {
            isLoading = true
            errorMessage = ""

            let header = [
                "Dashboard signals",
                "Processes: \(processCount)",
                "Launch jobs: \(launchJobCount)",
                ""
            ].joined(separator: "\n")

            let text = await service.diagnosticsSnapshot()
            consoleText = header + text
            statusMessage = "Diagnostics snapshot captured"
            isLoading = false
        }
    }
}
