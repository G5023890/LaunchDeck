import Foundation

@MainActor
final class AppViewModel: ObservableObject {
    @Published var selectedSection: SidebarSection? = .processes

    let processesViewModel: ProcessesViewModel
    let launchServicesViewModel: LaunchServicesViewModel
    let schedulesViewModel: SchedulesViewModel
    let diagnosticsViewModel: DiagnosticsViewModel

    init(service: LaunchctlService = LaunchctlService()) {
        processesViewModel = ProcessesViewModel(service: service)
        launchServicesViewModel = LaunchServicesViewModel(service: service)
        schedulesViewModel = SchedulesViewModel(service: service)
        diagnosticsViewModel = DiagnosticsViewModel(service: service)
    }

    func refreshCurrentSection() {
        guard let selectedSection else { return }

        switch selectedSection {
        case .processes:
            processesViewModel.refresh()
        case .launchServices, .userAgents, .systemAgents, .systemDaemons:
            launchServicesViewModel.refresh()
        case .schedules:
            schedulesViewModel.refresh()
        case .diagnostics:
            diagnosticsViewModel.captureSnapshot(
                processCount: processesViewModel.processes.count,
                launchJobCount: launchServicesViewModel.jobs.count
            )
        }
    }

    func initialLoad() {
        processesViewModel.refresh()
        launchServicesViewModel.refresh()
        schedulesViewModel.refresh()
    }
}

@MainActor
final class ProcessesViewModel: ObservableObject {
    @Published var processes: [RunningProcess] = []
    @Published var selectedProcessID: RunningProcess.ID?
    @Published var sortOrder: [KeyPathComparator<RunningProcess>] = [
        .init(\RunningProcess.cpu, order: .reverse)
    ] {
        didSet { applySort() }
    }

    @Published var isLiveRefresh = false {
        didSet { configureLiveRefresh() }
    }

    @Published var isLoading = false
    @Published var statusMessage = ""
    @Published var errorMessage = ""

    private let service: LaunchctlService
    private var liveRefreshTask: Task<Void, Never>?

    init(service: LaunchctlService) {
        self.service = service
    }

    deinit {
        liveRefreshTask?.cancel()
    }

    var selectedProcess: RunningProcess? {
        guard let selectedProcessID else { return nil }
        return processes.first(where: { $0.id == selectedProcessID })
    }

    func refresh() {
        Task { await refreshAsync() }
    }

    func refreshAsync() async {
        isLoading = true
        errorMessage = ""

        do {
            var items = try await service.fetchRunningProcesses()
            items.sort(using: sortOrder)
            processes = items
            statusMessage = "Updated \(Date().formatted(date: .omitted, time: .standard))"
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func killSelected(force: Bool) {
        guard let selected = selectedProcess else {
            errorMessage = "Select a process first"
            return
        }
        kill(selected, force: force)
    }

    func kill(_ process: RunningProcess, force: Bool) {
        selectedProcessID = process.id

        Task {
            do {
                try await service.killProcess(pid: process.pid, force: force)
                statusMessage = force ? "Killed \(process.pid) with KILL" : "Sent TERM to \(process.pid)"
                await refreshAsync()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func revealSelectedBinary() {
        guard let selected = selectedProcess else {
            errorMessage = "Select a process first"
            return
        }
        revealBinary(for: selected)
    }

    func revealBinary(for process: RunningProcess) {
        selectedProcessID = process.id

        guard let path = process.binaryPath else {
            errorMessage = "Selected command is not an absolute binary path"
            return
        }

        Task {
            do {
                try await service.revealBinary(path: path)
                statusMessage = "Revealed \(path)"
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func configureLiveRefresh() {
        liveRefreshTask?.cancel()
        guard isLiveRefresh else { return }

        liveRefreshTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.refreshAsync()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func applySort() {
        processes.sort(using: sortOrder)
    }
}

@MainActor
final class LaunchServicesViewModel: ObservableObject {
    @Published var jobs: [LaunchServiceJob] = []
    @Published var selectedJobID: LaunchServiceJob.ID?
    @Published var filterText = ""
    @Published var sortOrder: [KeyPathComparator<LaunchServiceJob>] = [
        .init(\LaunchServiceJob.label, order: .forward)
    ] {
        didSet { jobs.sort(using: sortOrder) }
    }

    @Published var isLoading = false
    @Published var statusMessage = ""
    @Published var errorMessage = ""

    private let service: LaunchctlService

    init(service: LaunchctlService) {
        self.service = service
    }

    var selectedJob: LaunchServiceJob? {
        guard let selectedJobID else { return nil }
        return jobs.first(where: { $0.id == selectedJobID })
    }

    func refresh() {
        Task { await refreshAsync() }
    }

    func refreshAsync() async {
        isLoading = true
        errorMessage = ""

        do {
            var fetched = try await service.fetchLaunchServices()
            fetched.sort(using: sortOrder)
            jobs = fetched

            if let selectedJobID, jobs.contains(where: { $0.id == selectedJobID }) == false {
                self.selectedJobID = nil
            }

            statusMessage = "Loaded \(jobs.count) jobs"
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func filteredJobs(for section: SidebarSection) -> [LaunchServiceJob] {
        let trimmedFilter = filterText.trimmingCharacters(in: .whitespacesAndNewlines)

        return jobs.filter { job in
            let inSection: Bool
            switch section {
            case .launchServices:
                inSection = true
            case .userAgents:
                inSection = job.domain == .userAgent
            case .systemAgents:
                inSection = job.domain == .systemAgent
            case .systemDaemons:
                inSection = job.domain == .systemDaemon
            default:
                inSection = true
            }

            guard inSection else { return false }
            guard !trimmedFilter.isEmpty else { return true }
            return job.label.localizedCaseInsensitiveContains(trimmedFilter)
                || (job.program ?? "").localizedCaseInsensitiveContains(trimmedFilter)
        }
    }

    func loadSelected() { performJobAction(name: "Load") { [self] in try await service.load($0) } }

    func unloadSelected() { performJobAction(name: "Unload") { [self] in try await service.unload($0) } }

    func kickstartSelected() { performJobAction(name: "Kickstart") { [self] in try await service.kickstart($0) } }

    func editSelected() { performJobAction(name: "Edit plist") { [self] in try await service.openPlistInEditor($0) } }

    func revealSelected() { performJobAction(name: "Reveal") { [self] in try await service.revealJobFile($0) } }

    private func performJobAction(name: String, action: @escaping (LaunchServiceJob) async throws -> Void) {
        guard let job = selectedJob else {
            errorMessage = "Select a launch service first"
            return
        }

        Task {
            do {
                try await action(job)
                statusMessage = "\(name): \(job.label)"
                await refreshAsync()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

@MainActor
final class SchedulesViewModel: ObservableObject {
    @Published var draft = ScheduleDraft()
    @Published var managedAgents: [ManagedAgent] = []
    @Published var selectedManagedAgentID: ManagedAgent.ID?
    @Published var sortOrder: [KeyPathComparator<ManagedAgent>] = [
        .init(\ManagedAgent.label, order: .forward)
    ] {
        didSet { managedAgents.sort(using: sortOrder) }
    }

    @Published var isLoading = false
    @Published var statusMessage = ""
    @Published var errorMessage = ""

    private let service: LaunchctlService

    init(service: LaunchctlService) {
        self.service = service
    }

    var selectedAgent: ManagedAgent? {
        guard let selectedManagedAgentID else { return nil }
        return managedAgents.first(where: { $0.id == selectedManagedAgentID })
    }

    var schedulePreview: String {
        switch draft.mode {
        case .interval:
            let components = DateComponents(second: draft.intervalSeconds)
            let formatter = DateComponentsFormatter()
            formatter.unitsStyle = .full
            formatter.allowedUnits = [.hour, .minute, .second]
            let text = formatter.string(from: components) ?? "\(draft.intervalSeconds) seconds"
            return "Runs every \(text)" + (draft.runAtLoad ? " (plus at login)" : "")

        case .calendar:
            let weekdays = weekdayNames(for: draft.weekdays)
            let time = String(format: "%02d:%02d", draft.hour, draft.minute)
            let dayText = weekdays.isEmpty ? "every day" : weekdays.joined(separator: ", ")
            return "Runs at \(time) on \(dayText)" + (draft.runAtLoad ? " (plus at login)" : "")
        }
    }

    func refresh() {
        Task { await refreshAsync() }
    }

    func refreshAsync() async {
        isLoading = true
        errorMessage = ""

        do {
            var agents = try await service.fetchManagedAgents()
            agents.sort(using: sortOrder)
            managedAgents = agents
            statusMessage = "Managed agents: \(agents.count)"
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func saveDraft() {
        Task {
            do {
                try await service.createOrUpdateManagedAgent(from: draft)
                statusMessage = "Saved \(draft.label)"
                await refreshAsync()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func unloadSelected() {
        guard let selectedAgent else {
            errorMessage = "Select a managed agent first"
            return
        }

        Task {
            do {
                try await service.unloadManagedAgent(label: selectedAgent.label)
                statusMessage = "Unloaded \(selectedAgent.label)"
                await refreshAsync()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func removeSelected() {
        guard let selectedAgent else {
            errorMessage = "Select a managed agent first"
            return
        }

        Task {
            do {
                try await service.removeManagedAgent(label: selectedAgent.label)
                statusMessage = "Removed \(selectedAgent.label)"
                await refreshAsync()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func scheduleText(for schedule: LaunchSchedule) -> String {
        switch schedule {
        case .none:
            return "Manual"
        case .interval(let seconds):
            let formatter = DateComponentsFormatter()
            formatter.unitsStyle = .abbreviated
            formatter.allowedUnits = [.hour, .minute, .second]
            return "Every " + (formatter.string(from: TimeInterval(seconds)) ?? "\(seconds)s")
        case .calendar(let entries):
            if entries.isEmpty { return "Manual" }
            return entries
                .map { entry in
                    let time = String(format: "%02d:%02d", entry.hour, entry.minute)
                    if let weekday = entry.weekday {
                        return "\(weekdayName(weekday)) \(time)"
                    }
                    return "Daily \(time)"
                }
                .joined(separator: ", ")
        }
    }

    func nextRunText(for schedule: LaunchSchedule) -> String {
        guard let date = nextRun(for: schedule) else { return "-" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private func nextRun(for schedule: LaunchSchedule) -> Date? {
        let now = Date()
        let calendar = Calendar.current

        switch schedule {
        case .none:
            return nil
        case .interval(let seconds):
            return now.addingTimeInterval(TimeInterval(seconds))
        case .calendar(let entries):
            let candidates = entries.compactMap { entry -> Date? in
                var components = DateComponents()
                components.hour = entry.hour
                components.minute = entry.minute
                components.second = 0
                components.weekday = entry.weekday

                return calendar.nextDate(
                    after: now,
                    matching: components,
                    matchingPolicy: .nextTime,
                    repeatedTimePolicy: .first,
                    direction: .forward
                )
            }
            return candidates.min()
        }
    }

    private func weekdayNames(for values: Set<Int>) -> [String] {
        values.sorted().map(weekdayName)
    }

    private func weekdayName(_ value: Int) -> String {
        let symbols = Calendar.current.weekdaySymbols
        let index = max(1, min(7, value)) - 1
        return symbols[index]
    }
}

@MainActor
final class DiagnosticsViewModel: ObservableObject {
    @Published var consoleText = ""
    @Published var isLoading = false
    @Published var statusMessage = ""
    @Published var errorMessage = ""

    private let service: LaunchctlService

    init(service: LaunchctlService) {
        self.service = service
    }

    func captureSnapshot(processCount: Int, launchJobCount: Int) {
        Task {
            isLoading = true
            errorMessage = ""

            let header = [
                "Dashboard signals",
                "Processes: \(processCount)",
                "Launch jobs: \(launchJobCount)",
                ""
            ].joined(separator: "\n")

            let text = await service.diagnosticsSnapshot()
            consoleText = header + text
            statusMessage = "Snapshot collected"
            isLoading = false
        }
    }
}
