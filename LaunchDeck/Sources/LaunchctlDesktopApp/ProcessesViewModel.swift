import AppKit
import Foundation
import SwiftUI

@MainActor
final class ProcessesViewModel: ObservableObject {
    @Published var processes: [RunningProcess] = []
    @Published var selectedProcessID: RunningProcess.ID? {
        didSet { stateStore.selectedProcessID = selectedProcessID }
    }
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
    private let stateStore: LaunchDeckStateStore
    private var liveRefreshTask: Task<Void, Never>?

    init(service: LaunchctlService, stateStore: LaunchDeckStateStore) {
        self.service = service
        self.stateStore = stateStore
        selectedProcessID = stateStore.selectedProcessID
        isLiveRefresh = stateStore.isLiveRefreshEnabled
        if isLiveRefresh {
            configureLiveRefresh()
        }
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
            statusMessage = "Updated at \(Date().formatted(date: .omitted, time: .standard))"
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func killSelected(force: Bool) {
        guard let selected = selectedProcess else {
            errorMessage = "Select a process to continue"
            return
        }
        kill(selected, force: force)
    }

    func kill(_ process: RunningProcess, force: Bool) {
        selectedProcessID = process.id

        Task {
            do {
                try await service.killProcess(pid: process.pid, force: force)
                statusMessage = force ? "Force killed PID \(process.pid)" : "Sent terminate signal to PID \(process.pid)"
                await refreshAsync()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func revealSelectedBinary() {
        guard let selected = selectedProcess else {
            errorMessage = "Select a process to continue"
            return
        }
        revealBinary(for: selected)
    }

    func revealBinary(for process: RunningProcess) {
        selectedProcessID = process.id

        guard let path = process.binaryPath else {
            errorMessage = "This command does not point to a local executable"
            return
        }

        Task {
            do {
                try await service.revealBinary(path: path)
                statusMessage = "Revealed in Finder"
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func copyPID(_ process: RunningProcess) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(String(process.pid), forType: .string)
        statusMessage = "Copied PID to clipboard"
    }

    func copyFullPath(_ process: RunningProcess) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(process.displayPath, forType: .string)
        statusMessage = "Copied full path to clipboard"
    }

    func isProcessAlive(_ process: RunningProcess) -> Bool {
        processes.contains(where: { $0.id == process.id })
    }

    private func configureLiveRefresh() {
        stateStore.isLiveRefreshEnabled = isLiveRefresh
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
