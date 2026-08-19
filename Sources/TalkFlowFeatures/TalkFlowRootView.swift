import SwiftUI

public struct TalkFlowRootView: View {
    private let models: TalkFlowModels
    @State private var selection: AppSection? = .overview

    public init(models: TalkFlowModels) {
        self.models = models
    }

    public var body: some View {
        NavigationSplitView {
            List(AppSection.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.symbolName)
                    .tag(section)
                    // Drafts wait in 활동 now, and a user on another screen had
                    // no way of knowing any were there. `badge` draws nothing
                    // at zero.
                    .badge(section == .activity ? models.timeline.pendingDraftCount : 0)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
            .navigationTitle("TalkFlow")
        } detail: {
            switch selection ?? .overview {
            case .overview:
                OverviewDashboardView(models: models)
            case .chatRooms:
                ChatRoomsManagementView(model: models.chatRooms, summaryModel: models.roomSummary)
            case .people:
                PeopleView(model: models.people)
            case .activity:
                ActivityTimelineView(model: models.timeline)
            case .settings:
                SettingsView(model: models.settings, adminRooms: models.admin)
            }
        }
        // Wide enough for the navigation sidebar plus the widest detail pane.
        // When the detail minimum leaves no room, macOS drops the sidebar
        // instead of shrinking the pane, and the app looks like it lost its
        // navigation.
        .frame(minWidth: 1000, minHeight: 640)
    }
}
