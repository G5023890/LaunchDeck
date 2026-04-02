import AppKit
import Foundation
import SwiftUI

@MainActor
final class LaunchServicesViewModel: ObservableObject {
    @Published var jobs: [LaunchServiceJob] = []
    @Published var selectedJobID: LaunchServiceJob.ID? {
        didSet { stateStore.selectedJobID = selectedJobID }
    }
    @Published var filterText = "" {
        didSet { stateStore.launchServicesFilterText = filterText }
    }
    @Published var statusFilter: LaunchServicesStatusFilter = .all {
        didSet { stateStore.launchServicesStatusFilter = statusFilter }
    }
    @Published var sortOption: LaunchServicesSortOption = .label {
        didSet { stateStore.launchServicesSortOption = sortOption }
    }
    @Published var expandedGroups: Set<LaunchServicesGroup> = Set(LaunchServicesGroup.allCases) {
        didSet { stateStore.launchServicesExpandedGroups = expandedGroups }
    }

    @Published var isLoading = false
    @Published var statusMessage = ""
    @Published var errorMessage = ""

    private let service: LaunchctlService
    private let scheduleParser = LaunchAgentParser()
    private let stateStore: LaunchDeckStateStore

    init(service: LaunchctlService, stateStore: LaunchDeckStateStore) {
        self.service = service
        self.stateStore = stateStore
        selectedJobID = stateStore.selectedJobID
        filterText = stateStore.launchServicesFilterText
        statusFilter = stateStore.launchServicesStatusFilter
        sortOption = stateStore.launchServicesSortOption
        expandedGroups = stateStore.launchServicesExpandedGroups
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

            statusMessage = "Loaded \(jobs.count) launch jobs"
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
        statusMessage = "Copied label to clipboard"
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
            errorMessage = "Select a launch service to continue"
            return
        }

        selectedJobID = job.id
        Task {
            do {
                try await action(job)
                statusMessage = "\(name) completed for \(job.label)"
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
