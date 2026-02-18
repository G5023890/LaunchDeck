import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = AppViewModel()

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailView
        }
        .navigationTitle("LaunchDeck")
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    viewModel.refreshCurrentSection()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r", modifiers: [.command])
            }
        }
        .onAppear {
            viewModel.initialLoad()
        }
    }

    private var sidebar: some View {
        List(SidebarSection.allCases, selection: $viewModel.selectedSection) { section in
            Label(section.title, systemImage: section.symbol)
                .tag(section)
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder
    private var detailView: some View {
        switch viewModel.selectedSection {
        case .processes:
            ProcessesView(viewModel: viewModel.processesViewModel)
        case .launchServices:
            LaunchServicesView(viewModel: viewModel.launchServicesViewModel, scope: .launchServices)
        case .userAgents:
            LaunchServicesView(viewModel: viewModel.launchServicesViewModel, scope: .userAgents)
        case .systemAgents:
            LaunchServicesView(viewModel: viewModel.launchServicesViewModel, scope: .systemAgents)
        case .systemDaemons:
            LaunchServicesView(viewModel: viewModel.launchServicesViewModel, scope: .systemDaemons)
        case .schedules:
            SchedulesView(viewModel: viewModel.schedulesViewModel)
        case .diagnostics:
            DiagnosticsView(
                viewModel: viewModel.diagnosticsViewModel,
                processCount: viewModel.processesViewModel.processes.count,
                launchJobCount: viewModel.launchServicesViewModel.jobs.count
            )
        case .none:
            ContentUnavailableView("Select a section", systemImage: "sidebar.left")
        }
    }
}
