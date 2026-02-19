import AppKit
import SwiftUI

struct LaunchServicesView: View {
    @ObservedObject var viewModel: LaunchServicesViewModel
    let scope: SidebarSection

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if !viewModel.errorMessage.isEmpty {
                statusText(viewModel.errorMessage, color: .red)
            } else if !viewModel.statusMessage.isEmpty {
                statusText(viewModel.statusMessage, color: .secondary)
            }

            HSplitView {
                jobsTable
                inspector
                    .frame(minWidth: 320, idealWidth: 360)
            }
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [Color(nsColor: .windowBackgroundColor), Color(nsColor: .controlBackgroundColor)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var header: some View {
        HStack {
            Label(scope.title, systemImage: scope.symbol)
                .font(.title3.weight(.semibold))

            TextField("Filter label or program", text: $viewModel.filterText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 300)

            Spacer()

            Button {
                viewModel.refresh()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
        }
    }

    private var jobsTable: some View {
        Table(scopedJobs, selection: $viewModel.selectedJobID, sortOrder: $viewModel.sortOrder) {
            TableColumn("Label", value: \LaunchServiceJob.label) { job in
                Text(job.label)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .contextMenu {
                        Button("Copy Label") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(job.label, forType: .string)
                            viewModel.statusMessage = "Copied \(job.label)"
                        }
                        if let program = job.program, !program.isEmpty {
                            Button("Copy Program") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(program, forType: .string)
                                viewModel.statusMessage = "Copied \(program)"
                            }
                        }
                    }
            }
            .width(min: 240, ideal: 320, max: 460)

            TableColumn("Domain") { job in
                Text(job.domain.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .width(min: 110, ideal: 130, max: 160)

            TableColumn("PID") { job in
                Text(job.pidText)
                    .font(.system(.body, design: .monospaced))
            }
            .width(min: 70, ideal: 90, max: 110)

            TableColumn("State") { job in
                HStack(spacing: 6) {
                    Circle()
                        .fill(job.state.color)
                        .frame(width: 8, height: 8)
                    Text(job.state.title)
                        .font(.caption.weight(.semibold))
                }
            }
            .width(min: 90, ideal: 110, max: 130)

            TableColumn("ExitCode") { job in
                Text(job.exitCodeText)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle((job.exitCode ?? 0) == 0 ? Color.secondary : Color.red)
            }
            .width(min: 80, ideal: 100, max: 120)
        }
        .overlay {
            if viewModel.isLoading {
                ProgressView()
                    .controlSize(.large)
            }
        }
    }

    private var inspector: some View {
        ScrollView {
            if let job = selectedScopedJob {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Inspector", systemImage: "sidebar.right")
                        .font(.headline)

                    DisclosureGroup("General") {
                        Form {
                            LabeledContent("Label") {
                                Text(job.label)
                                    .font(.system(.footnote, design: .monospaced))
                                    .lineLimit(2)
                                    .multilineTextAlignment(.trailing)
                            }
                            LabeledContent("Program") {
                                Text(job.program ?? "-")
                                    .lineLimit(2)
                                    .truncationMode(.middle)
                            }
                            LabeledContent("Arguments") {
                                Text(job.arguments.isEmpty ? "-" : job.arguments.joined(separator: " "))
                                    .lineLimit(2)
                                    .truncationMode(.middle)
                            }
                            LabeledContent("RunAtLoad") { Text(boolText(job.runAtLoad)) }
                            LabeledContent("KeepAlive") { Text(job.keepAliveDescription ?? "-") }
                        }
                    }
                    .padding(10)
                    .background(Color(nsColor: .underPageBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    DisclosureGroup("Schedule") {
                        Form {
                            LabeledContent("StartInterval") {
                                Text(startIntervalText(job.schedule))
                                    .font(.system(.body, design: .monospaced))
                            }
                            LabeledContent("StartCalendarInterval") {
                                Text(startCalendarText(job.schedule))
                                    .lineLimit(3)
                                    .multilineTextAlignment(.trailing)
                            }
                        }
                    }
                    .padding(10)
                    .background(Color(nsColor: .underPageBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    DisclosureGroup("Runtime") {
                        Form {
                            LabeledContent("PID") {
                                Text(job.pidText)
                                    .font(.system(.body, design: .monospaced))
                            }
                            LabeledContent("ExitCode") {
                                Text(job.exitCodeText)
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundStyle((job.exitCode ?? 0) == 0 ? Color.secondary : Color.red)
                            }
                        }
                    }
                    .padding(10)
                    .background(Color(nsColor: .underPageBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 8) {
                        Label("Actions", systemImage: "gearshape")
                            .font(.headline)

                        HStack {
                            Button("Load") { viewModel.loadSelected() }
                            Button("Unload") { viewModel.unloadSelected() }
                            Button("Kickstart") { viewModel.kickstartSelected() }
                        }

                        HStack {
                            Button("Edit plist") { viewModel.editSelected() }
                            Button("Reveal") { viewModel.revealSelected() }
                        }
                    }
                }
                .padding(2)
            } else {
                ContentUnavailableView("Select a launch job", systemImage: "cursorarrow.click")
            }
        }
    }

    private var scopedJobs: [LaunchServiceJob] {
        viewModel.filteredJobs(for: scope)
    }

    private var selectedScopedJob: LaunchServiceJob? {
        guard let selected = viewModel.selectedJob else { return nil }
        return scopedJobs.contains(where: { $0.id == selected.id }) ? selected : nil
    }

    private func boolText(_ value: Bool?) -> String {
        guard let value else { return "-" }
        return value ? "true" : "false"
    }

    private func startIntervalText(_ schedule: LaunchSchedule) -> String {
        guard case let .interval(seconds) = schedule else { return "-" }
        return "\(seconds)"
    }

    private func startCalendarText(_ schedule: LaunchSchedule) -> String {
        guard case let .calendar(entries) = schedule, !entries.isEmpty else { return "-" }

        return entries.map { entry in
            let time = String(format: "%02d:%02d", entry.hour, entry.minute)
            if let weekday = entry.weekday {
                return "weekday \(weekday) @ \(time)"
            }
            return "daily @ \(time)"
        }
        .joined(separator: ", ")
    }

    private func statusText(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(color)
    }
}

private extension LaunchJobState {
    var color: Color {
        switch self {
        case .running:
            return .green
        case .loadedIdle:
            return .yellow
        case .crashed:
            return .red
        case .unloaded:
            return .secondary
        }
    }
}
