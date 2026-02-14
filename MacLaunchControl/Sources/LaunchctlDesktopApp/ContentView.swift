import AppKit
import SwiftUI

struct ContentView: View {
    @StateObject private var vm = AppViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Mac Launch Control")
                    .font(.title2)
                    .bold()
                Spacer()
                Button("Обновить") {
                    vm.refreshAll()
                }
                .keyboardShortcut("r", modifiers: [.command])
            }

            if !vm.statusMessage.isEmpty {
                Text(vm.statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if !vm.errorMessage.isEmpty {
                Text(vm.errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            TabView {
                processesTab
                    .tabItem { Text("Процессы") }
                jobsTab
                    .tabItem { Text("launchctl") }
                scheduleTab
                    .tabItem { Text("Расписание") }
            }
        }
        .padding(16)
        .frame(minWidth: 980, minHeight: 680)
        .onAppear {
            vm.refreshAll()
        }
    }

    private var processesTab: some View {
        Table(vm.runningProcesses) {
            TableColumn("PID") { item in
                Text("\(item.pid)")
            }
            .width(min: 64, ideal: 80, max: 90)

            TableColumn("Command") { item in
                Text(item.command)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            TableColumn("Copy") { item in
                Button("Copy") {
                    copyCommand(item.command)
                }
                .buttonStyle(.borderless)
                .help("Копировать Command")
            }
            .width(min: 60, ideal: 70, max: 80)
        }
    }

    private var jobsTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Фильтр label:")
                TextField("например, chrome или com.apple", text: $vm.labelFilter)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 320)
                if !vm.labelFilter.isEmpty {
                    Button("Сброс") {
                        vm.labelFilter = ""
                    }
                }
            }

            Table(filteredJobs) {
                TableColumn("Label") { item in
                    HStack(spacing: 8) {
                        Text(item.label)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button {
                            copyLabel(item.label)
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.borderless)
                        .help("Копировать Label")
                    }
                }
                TableColumn("PID") { item in
                    Text(item.pid)
                }
                TableColumn("Status") { item in
                    Text(item.status)
                }
            }
        }
    }

    private var scheduleTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupBox("Новая задача / обновление") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Label")
                            .frame(width: 120, alignment: .leading)
                        TextField("com.launchctl.schedule.my-job", text: $vm.label)
                    }

                    HStack {
                        Text("Команда")
                            .frame(width: 120, alignment: .leading)
                        TextField("/usr/bin/say", text: $vm.commandPath)
                    }

                    HStack {
                        Text("Аргументы")
                            .frame(width: 120, alignment: .leading)
                        TextField("hello", text: $vm.commandArguments)
                    }

                    HStack {
                        Text("Время")
                            .frame(width: 120, alignment: .leading)
                        Stepper(value: $vm.hour, in: 0...23) {
                            Text("Hour: \(vm.hour)")
                        }
                        Stepper(value: $vm.minute, in: 0...59) {
                            Text("Minute: \(vm.minute)")
                        }
                    }

                    HStack {
                        Text("Дни")
                            .frame(width: 120, alignment: .leading)
                        Toggle("Пн", isOn: $vm.monday)
                        Toggle("Вт", isOn: $vm.tuesday)
                        Toggle("Ср", isOn: $vm.wednesday)
                        Toggle("Чт", isOn: $vm.thursday)
                        Toggle("Пт", isOn: $vm.friday)
                        Toggle("Сб", isOn: $vm.saturday)
                        Toggle("Вс", isOn: $vm.sunday)
                    }

                    Toggle("Запускать сразу после логина (RunAtLoad)", isOn: $vm.runAtLoad)

                    HStack {
                        Button("Сохранить расписание") {
                            vm.saveSchedule()
                        }
                        Button("Обновить список") {
                            vm.refreshAll()
                        }
                    }
                }
                .padding(.top, 6)
            }

            GroupBox("Управляемые задачи (\(vm.managedAgents.count))") {
                Table(vm.managedAgents) {
                    TableColumn("Label") { item in
                        Text(item.label)
                    }
                    TableColumn("Команда") { item in
                        Text(item.command)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    TableColumn("Расписание") { item in
                        Text(item.scheduleDescription)
                    }
                    TableColumn("Loaded") { item in
                        Text(item.isLoaded ? "Да" : "Нет")
                    }
                    TableColumn("Действия") { item in
                        HStack {
                            Button("Unload") {
                                vm.unload(label: item.label)
                            }
                            Button("Delete") {
                                vm.remove(label: item.label)
                            }
                        }
                    }
                }
                .frame(minHeight: 260)
            }
        }
    }

    private var filteredJobs: [LaunchctlJob] {
        let filter = vm.labelFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        if filter.isEmpty {
            return vm.launchctlJobs
        }
        return vm.launchctlJobs.filter { $0.label.localizedCaseInsensitiveContains(filter) }
    }

    private func copyLabel(_ label: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(label, forType: .string)
        vm.statusMessage = "Скопировано: \(label)"
    }

    private func copyCommand(_ command: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        vm.statusMessage = "Скопирован Command"
    }
}
