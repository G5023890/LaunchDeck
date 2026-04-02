import Foundation

@MainActor
final class LaunchDeckStateStore {
    static let shared = LaunchDeckStateStore()

    private let defaults: UserDefaults
    private let key = "LaunchDeck.AppState.v1"
    private var state: LaunchDeckAppState

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode(LaunchDeckAppState.self, from: data) {
            state = decoded
        } else {
            state = LaunchDeckAppState()
        }
    }

    var selectedSection: SidebarSection {
        get { state.selectedSection }
        set { update { $0.selectedSection = newValue } }
    }

    var selectedProcessID: Int? {
        get { state.selectedProcessID }
        set { update { $0.selectedProcessID = newValue } }
    }

    var isLiveRefreshEnabled: Bool {
        get { state.isLiveRefreshEnabled }
        set { update { $0.isLiveRefreshEnabled = newValue } }
    }

    var selectedJobID: String? {
        get { state.selectedJobID }
        set { update { $0.selectedJobID = newValue } }
    }

    var launchServicesFilterText: String {
        get { state.launchServicesFilterText }
        set { update { $0.launchServicesFilterText = newValue } }
    }

    var launchServicesStatusFilter: LaunchServicesStatusFilter {
        get { state.launchServicesStatusFilter }
        set { update { $0.launchServicesStatusFilter = newValue } }
    }

    var launchServicesSortOption: LaunchServicesSortOption {
        get { state.launchServicesSortOption }
        set { update { $0.launchServicesSortOption = newValue } }
    }

    var launchServicesExpandedGroups: Set<LaunchServicesGroup> {
        get { state.launchServicesExpandedGroups }
        set { update { $0.launchServicesExpandedGroups = newValue } }
    }

    var scheduledAgentID: String? {
        get { state.scheduledAgentID }
        set { update { $0.scheduledAgentID = newValue } }
    }

    var schedulesSearchText: String {
        get { state.schedulesSearchText }
        set { update { $0.schedulesSearchText = newValue } }
    }

    var schedulesFilter: SchedulesFilter {
        get { state.schedulesFilter }
        set { update { $0.schedulesFilter = newValue } }
    }

    var scheduleDraft: ScheduleDraft {
        get { state.scheduleDraft }
        set { update { $0.scheduleDraft = newValue } }
    }

    private func update(_ mutate: (inout LaunchDeckAppState) -> Void) {
        mutate(&state)
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: key)
    }
}

struct LaunchDeckAppState: Codable {
    var selectedSection: SidebarSection = .processes
    var selectedProcessID: Int?
    var isLiveRefreshEnabled: Bool = false

    var selectedJobID: String?
    var launchServicesFilterText: String = ""
    var launchServicesStatusFilter: LaunchServicesStatusFilter = .all
    var launchServicesSortOption: LaunchServicesSortOption = .label
    var launchServicesExpandedGroups: Set<LaunchServicesGroup> = Set(LaunchServicesGroup.allCases)

    var scheduledAgentID: String?
    var schedulesSearchText: String = ""
    var schedulesFilter: SchedulesFilter = .all
    var scheduleDraft: ScheduleDraft = ScheduleDraft()
}
