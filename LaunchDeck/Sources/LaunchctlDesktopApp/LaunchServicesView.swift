import AppKit
import SwiftUI

struct LaunchServicesView: View {
    @ObservedObject var viewModel: LaunchServicesViewModel
    let scope: SidebarSection

    @State private var isAdvancedExpanded = false

    var body: some View {
        HSplitView {
            listColumn
                .frame(minWidth: 440, idealWidth: 560, maxWidth: 680)
            inspectorColumn
                .frame(minWidth: 460, idealWidth: 620, maxWidth: .infinity)
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
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var listColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
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
                                            Button("Unload") { viewModel.unload(job: job) }
                                                .disabled(job.plistPath == nil)
                                        } else {
                                            Button("Load") { viewModel.load(job: job) }
                                                .disabled(job.plistPath == nil)
                                        }
                                        Button("Kickstart") { viewModel.kickstart(job: job) }
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
                        description: Text("Adjust filters or refresh the launchctl scan.")
                    )
                }
            }
            .listStyle(.inset)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(.regularMaterial))
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
            .background(RoundedRectangle(cornerRadius: 14).fill(.regularMaterial))
        } else {
            ContentUnavailableView(
                "Select a launch service",
                systemImage: "sidebar.right",
                description: Text("Inspector shows contextual information and actions.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 14).fill(.regularMaterial))
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

                    Button("Unload") { viewModel.unloadSelected() }
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

                    Button("Kickstart") { viewModel.kickstartSelected() }
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
        .background(RoundedRectangle(cornerRadius: 14).fill(.regularMaterial))
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
        return "No schedule metadata in plist"
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
            .background(Capsule().fill(color.opacity(0.16)))
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
