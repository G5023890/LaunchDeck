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
        let fileAccess = FoundationFileAccessService()
        let commandRunner = ShellExecutor()
        let launchctlClient = DefaultLaunchctlClient(runner: commandRunner)
        let plistEditingService = FoundationPlistEditingService(fileAccess: fileAccess)
        let validationService = DefaultLaunchdValidationService(
            fileAccess: fileAccess,
            launchctlClient: launchctlClient,
            plistEditingService: plistEditingService
        )
        let backupService = FoundationLaunchdBackupService(fileAccess: fileAccess)
        let applyService = DefaultLaunchdApplyService(
            validationService: validationService,
            backupService: backupService,
            plistEditingService: plistEditingService,
            launchctlClient: launchctlClient,
            fileAccess: fileAccess
        )

        let processesVM = ProcessesViewModel(service: service, stateStore: stateStore)
        let launchServicesVM = LaunchServicesViewModel(
            service: service,
            stateStore: stateStore,
            plistEditingService: plistEditingService,
            validationService: validationService,
            applyService: applyService,
            backupService: backupService
        )
        processesVM.onProcessesUpdated = { [weak launchServicesVM] processes in
            launchServicesVM?.updateRunningProcesses(processes)
        }
        processesViewModel = processesVM
        launchServicesViewModel = launchServicesVM
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
