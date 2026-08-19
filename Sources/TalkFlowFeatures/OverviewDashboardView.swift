import SwiftUI

struct OverviewDashboardView: View {
    private let models: TalkFlowModels

    init(models: TalkFlowModels) {
        self.models = models
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("TalkFlow").font(.largeTitle.bold())
                HStack(spacing: 12) {
                    ConnectionStatusView(loadStatus: models.loadStatus)
                    AIConnectionView(model: models.aiConnection)
                }
                .frame(height: 150)

                responseControl
                SyncActivityView(model: models.syncActivity)
                SendQueueView(
                    model: models.sendQueue,
                    usePolicyAccepted: models.settings.sendUsePolicyAccepted
                )
                PermissionCenterView()
            }
            .padding(24)
        }
        .navigationTitle("개요")
        .task {
            await models.responseControl.load()
            await models.settings.loadIfNeeded()
            models.syncActivity.startObserving()
            models.sendQueue.start()
            // The sidebar's 활동 badge is how the user learns drafts are
            // waiting, and this is the screen the app opens on. Left to the
            // 활동 화면's own load it would only appear after the visit it
            // exists to prompt.
            await models.timeline.reload()
        }
    }

    private var responseControl: some View {
        GroupBox("자동 응답") {
            HStack {
                VStack(alignment: .leading) {
                    Text(models.responseControl.isEnabled ? "응답이 켜져 있습니다" : "응답이 일시 중지되어 있습니다")
                    Text("채팅방별 정책은 ‘채팅방’에서 관리합니다.")
                        .foregroundStyle(.secondary)
                    if let shortcut = models.stopShortcutName {
                        Text("어디서든 \(shortcut) 로 즉시 중지")
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer()
                Toggle("자동 응답", isOn: Binding(
                    get: { models.responseControl.isEnabled },
                    set: { models.responseControl.setEnabled($0) }
                ))
                .labelsHidden()
                Button("긴급 중지", role: .destructive) {
                    models.responseControl.stopEverything()
                }
            }
        }
    }
}
