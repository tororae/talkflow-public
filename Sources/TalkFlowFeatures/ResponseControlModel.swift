import Observation
import TalkFlowApplication
import TalkFlowDomain

/// Owns the global on/off state. Every screen and the menu bar change it through
/// here, and the value is written to disk so a paused app stays paused across
/// relaunches instead of quietly resuming.
///
/// Arming also holds the Mac awake. Sending needs an unlocked session, and the
/// session locks about a second after the display sleeps, so an app that only
/// promised to reply would otherwise go quiet the moment the user stepped away.
@MainActor
@Observable
public final class ResponseControlModel {
    public private(set) var isEnabled = false

    private let settings: ManageAppSettings
    private let wakefulness: (any WakefulnessController)?

    public init(settings: ManageAppSettings, wakefulness: (any WakefulnessController)? = nil) {
        self.settings = settings
        self.wakefulness = wakefulness
    }

    public func load() async {
        isEnabled = (try? await settings.globalResponsesEnabled()) ?? false
        await wakefulness?.setArmed(isEnabled)
    }

    public func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        Task {
            try? await settings.setGlobalResponsesEnabled(enabled)
            await wakefulness?.setArmed(enabled)
        }
    }

    /// The emergency stop is the same switch, named for what it is used for.
    /// Turning off also releases the power assertions, which is what lets the
    /// Mac sleep again before it goes in a bag.
    public func stopEverything() {
        setEnabled(false)
    }
}
