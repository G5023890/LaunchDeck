import AppKit
import SwiftUI

struct SchedulesView: View {
    @ObservedObject var viewModel: SchedulesViewModel
    @State private var isArgumentsExpanded = false

    var body: some View {
        HSplitView {
            centerColumn
                .frame(minWidth: 420, idealWidth: 520, maxWidth: 620)
            inspectorColumn
                .frame(minWidth: 480, idealWidth: 640, maxWidth: .infinity)
        }
        .searchable(text: $viewModel.searchText, placement: .toolbar, prompt: "Search scheduled agents")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Picker("Filter", selection: $viewModel.filter) {
                    ForEach(SchedulesFilter.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 240)
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

    private var centerColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !viewModel.errorMessage.isEmpty {
                Text(viewModel.errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            } else if !viewModel.statusMessage.isEmpty {
                Text(viewModel.statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            List(viewModel.filteredAgents, selection: $viewModel.selectedScheduledAgentID) { agent in
                ScheduledAgentRow(
                    agent: agent,
                    nextRunText: viewModel.nextRunRelativeText(agent.nextRun)
                )
                .tag(agent.id)
                .contextMenu {
                    Button("Copy Label") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(agent.label, forType: .string)
                        viewModel.statusMessage = "Copied \(agent.label)"
                    }
                    Button("Reveal plist") {
                        NSWorkspace.shared.activateFileViewerSelecting([agent.fileURL])
                    }
                }
            }
            .overlay {
                if viewModel.isLoading {
                    ProgressView().controlSize(.large)
                } else if viewModel.filteredAgents.isEmpty {
                    ContentUnavailableView(
                        "No scheduled agents",
                        systemImage: "calendar.badge.exclamationmark",
                        description: Text("Only LaunchAgents with StartInterval or StartCalendarInterval appear here.")
                    )
                }
            }
            .listStyle(.inset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(.regularMaterial))
    }

    @ViewBuilder
    private var inspectorColumn: some View {
        if let agent = viewModel.selectedAgent {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    commandSection(agent)
                    scheduleSection
                    executionPreviewSection
                    actionBar
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 14).fill(.regularMaterial))
        } else {
            ContentUnavailableView(
                "Select a scheduled agent",
                systemImage: "sidebar.right",
                description: Text("Inspector appears here for editing interval/calendar schedule.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 14).fill(.regularMaterial))
        }
    }

    private func commandSection(_ agent: ScheduledAgent) -> some View {
        inspectorCard(title: "Command", symbol: "terminal") {
            Form {
                HStack(spacing: 10) {
                    agentIcon(for: agent)
                        .frame(width: 28, height: 28)
                    TextField("Label", text: $viewModel.draft.label)
                        .textFieldStyle(.roundedBorder)
                }

                LabeledContent("Command path") {
                    Text(viewModel.draft.commandPath)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }

                DisclosureGroup("Arguments", isExpanded: $isArgumentsExpanded) {
                    Text(viewModel.draft.arguments.isEmpty ? "No arguments" : viewModel.draft.arguments)
                        .font(.system(.footnote, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                }

                Toggle("Run at Login", isOn: $viewModel.draft.runAtLoad)
            }
            .formStyle(.grouped)
        }
    }

    private var scheduleSection: some View {
        inspectorCard(title: "Schedule", symbol: "calendar.badge.clock") {
            VStack(alignment: .leading, spacing: 14) {
                Picker("Mode", selection: modeBinding) {
                    Text("Calendar").tag(ScheduleBuilderMode.calendar)
                    Text("Interval").tag(ScheduleBuilderMode.interval)
                }
                .pickerStyle(.segmented)

                if viewModel.draft.mode == .interval {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Repeat every")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 8) {
                            TextField(
                                "Value",
                                value: $viewModel.intervalValue,
                                format: .number
                            )
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 72)

                            Picker("Unit", selection: $viewModel.intervalUnit) {
                                ForEach(IntervalUnit.allCases) { unit in
                                    Text(unit.title).tag(unit)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 120)
                        }

                        Text("Equivalent to \(viewModel.intervalEquivalentText)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Time")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        DatePicker(
                            "",
                            selection: $viewModel.calendarTime,
                            displayedComponents: [.hourAndMinute]
                        )
                        .labelsHidden()
                        .datePickerStyle(.field)

                        Text("Weekdays")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        weekdayCapsules
                    }
                }
            }
        }
    }

    private var executionPreviewSection: some View {
        inspectorCard(title: "Execution Preview", symbol: "play.rectangle") {
            VStack(alignment: .leading, spacing: 8) {
                LabeledContent("Next run") {
                    Text(viewModel.nextRunRelativeText(viewModel.previewNextRun))
                        .monospacedDigit()
                }
                LabeledContent("Repeats") {
                    Text(viewModel.schedulePreview)
                }
                LabeledContent("Run at login") {
                    Text(viewModel.draft.runAtLoad ? "Yes" : "No")
                }
            }
        }
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            Button("Cancel") {
                viewModel.cancelChanges()
            }
            .disabled(!viewModel.hasPendingChanges)

            Spacer(minLength: 4)

            Text(viewModel.showReloadHint ? "Applying changes will reload the agent." : " ")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .trailing)

            Button("Apply Changes") {
                viewModel.applyChanges()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.canApplyChanges)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.regularMaterial)
        )
    }

    private var weekdayCapsules: some View {
        HStack(spacing: 8) {
            ForEach(weekdays, id: \.value) { day in
                let isActive = viewModel.draft.weekdays.contains(day.value)
                Button {
                    withAnimation(.easeInOut(duration: 0.12)) {
                        viewModel.toggleWeekday(day.value)
                    }
                } label: {
                    Text(day.short)
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .frame(minWidth: 34)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 4)
                        .foregroundStyle(isActive ? .white : .primary)
                        .background(
                            Capsule()
                                .fill(isActive ? Color.accentColor : Color(nsColor: .quaternaryLabelColor))
                        )
                }
                .buttonStyle(.plain)
                .help(day.full)
            }
        }
    }

    private var modeBinding: Binding<ScheduleBuilderMode> {
        Binding(
            get: { viewModel.draft.mode },
            set: { mode in
                if mode == .calendar {
                    viewModel.setCalendarMode()
                } else {
                    viewModel.setIntervalMode()
                }
            }
        )
    }

    private func inspectorCard<Content: View>(title: String, symbol: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol)
                .font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.regularMaterial)
        )
    }

    private func agentIcon(for agent: ScheduledAgent) -> Image {
        if !agent.commandPath.isEmpty,
           FileManager.default.fileExists(atPath: agent.commandPath) {
            return Image(nsImage: NSWorkspace.shared.icon(forFile: agent.commandPath))
        }

        return Image(systemName: "calendar.badge.clock")
    }

    private var weekdays: [(value: Int, short: String, full: String)] {
        [
            (2, "Mon", "Monday"),
            (3, "Tue", "Tuesday"),
            (4, "Wed", "Wednesday"),
            (5, "Thu", "Thursday"),
            (6, "Fri", "Friday"),
            (7, "Sat", "Saturday"),
            (1, "Sun", "Sunday")
        ]
    }
}

private struct ScheduledAgentRow: View {
    let agent: ScheduledAgent
    let nextRunText: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            icon
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(agent.label)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text("\(agent.scheduleDescription) • Next run \(nextRunText)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                Circle()
                    .fill(agent.isLoaded ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
                Text(agent.isLoaded ? "Active" : "Disabled")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 2)
        }
        .padding(.vertical, 4)
    }

    private var icon: Image {
        if !agent.commandPath.isEmpty,
           FileManager.default.fileExists(atPath: agent.commandPath) {
            return Image(nsImage: NSWorkspace.shared.icon(forFile: agent.commandPath))
        }
        return Image(systemName: "calendar.badge.clock")
    }
}
