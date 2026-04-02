import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = AppViewModel()

    var body: some View {
        ZStack {
            background

            NavigationSplitView {
                sidebar
                    .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 280)
            } detail: {
                detailView
            }
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

    private var background: some View {
        LinearGradient(
            colors: [
                Color(nsColor: .windowBackgroundColor),
                Color(nsColor: .underPageBackgroundColor),
                Color(nsColor: .controlBackgroundColor)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(alignment: .topLeading) {
            Circle()
                .fill(Color.accentColor.opacity(0.12))
                .frame(width: 220, height: 220)
                .blur(radius: 60)
                .offset(x: -60, y: -80)
        }
        .overlay(alignment: .bottomTrailing) {
            Circle()
                .fill(Color.blue.opacity(0.10))
                .frame(width: 260, height: 260)
                .blur(radius: 70)
                .offset(x: 80, y: 100)
        }
        .ignoresSafeArea()
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
