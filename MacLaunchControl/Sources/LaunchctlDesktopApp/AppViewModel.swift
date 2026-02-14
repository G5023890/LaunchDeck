import Foundation

@MainActor
final class AppViewModel: ObservableObject {
    @Published var runningProcesses: [RunningProcess] = []
    @Published var launchctlJobs: [LaunchctlJob] = []
    @Published var managedAgents: [ManagedAgent] = []

    @Published var isLoading = false
    @Published var statusMessage = ""
    @Published var errorMessage = ""
    @Published var labelFilter = ""

    @Published var label = "com.launchctl.schedule.demo"
    @Published var commandPath = "/usr/bin/say"
    @Published var commandArguments = "hello from launchctl"
    @Published var hour = 9
    @Published var minute = 0
    @Published var runAtLoad = false
    @Published var monday = true
    @Published var tuesday = true
    @Published var wednesday = true
    @Published var thursday = true
    @Published var friday = true
    @Published var saturday = false
    @Published var sunday = false

    private let service = LaunchctlService()

    func refreshAll() {
        isLoading = true
        errorMessage = ""
        statusMessage = "Обновление..."

        Task.detached {
            do {
                let processes = try self.service.fetchRunningProcesses()
                let jobs = try self.service.fetchLaunchctlJobs()
                let agents = try self.service.fetchManagedAgents()
                await MainActor.run {
                    self.runningProcesses = processes
                    self.launchctlJobs = jobs
                    self.managedAgents = agents
                    self.isLoading = false
                    self.statusMessage = "Обновлено: \(Date().formatted(date: .abbreviated, time: .standard))"
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    self.errorMessage = error.localizedDescription
                    self.statusMessage = ""
                }
            }
        }
    }

    func saveSchedule() {
        errorMessage = ""
        statusMessage = "Сохраняю расписание..."

        let weekdays = selectedWeekdays()
        let input = ScheduleInput(
            label: label.trimmingCharacters(in: .whitespacesAndNewlines),
            commandPath: commandPath.trimmingCharacters(in: .whitespacesAndNewlines),
            arguments: commandArguments,
            hour: hour,
            minute: minute,
            weekdays: weekdays,
            runAtLoad: runAtLoad
        )

        Task.detached {
            do {
                try self.service.createOrUpdateAgent(input: input)
                let agents = try self.service.fetchManagedAgents()
                let jobs = try self.service.fetchLaunchctlJobs()
                await MainActor.run {
                    self.managedAgents = agents
                    self.launchctlJobs = jobs
                    self.statusMessage = "Готово: \(input.label)"
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.statusMessage = ""
                }
            }
        }
    }

    func unload(label: String) {
        errorMessage = ""
        statusMessage = "Отключаю \(label)..."

        Task.detached {
            do {
                try self.service.unload(label: label)
                let agents = try self.service.fetchManagedAgents()
                let jobs = try self.service.fetchLaunchctlJobs()
                await MainActor.run {
                    self.managedAgents = agents
                    self.launchctlJobs = jobs
                    self.statusMessage = "Отключено: \(label)"
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.statusMessage = ""
                }
            }
        }
    }

    func remove(label: String) {
        errorMessage = ""
        statusMessage = "Удаляю \(label)..."

        Task.detached {
            do {
                try self.service.removeAgent(label: label)
                let agents = try self.service.fetchManagedAgents()
                let jobs = try self.service.fetchLaunchctlJobs()
                await MainActor.run {
                    self.managedAgents = agents
                    self.launchctlJobs = jobs
                    self.statusMessage = "Удалено: \(label)"
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.statusMessage = ""
                }
            }
        }
    }

    private func selectedWeekdays() -> Set<Int> {
        var values: Set<Int> = []
        if sunday { values.insert(0) }
        if monday { values.insert(1) }
        if tuesday { values.insert(2) }
        if wednesday { values.insert(3) }
        if thursday { values.insert(4) }
        if friday { values.insert(5) }
        if saturday { values.insert(6) }
        return values
    }
}
