import AppKit
import Foundation
import SwiftUI

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

    var canActOnSelectedProcess: Bool {
        guard let selectedProcessID else { return false }
        return processes.contains(where: { $0.id == selectedProcessID })
    }

    func refresh() {
        Task { await refreshAsync() }
    }

    func refreshAsync() async {
        isLoading = true
        errorMessage = ""
        let previousSelection = selectedProcessID

        do {
            var items = try await service.fetchRunningProcesses()
            items = stableSorted(items)
            withAnimation(.easeInOut(duration: 0.16)) {
                processes = items
            }
            if let previousSelection, items.contains(where: { $0.id == previousSelection }) {
                selectedProcessID = previousSelection
            } else {
                selectedProcessID = nil
            }
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

    func copyPID(_ process: RunningProcess) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(String(process.pid), forType: .string)
        statusMessage = "Copied PID \(process.pid)"
    }

    func copyFullPath(_ process: RunningProcess) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(process.displayPath, forType: .string)
        statusMessage = "Copied path"
    }

    func isProcessAlive(_ process: RunningProcess) -> Bool {
        processes.contains(where: { $0.id == process.id })
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
        processes = stableSorted(processes)
    }

    private func stableSorted(_ values: [RunningProcess]) -> [RunningProcess] {
        values
            .enumerated()
            .sorted { lhs, rhs in
                for comparator in sortOrder {
                    let result = comparator.compare(lhs.element, rhs.element)
                    if result == .orderedAscending { return true }
                    if result == .orderedDescending { return false }
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }
}

@MainActor
final class LaunchServicesViewModel: ObservableObject {
    @Published var jobs: [LaunchServiceJob] = []
    @Published var selectedJobID: LaunchServiceJob.ID?
    @Published var filterText = ""
    @Published var statusFilter: LaunchServicesStatusFilter = .all
    @Published var sortOption: LaunchServicesSortOption = .label
    @Published var expandedGroups: Set<LaunchServicesGroup> = Set(LaunchServicesGroup.allCases)

    @Published var isLoading = false
    @Published var statusMessage = ""
    @Published var errorMessage = ""

    private let service: LaunchctlService
    private let scheduleParser = LaunchAgentParser()

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
            fetched = sorted(fetched)
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

        let base = jobs.filter { job in
            let inScope: Bool
            switch section {
            case .launchServices:
                inScope = true
            case .userAgents:
                inScope = job.domain == .userAgent
            case .systemAgents:
                inScope = job.domain == .systemAgent
            case .systemDaemons:
                inScope = job.domain == .systemDaemon
            default:
                inScope = true
            }
            guard inScope else { return false }

            let passStatus: Bool
            switch statusFilter {
            case .all:
                passStatus = true
            case .running:
                passStatus = job.state == .running
            case .loaded:
                passStatus = job.state == .loadedIdle
            case .unloaded:
                passStatus = job.state == .unloaded || job.state == .crashed
            case .system:
                passStatus = job.domain == .systemAgent || job.domain == .systemDaemon
            case .user:
                passStatus = job.domain == .userAgent || job.group == .applications
            }
            guard passStatus else { return false }

            guard !trimmedFilter.isEmpty else { return true }
            return job.label.localizedCaseInsensitiveContains(trimmedFilter)
                || (job.program ?? "").localizedCaseInsensitiveContains(trimmedFilter)
        }

        return sorted(base)
    }

    func groupedJobs(for section: SidebarSection) -> [(group: LaunchServicesGroup, jobs: [LaunchServiceJob])] {
        let filtered = filteredJobs(for: section)
        let grouped = Dictionary(grouping: filtered, by: \.group)

        return LaunchServicesGroup.allCases.compactMap { group in
            guard let values = grouped[group], !values.isEmpty else { return nil }
            return (group, values)
        }
    }

    func isGroupExpanded(_ group: LaunchServicesGroup) -> Bool {
        expandedGroups.contains(group)
    }

    func toggleGroup(_ group: LaunchServicesGroup) {
        if expandedGroups.contains(group) {
            expandedGroups.remove(group)
        } else {
            expandedGroups.insert(group)
        }
    }

    var canLoadSelected: Bool {
        guard let job = selectedJob else { return false }
        return job.plistPath != nil && !job.isLoaded
    }

    var canUnloadSelected: Bool {
        guard let job = selectedJob else { return false }
        return job.plistPath != nil && job.isLoaded
    }

    var canEditSelected: Bool { selectedJob?.plistPath != nil }
    var canRevealSelected: Bool { selectedJob?.plistPath != nil || selectedJob?.program?.hasPrefix("/") == true }
    var canKickstartSelected: Bool { selectedJob?.isLoaded == true }

    func loadSelected() { performJobAction(named: "Load", on: selectedJob, action: { [self] in try await service.load($0) }) }
    func unloadSelected() { performJobAction(named: "Unload", on: selectedJob, action: { [self] in try await service.unload($0) }) }
    func kickstartSelected() { performJobAction(named: "Kickstart", on: selectedJob, action: { [self] in try await service.kickstart($0) }) }
    func editSelected() { performJobAction(named: "Edit plist", on: selectedJob, action: { [self] in try await service.openPlistInEditor($0) }) }
    func revealSelected() { performJobAction(named: "Reveal", on: selectedJob, action: { [self] in try await service.revealJobFile($0) }) }

    func load(job: LaunchServiceJob) { performJobAction(named: "Load", on: job, action: { [self] in try await service.load($0) }) }
    func unload(job: LaunchServiceJob) { performJobAction(named: "Unload", on: job, action: { [self] in try await service.unload($0) }) }
    func kickstart(job: LaunchServiceJob) { performJobAction(named: "Kickstart", on: job, action: { [self] in try await service.kickstart($0) }) }
    func edit(job: LaunchServiceJob) { performJobAction(named: "Edit plist", on: job, action: { [self] in try await service.openPlistInEditor($0) }) }
    func reveal(job: LaunchServiceJob) { performJobAction(named: "Reveal", on: job, action: { [self] in try await service.revealJobFile($0) }) }

    func copyLabel(_ label: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(label, forType: .string)
        statusMessage = "Copied \(label)"
    }

    func scheduleSummary(for job: LaunchServiceJob) -> String {
        scheduleParser.scheduleDescription(for: job.schedule)
    }

    func scheduleNextRun(for job: LaunchServiceJob) -> Date? {
        scheduleParser.nextRun(for: job.schedule)
    }

    private func performJobAction(
        named name: String,
        on job: LaunchServiceJob?,
        action: @escaping (LaunchServiceJob) async throws -> Void
    ) {
        guard let job else {
            errorMessage = "Select a launch service first"
            return
        }

        selectedJobID = job.id
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

    private func sorted(_ values: [LaunchServiceJob]) -> [LaunchServiceJob] {
        switch sortOption {
        case .label:
            return values.sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
        case .domain:
            return values.sorted {
                if $0.group == $1.group {
                    return $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending
                }
                return $0.group.rawValue < $1.group.rawValue
            }
        case .status:
            return values.sorted {
                if stateRank($0.state) == stateRank($1.state) {
                    return $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending
                }
                return stateRank($0.state) < stateRank($1.state)
            }
        }
    }

    private func stateRank(_ state: LaunchJobState) -> Int {
        switch state {
        case .running:
            return 0
        case .loadedIdle:
            return 1
        case .unloaded:
            return 2
        case .crashed:
            return 3
        }
    }
}

@MainActor
final class SchedulesViewModel: ObservableObject {
    @Published var draft = ScheduleDraft()
    @Published var scheduledAgents: [ScheduledAgent] = []
    @Published var selectedScheduledAgentID: ScheduledAgent.ID? {
        didSet { loadSelectedAgentIntoBuilder() }
    }
    @Published var sortOrder: [KeyPathComparator<ScheduledAgent>] = [
        .init(\ScheduledAgent.label, order: .forward)
    ] {
        didSet { scheduledAgents.sort(using: sortOrder) }
    }
    @Published var searchText = ""
    @Published var filter: SchedulesFilter = .all
    @Published var intervalValue = 15 {
        didSet { syncIntervalIntoDraftIfNeeded() }
    }
    @Published var intervalUnit: IntervalUnit = .minutes {
        didSet { syncIntervalIntoDraftIfNeeded() }
    }
    @Published var calendarTime: Date = Date() {
        didSet { syncCalendarIntoDraftIfNeeded() }
    }

    @Published var isLoading = false
    @Published var isApplying = false
    @Published var statusMessage = ""
    @Published var errorMessage = ""

    private let parser: LaunchAgentParser
    private let writer: LaunchAgentWriter
    private let launchCtl: LaunchCtlService
    private var isSyncingBuilderFromSelection = false
    private var isSyncingDerivedControls = false
    private var loadedDraftSnapshot: ScheduleDraft?

    init(
        service: LaunchctlService,
        parser: LaunchAgentParser = LaunchAgentParser(),
        writer: LaunchAgentWriter = LaunchAgentWriter(),
        launchCtl: LaunchCtlService = LaunchCtlService()
    ) {
        _ = service
        self.parser = parser
        self.writer = writer
        self.launchCtl = launchCtl
    }

    var selectedAgent: ScheduledAgent? {
        guard let selectedScheduledAgentID else { return nil }
        return scheduledAgents.first(where: { $0.id == selectedScheduledAgentID })
    }

    var filteredAgents: [ScheduledAgent] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return scheduledAgents.filter { agent in
            let matchesFilter: Bool
            switch filter {
            case .all:
                matchesFilter = true
            case .active:
                matchesFilter = agent.isLoaded
            case .disabled:
                matchesFilter = !agent.isLoaded
            }

            guard matchesFilter else { return false }
            guard !query.isEmpty else { return true }
            return agent.label.localizedCaseInsensitiveContains(query)
                || agent.scheduleDescription.localizedCaseInsensitiveContains(query)
        }
    }

    var schedulePreview: String {
        switch draft.mode {
        case .interval:
            let schedule = LaunchSchedule.interval(seconds: draft.intervalSeconds)
            return parser.scheduleDescription(for: schedule)
        case .calendar:
            let entries = makeCalendarEntries(hour: draft.hour, minute: draft.minute, weekdays: draft.weekdays)
            let schedule = LaunchSchedule.calendar(entries: entries)
            return parser.scheduleDescription(for: schedule)
        }
    }

    var previewNextRun: Date? {
        switch draft.mode {
        case .interval:
            return parser.nextRun(for: .interval(seconds: draft.intervalSeconds))
        case .calendar:
            return parser.nextRun(for: .calendar(entries: makeCalendarEntries(hour: draft.hour, minute: draft.minute, weekdays: draft.weekdays)))
        }
    }

    var intervalEquivalentText: String {
        "\(draft.intervalSeconds) seconds"
    }

    var canApplyChanges: Bool {
        selectedAgent != nil && hasPendingChanges && !isApplying
    }

    var hasPendingChanges: Bool {
        guard let loadedDraftSnapshot else { return false }
        return !isSameEditableState(lhs: loadedDraftSnapshot, rhs: draft)
    }

    var showReloadHint: Bool {
        selectedAgent?.isLoaded == true
    }

    func refresh() {
        Task { await refreshAsync() }
    }

    func refreshAsync() async {
        isLoading = true
        errorMessage = ""

        do {
            let loadedLabels = try await launchCtl.loadedLabels()
            var agents = try parser.scanScheduledAgents(loadedLabels: loadedLabels, includeSystemLaunchAgents: true)
            agents.sort(using: sortOrder)
            scheduledAgents = agents
            statusMessage = "Scheduled agents: \(agents.count)"

            if let selectedScheduledAgentID,
               scheduledAgents.contains(where: { $0.id == selectedScheduledAgentID }) == false {
                self.selectedScheduledAgentID = nil
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func applyChanges() {
        guard let selectedAgent else {
            errorMessage = "Select a scheduled agent first"
            return
        }
        guard hasPendingChanges else { return }

        let draftSnapshot = draft
        Task {
            isApplying = true
            do {
                try writer.rewriteScheduleAndRunAtLoad(
                    fileURL: selectedAgent.fileURL,
                    draft: draftSnapshot,
                    parser: parser
                )
                try await launchCtl.reload(plistURL: selectedAgent.fileURL)
                statusMessage = "Applied changes to \(draftSnapshot.label)"
                await refreshAsync()
                selectedScheduledAgentID = selectedAgent.id
            } catch {
                errorMessage = error.localizedDescription
            }
            isApplying = false
        }
    }

    func cancelChanges() {
        guard selectedAgent != nil else { return }
        loadSelectedAgentIntoBuilder()
    }

    func nextRunText(_ value: Date?) -> String {
        guard let date = value else { return "-" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    func nextRunRelativeText(_ value: Date?) -> String {
        guard let date = value else { return "No next run" }
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today at \(date.formatted(date: .omitted, time: .shortened))"
        }
        if calendar.isDateInTomorrow(date) {
            return "Tomorrow at \(date.formatted(date: .omitted, time: .shortened))"
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    func setCalendarMode() {
        draft.mode = .calendar
    }

    func setIntervalMode() {
        draft.mode = .interval
        syncIntervalIntoDraftIfNeeded()
    }

    func toggleWeekday(_ value: Int) {
        if draft.weekdays.contains(value) {
            draft.weekdays.remove(value)
        } else {
            draft.weekdays.insert(value)
        }
    }

    private func loadSelectedAgentIntoBuilder() {
        guard let selectedAgent else { return }
        do {
            guard let parsed = try parser.parseAgent(at: selectedAgent.fileURL) else {
                errorMessage = "Failed to parse plist: \(selectedAgent.fileURL.path)"
                return
            }
            isSyncingBuilderFromSelection = true
            isSyncingDerivedControls = true
            draft = parser.draft(from: parsed)
            loadedDraftSnapshot = draft
            calendarTime = makeDate(hour: draft.hour, minute: draft.minute)
            syncIntervalControlsFromDraft()
            statusMessage = "Loaded \(parsed.label)"
            isSyncingDerivedControls = false
            isSyncingBuilderFromSelection = false
        } catch {
            isSyncingBuilderFromSelection = false
            isSyncingDerivedControls = false
            errorMessage = error.localizedDescription
        }
    }

    private func makeCalendarEntries(hour: Int, minute: Int, weekdays: Set<Int>) -> [CalendarSpec] {
        if weekdays.isEmpty {
            return [CalendarSpec(weekday: nil, hour: hour, minute: minute)]
        }
        return weekdays.sorted().map { weekday in
            CalendarSpec(weekday: weekday, hour: hour, minute: minute)
        }
    }

    private func isSameEditableState(lhs: ScheduleDraft, rhs: ScheduleDraft) -> Bool {
        lhs.label == rhs.label
            && lhs.runAtLoad == rhs.runAtLoad
            && lhs.mode == rhs.mode
            && lhs.hour == rhs.hour
            && lhs.minute == rhs.minute
            && lhs.weekdays == rhs.weekdays
            && lhs.intervalSeconds == rhs.intervalSeconds
    }

    private func syncIntervalControlsFromDraft() {
        let seconds = max(60, draft.intervalSeconds)

        if seconds % IntervalUnit.days.secondsMultiplier == 0 {
            intervalUnit = .days
            intervalValue = max(1, seconds / IntervalUnit.days.secondsMultiplier)
            return
        }

        if seconds % IntervalUnit.hours.secondsMultiplier == 0 {
            intervalUnit = .hours
            intervalValue = max(1, seconds / IntervalUnit.hours.secondsMultiplier)
            return
        }

        intervalUnit = .minutes
        intervalValue = max(1, seconds / IntervalUnit.minutes.secondsMultiplier)
    }

    private func syncIntervalIntoDraftIfNeeded() {
        guard !isSyncingDerivedControls else { return }
        let safeValue = max(1, intervalValue)
        if safeValue != intervalValue {
            intervalValue = safeValue
        }
        draft.intervalSeconds = safeValue * intervalUnit.secondsMultiplier
    }

    private func syncCalendarIntoDraftIfNeeded() {
        guard !isSyncingDerivedControls else { return }
        let components = Calendar.current.dateComponents([.hour, .minute], from: calendarTime)
        draft.hour = components.hour ?? draft.hour
        draft.minute = components.minute ?? draft.minute
    }

    private func makeDate(hour: Int, minute: Int) -> Date {
        let now = Date()
        let calendar = Calendar.current
        let current = calendar.dateComponents([.year, .month, .day], from: now)
        var withTime = DateComponents()
        withTime.year = current.year
        withTime.month = current.month
        withTime.day = current.day
        withTime.hour = hour
        withTime.minute = minute
        withTime.second = 0
        return calendar.date(from: withTime) ?? now
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
