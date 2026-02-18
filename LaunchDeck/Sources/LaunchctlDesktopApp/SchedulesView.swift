import SwiftUI

struct SchedulesView: View {
    @ObservedObject var viewModel: SchedulesViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if !viewModel.errorMessage.isEmpty {
                statusText(viewModel.errorMessage, color: .red)
            } else if !viewModel.statusMessage.isEmpty {
                statusText(viewModel.statusMessage, color: .secondary)
            }

            GroupBox {
                Form {
                    Section("LaunchAgent") {
                        TextField("Label", text: $viewModel.draft.label)
                        TextField("Command path", text: $viewModel.draft.commandPath)
                        TextField("Arguments", text: $viewModel.draft.arguments)
                        Toggle("RunAtLoad", isOn: $viewModel.draft.runAtLoad)
                    }

                    Section("Schedule") {
                        Picker("Mode", selection: $viewModel.draft.mode) {
                            ForEach(ScheduleBuilderMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)

                        if viewModel.draft.mode == .calendar {
                            Stepper(value: $viewModel.draft.hour, in: 0...23) {
                                Text("Hour: \(viewModel.draft.hour)")
                                    .font(.system(.body, design: .monospaced))
                            }
                            Stepper(value: $viewModel.draft.minute, in: 0...59) {
                                Text("Minute: \(viewModel.draft.minute)")
                                    .font(.system(.body, design: .monospaced))
                            }
                            weekdayPicker
                        } else {
                            Stepper(value: $viewModel.draft.intervalSeconds, in: 60...86_400, step: 60) {
                                Text("Interval: \(viewModel.draft.intervalSeconds) sec")
                                    .font(.system(.body, design: .monospaced))
                            }
                        }

                        LabeledContent("Preview") {
                            Text(viewModel.schedulePreview)
                                .multilineTextAlignment(.trailing)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } label: {
                Label("Builder", systemImage: "calendar.badge.plus")
            }

            HStack {
                Button {
                    viewModel.saveDraft()
                } label: {
                    Label("Save LaunchAgent", systemImage: "square.and.arrow.down")
                }

                Button {
                    viewModel.unloadSelected()
                } label: {
                    Label("Unload selected", systemImage: "eject")
                }

                Button(role: .destructive) {
                    viewModel.removeSelected()
                } label: {
                    Label("Remove selected", systemImage: "trash")
                }

                Spacer()

                Button {
                    viewModel.refresh()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }

            GroupBox {
                Table(
                    viewModel.managedAgents,
                    selection: $viewModel.selectedManagedAgentID,
                    sortOrder: $viewModel.sortOrder
                ) {
                    TableColumn("Label", value: \ManagedAgent.label) { item in
                        Text(item.label)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .width(min: 240, ideal: 320, max: 460)

                    TableColumn("Mode", value: \ManagedAgent.modeTitle) { item in
                        Text(item.modeTitle)
                    }
                    .width(min: 80, ideal: 110, max: 140)

                    TableColumn("Schedule") { item in
                        Text(viewModel.scheduleText(for: item.schedule))
                            .lineLimit(2)
                    }

                    TableColumn("Next Run") { item in
                        Text(viewModel.nextRunText(for: item.schedule))
                            .font(.system(.body, design: .monospaced))
                    }
                    .width(min: 140, ideal: 170, max: 220)

                    TableColumn("Loaded") { item in
                        Text(item.isLoaded ? "Yes" : "No")
                            .foregroundStyle(item.isLoaded ? .green : .secondary)
                    }
                    .width(min: 70, ideal: 90, max: 100)
                }
                .overlay {
                    if viewModel.isLoading {
                        ProgressView()
                            .controlSize(.large)
                    }
                }
            } label: {
                Label("Managed Agents", systemImage: "tablecells")
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
            Label("Schedules", systemImage: "calendar.badge.clock")
                .font(.title3.weight(.semibold))
            Spacer()
        }
    }

    private var weekdayPicker: some View {
        HStack(spacing: 10) {
            ForEach(weekdays, id: \.value) { weekday in
                Toggle(weekday.shortName, isOn: bindingForWeekday(weekday.value))
                    .toggleStyle(.button)
                    .help(weekday.fullName)
            }
        }
    }

    private func bindingForWeekday(_ value: Int) -> Binding<Bool> {
        Binding {
            viewModel.draft.weekdays.contains(value)
        } set: { isEnabled in
            if isEnabled {
                viewModel.draft.weekdays.insert(value)
            } else {
                viewModel.draft.weekdays.remove(value)
            }
        }
    }

    private func statusText(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(color)
    }

    private var weekdays: [(value: Int, shortName: String, fullName: String)] {
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
