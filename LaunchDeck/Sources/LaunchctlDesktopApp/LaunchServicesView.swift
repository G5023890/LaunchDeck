import AppKit
import SwiftUI

struct LaunchServicesView: View {
    @ObservedObject var viewModel: LaunchServicesViewModel
    let scope: SidebarSection

    @State private var isAdvancedExpanded = false
    @State private var pendingJobAction: PendingJobAction?

    var body: some View {
        HSplitView {
            listColumn
                .frame(minWidth: 540, idealWidth: 700, maxWidth: .infinity)
            inspectorColumn
                .frame(minWidth: 360, idealWidth: 420, maxWidth: 520)
        }
        .searchable(text: $viewModel.filterText, placement: .toolbar, prompt: "Filter label or program")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Picker("Filter", selection: $viewModel.statusFilter) {
                    ForEach(LaunchServicesStatusFilter.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 380)
            }

            ToolbarItem(placement: .automatic) {
                Menu {
                    Picker("Sort by", selection: $viewModel.sortOption) {
                        ForEach(LaunchServicesSortOption.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    viewModel.refresh()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
        }
        .padding(16)
        .background(backgroundLayer)
        .confirmationDialog(
            pendingJobAction?.title ?? "Confirm",
            isPresented: Binding(
                get: { pendingJobAction != nil },
                set: { if !$0 { pendingJobAction = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let pendingJobAction {
                Button(pendingJobAction.confirmTitle, role: .destructive) {
                    pendingJobAction.perform(on: viewModel)
                    self.pendingJobAction = nil
                }
                Button("Cancel", role: .cancel) {
                    self.pendingJobAction = nil
                }
            }
        } message: {
            Text(pendingJobAction?.message ?? "")
        }
    }

    private var listColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(scope.title, systemImage: scope.symbol)
                    .font(.title3.weight(.semibold))

                Spacer()

                Text("\(viewModel.groupedJobs(for: scope).reduce(0) { $0 + $1.jobs.count })")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.accentColor.opacity(0.14)))
                    .foregroundStyle(Color.accentColor)
            }

            if !viewModel.errorMessage.isEmpty {
                Text(viewModel.errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            } else if !viewModel.statusMessage.isEmpty {
                Text(viewModel.statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            List(selection: $viewModel.selectedJobID) {
                ForEach(viewModel.groupedJobs(for: scope), id: \.group) { section in
                    Section {
                        if viewModel.isGroupExpanded(section.group) {
                            ForEach(section.jobs) { job in
                                LaunchServiceRow(job: job)
                                    .tag(job.id)
                                    .contextMenu {
                                        if job.isLoaded {
                                            Button("Unload") { pendingJobAction = .unload(job) }
                                                .disabled(job.plistPath == nil)
                                        } else {
                                            Button("Load") { viewModel.load(job: job) }
                                                .disabled(job.plistPath == nil)
                                        }
                                        Button("Kickstart") { pendingJobAction = .kickstart(job) }
                                            .disabled(!job.isLoaded)
                                        Divider()
                                        Button("Reveal in Finder") { viewModel.reveal(job: job) }
                                        Button("Copy Label") { viewModel.copyLabel(job.label) }
                                        Button("Edit plist") { viewModel.edit(job: job) }
                                            .disabled(job.plistPath == nil)
                                    }
                            }
                        }
                    } header: {
                        Button {
                            viewModel.toggleGroup(section.group)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: viewModel.isGroupExpanded(section.group) ? "chevron.down" : "chevron.right")
                                    .font(.caption.weight(.semibold))
                                Label(section.group.title, systemImage: section.group.symbol)
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text("\(section.jobs.count)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .overlay {
                if viewModel.isLoading {
                    ProgressView().controlSize(.large)
                } else if viewModel.groupedJobs(for: scope).isEmpty {
                    ContentUnavailableView(
                        "No launch services",
                        systemImage: "shippingbox",
                        description: Text("Adjust filters or refresh the scan for this domain.")
                    )
                }
            }
            .listStyle(.inset)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.thinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var inspectorColumn: some View {
        if let job = viewModel.selectedJob {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    overviewCard(job)
                    if job.hasSchedule {
                        scheduleCard(job)
                    }
                    detailsCard(job)
                    actionsCard(job)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.thinMaterial)
            )
        } else {
            ContentUnavailableView(
                "Select a launch service",
                systemImage: "sidebar.right",
                description: Text("Inspector shows details and actions for the selected job.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
            )
        }
    }

    private func overviewCard(_ job: LaunchServiceJob) -> some View {
        inspectorCard(title: "Overview", symbol: "info.circle") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    serviceIcon(for: job)
                        .frame(width: 32, height: 32)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(job.label)
                            .font(.title3.weight(.semibold))
                            .lineLimit(2)
                            .truncationMode(.middle)

                        HStack(spacing: 8) {
                            badge(job.domainBadgeTitle, color: .blue)
                            badge(job.statusBadgeTitle, color: statusColor(job.state))
                        }
                    }
                }

                Divider()

                LabeledContent("State") {
                    Text(job.secondaryStatusText)
                        .monospacedDigit()
                }

                LabeledContent("Program") {
                    Text(job.program ?? "-")
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }

                Text(summary(for: job))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func scheduleCard(_ job: LaunchServiceJob) -> some View {
        inspectorCard(title: "Schedule", symbol: "calendar.badge.clock") {
            VStack(alignment: .leading, spacing: 8) {
                LabeledContent("Mode") {
                    Text(job.schedule.modeTitle)
                }

                LabeledContent("Description") {
                    Text(viewModel.scheduleSummary(for: job))
                }

                LabeledContent("Next run") {
                    Text(nextRunText(viewModel.scheduleNextRun(for: job)))
                        .monospacedDigit()
                }
            }
        }
    }

    private func detailsCard(_ job: LaunchServiceJob) -> some View {
        inspectorCard(title: "Details", symbol: "list.bullet.rectangle") {
            DisclosureGroup("Advanced Details", isExpanded: $isAdvancedExpanded) {
                VStack(alignment: .leading, spacing: 10) {
                    detailBlock("ProgramArguments", value: job.arguments.isEmpty ? "-" : job.arguments.joined(separator: " "))
                    detailBlock("EnvironmentVariables", value: envText(job.environmentVariables))
                    detailBlock("MachServices", value: job.machServices.isEmpty ? "-" : job.machServices.joined(separator: ", "))
                    detailBlock("plist path", value: job.plistPath ?? "-")
                    detailBlock("Raw keys", value: job.rawKeys.isEmpty ? "-" : job.rawKeys.joined(separator: ", "))
                }
                .padding(.top, 8)
            }
        }
    }

    private func actionsCard(_ job: LaunchServiceJob) -> some View {
        inspectorCard(title: "Actions", symbol: "gearshape") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Button("Load") { viewModel.loadSelected() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!viewModel.canLoadSelected)

                    Button("Unload") {
                        if let job = viewModel.selectedJob {
                            pendingJobAction = .unload(job)
                        }
                    }
                        .buttonStyle(.borderedProminent)
                        .disabled(!viewModel.canUnloadSelected)
                }

                HStack(spacing: 10) {
                    Button("Reveal in Finder") { viewModel.revealSelected() }
                        .buttonStyle(.bordered)
                        .disabled(!viewModel.canRevealSelected)

                    Button("Copy Label") { viewModel.copyLabel(job.label) }
                        .buttonStyle(.bordered)

                    Button("Edit plist") { viewModel.editSelected() }
                        .buttonStyle(.bordered)
                        .disabled(!viewModel.canEditSelected)

                    Button("Kickstart") {
                        if let job = viewModel.selectedJob {
                            pendingJobAction = .kickstart(job)
                        }
                    }
                        .buttonStyle(.bordered)
                        .disabled(!viewModel.canKickstartSelected)
                }
            }
        }
    }

    private func inspectorCard<Content: View>(title: String, symbol: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbol)
                .font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.thinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 4)
    }

    private func detailBlock(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.footnote, design: .monospaced))
                .lineLimit(3)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func envText(_ value: [String: String]) -> String {
        guard !value.isEmpty else { return "-" }
        return value
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ", ")
    }

    private func summary(for job: LaunchServiceJob) -> String {
        if job.hasSchedule {
            return "Scheduled: \(viewModel.scheduleSummary(for: job))"
        }
        return "No schedule metadata available"
    }

    private func statusColor(_ state: LaunchJobState) -> Color {
        switch state {
        case .running:
            return .green
        case .loadedIdle:
            return .yellow
        case .crashed:
            return .orange
        case .unloaded:
            return .gray
        }
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(color.opacity(0.20)))
            .overlay(
                Capsule().strokeBorder(color.opacity(0.25), lineWidth: 1)
            )
            .foregroundStyle(color)
    }

    private func nextRunText(_ value: Date?) -> String {
        guard let value else { return "-" }
        let calendar = Calendar.current
        if calendar.isDateInToday(value) {
            return "Today at \(value.formatted(date: .omitted, time: .shortened))"
        }
        if calendar.isDateInTomorrow(value) {
            return "Tomorrow at \(value.formatted(date: .omitted, time: .shortened))"
        }
        return value.formatted(date: .abbreviated, time: .shortened)
    }

    private func serviceIcon(for job: LaunchServiceJob) -> Image {
        if let path = job.program, path.hasPrefix("/"), FileManager.default.fileExists(atPath: path) {
            return Image(nsImage: NSWorkspace.shared.icon(forFile: path))
        }
        return Image(systemName: "shippingbox")
    }

    private var backgroundLayer: some View {
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
                .frame(width: 260, height: 260)
                .blur(radius: 68)
                .offset(x: -90, y: -90)
        }
        .overlay(alignment: .bottomTrailing) {
            Circle()
                .fill(Color.blue.opacity(0.10))
                .frame(width: 300, height: 300)
                .blur(radius: 80)
                .offset(x: 120, y: 120)
        }
        .ignoresSafeArea()
    }
}

private enum PendingJobAction {
    case unload(LaunchServiceJob)
    case kickstart(LaunchServiceJob)

    var title: String {
        switch self {
        case .unload(let job):
            return "Unload \(job.label)?"
        case .kickstart(let job):
            return "Kickstart \(job.label)?"
        }
    }

    var confirmTitle: String {
        switch self {
        case .unload:
            return "Unload"
        case .kickstart:
            return "Kickstart"
        }
    }

    var message: String {
        switch self {
        case .unload(let job):
            return "Stop the launch service \(job.label) now? This will boot it out of its current domain."
        case .kickstart(let job):
            return "Restart \(job.label) now? The job is already loaded and will be started again."
        }
    }

    @MainActor
    func perform(on viewModel: LaunchServicesViewModel) {
        switch self {
        case .unload(let job):
            viewModel.unload(job: job)
        case .kickstart(let job):
            viewModel.kickstart(job: job)
        }
    }
}

private struct LaunchServiceRow: View {
    let job: LaunchServiceJob

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            rowIcon
                .frame(width: 26, height: 26)

            VStack(alignment: .leading, spacing: 4) {
                Text(job.label)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: 6) {
                    rowBadge(job.domainBadgeTitle, color: .blue)
                    rowBadge(job.statusBadgeTitle, color: statusColor)
                }

                Text(job.secondaryStatusText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Spacer(minLength: 4)
        }
        .padding(.vertical, 4)
    }

    private var rowIcon: Image {
        if let path = job.program, path.hasPrefix("/"), FileManager.default.fileExists(atPath: path) {
            return Image(nsImage: NSWorkspace.shared.icon(forFile: path))
        }
        return Image(systemName: "square.stack.3d.up")
    }

    private var statusColor: Color {
        switch job.state {
        case .running:
            return .green
        case .loadedIdle:
            return .yellow
        case .crashed:
            return .orange
        case .unloaded:
            return .gray
        }
    }

    private func rowBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.16)))
            .foregroundStyle(color)
    }

}
