import Foundation
import SwiftUI

@MainActor
final class SchedulesViewModel: ObservableObject {
    @Published var draft = ScheduleDraft() {
        didSet { stateStore.scheduleDraft = draft }
    }
    @Published var scheduledAgents: [ScheduledAgent] = []
    @Published var selectedScheduledAgentID: ScheduledAgent.ID? {
        didSet {
            stateStore.scheduledAgentID = selectedScheduledAgentID
            loadSelectedAgentIntoBuilder()
        }
    }
    @Published var sortOrder: [KeyPathComparator<ScheduledAgent>] = [
        .init(\ScheduledAgent.label, order: .forward)
    ] {
        didSet { scheduledAgents.sort(using: sortOrder) }
    }
    @Published var searchText = "" {
        didSet { stateStore.schedulesSearchText = searchText }
    }
    @Published var filter: SchedulesFilter = .all {
        didSet { stateStore.schedulesFilter = filter }
    }
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
    private let stateStore: LaunchDeckStateStore
    private var isSyncingBuilderFromSelection = false
    private var isSyncingDerivedControls = false
    private var loadedDraftSnapshot: ScheduleDraft?

    init(
        service: LaunchctlService,
        parser: LaunchAgentParser = LaunchAgentParser(),
        writer: LaunchAgentWriter = LaunchAgentWriter(),
        launchCtl: LaunchCtlService = LaunchCtlService(),
        stateStore: LaunchDeckStateStore
    ) {
        _ = service
        self.parser = parser
        self.writer = writer
        self.launchCtl = launchCtl
        self.stateStore = stateStore
        draft = stateStore.scheduleDraft
        selectedScheduledAgentID = stateStore.scheduledAgentID
        searchText = stateStore.schedulesSearchText
        filter = stateStore.schedulesFilter
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
            statusMessage = "Loaded \(agents.count) scheduled agents"

            if let selectedScheduledAgentID,
               scheduledAgents.contains(where: { $0.id == selectedScheduledAgentID }) == false {
                self.selectedScheduledAgentID = nil
            } else if loadedDraftSnapshot == nil {
                loadSelectedAgentIntoBuilder()
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func applyChanges() {
        guard let selectedAgent else {
            errorMessage = "Select a scheduled agent to continue"
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
                errorMessage = "Could not parse plist at \(selectedAgent.fileURL.path)"
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
            && lhs.commandPath == rhs.commandPath
            && lhs.arguments == rhs.arguments
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
