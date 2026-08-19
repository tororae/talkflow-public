import Foundation
import IOKit.pwr_mgt
import TalkFlowDomain

/// Wakes the display by declaring user activity, the same way an input device
/// does. Measured behaviour: the screen comes back and the session reports
/// unlocked within about a second, after which UI automation can target
/// KakaoTalk. Once macOS starts demanding a password the screen stays locked and
/// the caller keeps waiting instead.
public struct MacDisplayWaker: DisplayWaker {
    /// How long to let the screen settle before reading the session state again.
    private let settleDelay: Duration

    public init(settleDelay: Duration = .seconds(2)) {
        self.settleDelay = settleDelay
    }

    public func wake() async {
        var assertionID: IOPMAssertionID = 0
        IOPMAssertionDeclareUserActivity(
            "TalkFlow가 대기 중인 메시지를 전송합니다" as CFString,
            kIOPMUserActiveLocal,
            &assertionID
        )
        try? await Task.sleep(for: settleDelay)
    }
}
