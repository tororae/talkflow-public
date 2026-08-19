import SwiftUI
import TalkFlowApplication
import TalkFlowDomain
import TalkFlowFeatures
import TalkFlowInfrastructure

/// Claims the activation policy the app actually needs.
///
/// A Swift package builds a bare executable, not an app bundle, and macOS reads
/// one as a background-only process. Its windows still draw, which is what makes
/// this so hard to see: the settings form appears, a field takes a focus ring,
/// and every keystroke goes somewhere else, because a background-only app can
/// never own the key window. Saying `.regular` out loud makes a `swift run`
/// build behave the way the bundled app will.
final class TalkFlowLaunch: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

@main
struct TalkFlowApp: App {
    @NSApplicationDelegateAdaptor(TalkFlowLaunch.self) private var launch
    @State private var models = TalkFlowComposition.makeModels()

    var body: some Scene {
        WindowGroup {
            TalkFlowRootView(models: models)
        }

        MenuBarExtra("TalkFlow", systemImage: models.responseControl.isEnabled ? "bolt.fill" : "bolt.slash") {
            Toggle("자동 응답", isOn: Binding(
                get: { models.responseControl.isEnabled },
                set: { models.responseControl.setEnabled($0) }
            ))
            Divider()
            Text(models.responseControl.isEnabled ? "응답이 켜져 있습니다" : "응답이 일시 중지되어 있습니다")
            Button(models.stopShortcutName.map { "긴급 중지  \($0)" } ?? "긴급 중지") {
                models.responseControl.stopEverything()
            }
            Divider()
            Button("TalkFlow 종료") { NSApplication.shared.terminate(nil) }
        }
    }
}
