import AppKit
import Foundation
import SwiftUI

@MainActor
final class AppViewModel: ObservableObject {
    @Published var selectedSection: SidebarSection? {
        didSet {
            if let selectedSection {
                stateStore.selectedSection = selectedSection
            }
        }
    }

    let processesViewModel: ProcessesViewModel
    let launchServicesViewModel: LaunchServicesViewModel
    let schedulesViewModel: SchedulesViewModel
    let diagnosticsViewModel: DiagnosticsViewModel
    private let stateStore: LaunchDeckStateStore

    init(service: LaunchctlService = LaunchctlService(), stateStore: LaunchDeckStateStore = .shared) {
        self.stateStore = stateStore
        selectedSection = stateStore.selectedSection
        processesViewModel = ProcessesViewModel(service: service, stateStore: stateStore)
        launchServicesViewModel = LaunchServicesViewModel(service: service, stateStore: stateStore)
        schedulesViewModel = SchedulesViewModel(service: service, stateStore: stateStore)
        diagnosticsViewModel = DiagnosticsViewModel(service: service)
    }

    func refreshCurrentSection() {
        guard let selectedSection else { return }

        switch selectedSection {
        case .processes:
            processesViewModel.refresh()
        case .launchServices, .userAgents, .systemAgents, .systemDaemons:
            launchServicesViewModel.refresh()
        case .schedules:
            schedulesViewModel.refresh()
        case .diagnostics:
            diagnosticsViewModel.captureSnapshot(
                processCount: processesViewModel.processes.count,
                launchJobCount: launchServicesViewModel.jobs.count
            )
        }
    }

    func initialLoad() {
        processesViewModel.refresh()
        launchServicesViewModel.refresh()
        schedulesViewModel.refresh()
    }
}
