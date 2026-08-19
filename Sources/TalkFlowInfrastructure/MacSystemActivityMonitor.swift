import CoreGraphics
import Foundation
import TalkFlowDomain

/// Reads the macOS state the send rules depend on.
///
/// Both signals come from public APIs that need no permission prompt, so a user
/// who only wants drafts never has to grant anything for this.
public struct MacSystemActivityMonitor: SystemActivityMonitor {
    public init() {}

    public func snapshot() -> SystemActivitySnapshot {
        SystemActivitySnapshot(
            idleSeconds: Self.idleSeconds(),
            screenLocked: Self.screenIsLocked()
        )
    }

    /// Seconds since the last keyboard or mouse event of any kind.
    private static func idleSeconds() -> TimeInterval {
        CGEventSource.secondsSinceLastEventType(
            .hidSystemState,
            eventType: CGEventType(rawValue: ~0)!
        )
    }

    private static func screenIsLocked() -> Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return session["CGSSessionScreenIsLocked"] as? Bool ?? false
    }
}
