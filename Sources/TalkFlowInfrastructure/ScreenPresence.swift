import CoreGraphics
import Foundation

/// Whether there is a screen for a send to interrupt.
///
/// Driving KakaoTalk's interface can mean bringing it forward. Whether that is
/// rude or free depends entirely on whether anyone can see it happen, and that
/// is not something the send rules can infer from idle time: a shut laptop on a
/// desk reports the same keyboard idleness as one being typed on a second ago.
protocol ScreenPresenceReading: Sendable {
    func hasVisibleScreen() -> Bool
}

struct MacScreenPresence: ScreenPresenceReading {
    private let lidState: any LidStateReading

    init(lidState: any LidStateReading = IOKitLidState()) {
        self.lidState = lidState
    }

    /// Measured behaviour, and the reason this reads the lid rather than the
    /// display: behind a shut lid `CGDisplayIsAsleep` still answers "awake" and
    /// the active-display list still counts the built-in panel, because
    /// TalkFlow's own assertion is what holds the display logically on. Reading
    /// either of them as "lid" has been wrong every time it was tried.
    func hasVisibleScreen() -> Bool {
        guard lidState.isLidClosed() else { return true }
        return Self.hasActiveExternalDisplay()
    }

    /// A shut lid still leaves something to interrupt when an external display
    /// is driving the desktop — that is what clamshell mode is.
    private static func hasActiveExternalDisplay() -> Bool {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return false }

        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return false }

        return ids.prefix(Int(count)).contains { CGDisplayIsBuiltin($0) == 0 }
    }
}
