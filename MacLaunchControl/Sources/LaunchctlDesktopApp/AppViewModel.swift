import Foundation

@MainActor
final class AppViewModel: ObservableObject {
    @Published var runningProcesses: [RunningProcess] = []
    @Published var launchctlJobs: [LaunchctlJob] = []
    @Published var managedAgents: [ManagedAgent] = []
    @Published var timedJobs: [TimedLaunchItem] = []

    @Published var isLoading = false
    @Published var statusMessage = ""
    @Published var errorMessage = ""
    @Published var labelFilter = ""
    @Published var timerFilter = ""
    @Published var editingTimerPath = ""

    @Published var label = "com.launchctl.schedule.demo"
    @Published var commandPath = "/usr/bin/say"
    @Published var commandArguments = "hello from launchctl"
    @Published var scheduleMode: ScheduleMode = .calendar
    @Published var hour = 9
    @Published var minute = 0
    @Published var intervalValue = 15
    @Published var intervalUnit: IntervalUnit = .minutes
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
                let timed = try self.service.fetchTimedJobs()

                await MainActor.run {
                    self.runningProcesses = processes
                    self.launchctlJobs = jobs
                    self.managedAgents = agents
                    self.timedJobs = timed
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
        statusMessage = editingTimerPath.isEmpty ? "Сохраняю расписание..." : "Обновляю таймер..."

        let targetTimerPath = editingTimerPath
        let weekdays = selectedWeekdays()
        let input = ScheduleInput(
            label: label.trimmingCharacters(in: .whitespacesAndNewlines),
            commandPath: commandPath.trimmingCharacters(in: .whitespacesAndNewlines),
            arguments: commandArguments,
            mode: scheduleMode,
            hour: hour,
            minute: minute,
            weekdays: weekdays,
            intervalValue: intervalValue,
            intervalUnit: intervalUnit,
            runAtLoad: runAtLoad
        )

        Task.detached {
            do {
                if targetTimerPath.isEmpty {
                    try self.service.createOrUpdateAgent(input: input)
                } else {
                    try self.service.updateTimer(at: targetTimerPath, input: input)
                }

                let agents = try self.service.fetchManagedAgents()
                let jobs = try self.service.fetchLaunchctlJobs()
                let timed = try self.service.fetchTimedJobs()

                await MainActor.run {
                    self.managedAgents = agents
                    self.launchctlJobs = jobs
                    self.timedJobs = timed
                    self.statusMessage = targetTimerPath.isEmpty ? "Готово: \(input.label)" : "Таймер обновлён: \(input.label)"
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.statusMessage = ""
                }
            }
        }
    }

    func loadTimerForEdit(_ item: TimedLaunchItem) {
        label = item.label
        commandPath = item.commandPath.isEmpty ? commandPath : item.commandPath
        commandArguments = item.arguments
        runAtLoad = item.runAtLoad
        editingTimerPath = item.path

        if let startInterval = item.startIntervalSeconds {
            scheduleMode = .interval
            configureInterval(from: startInterval)
        } else {
            scheduleMode = .calendar
            if let h = item.hour {
                hour = h
            }
            if let m = item.minute {
                minute = m
            }
            applyWeekdays(item.weekdays)
        }

        statusMessage = "Редактирование: \(item.label)"
        errorMessage = ""
    }

    func clearTimerEditing() {
        editingTimerPath = ""
        statusMessage = "Режим редактирования таймера выключен"
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
                let timed = try self.service.fetchTimedJobs()
                await MainActor.run {
                    self.managedAgents = agents
                    self.launchctlJobs = jobs
                    self.timedJobs = timed
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

    private func configureInterval(from startInterval: Int) {
        if startInterval % IntervalUnit.days.secondsMultiplier == 0 {
            intervalUnit = .days
            intervalValue = max(1, startInterval / IntervalUnit.days.secondsMultiplier)
            return
        }
        if startInterval % IntervalUnit.hours.secondsMultiplier == 0 {
            intervalUnit = .hours
            intervalValue = max(1, startInterval / IntervalUnit.hours.secondsMultiplier)
            return
        }
        intervalUnit = .minutes
        intervalValue = max(1, startInterval / IntervalUnit.minutes.secondsMultiplier)
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

    private func applyWeekdays(_ weekdays: Set<Int>) {
        sunday = weekdays.contains(0)
        monday = weekdays.contains(1)
        tuesday = weekdays.contains(2)
        wednesday = weekdays.contains(3)
        thursday = weekdays.contains(4)
        friday = weekdays.contains(5)
        saturday = weekdays.contains(6)
    }
}
