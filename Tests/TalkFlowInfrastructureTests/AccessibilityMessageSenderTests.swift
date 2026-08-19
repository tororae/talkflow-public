import Foundation
import Testing
import TalkFlowDomain
@testable import TalkFlowInfrastructure

/// These ask the interlock directly rather than through `send`.
///
/// Just past that decision `send` queries KakaoTalk's accessibility tree, and a
/// test that reaches a live application's windows hangs whenever that application
/// is busy. It hung this suite once, while TalkFlow was delivering.
private struct IdleMonitor: SystemActivityMonitor {
    let idleSeconds: TimeInterval

    func snapshot() -> SystemActivitySnapshot {
        SystemActivitySnapshot(idleSeconds: idleSeconds, screenLocked: false)
    }
}

private struct FixedScreenPresence: ScreenPresenceReading {
    let visible: Bool

    func hasVisibleScreen() -> Bool { visible }
}

private struct FixedFrontmost: FrontmostApplicationReading {
    let kakaoTalk: Bool

    func isKakaoTalkFrontmost() -> Bool { kakaoTalk }
}

/// KakaoTalk frontmost and somebody typing: the only arrangement in which the
/// interlock has anything to protect, so the default a test starts from.
private func sender(
    idleSeconds: TimeInterval = 0,
    screenVisible: Bool = true,
    kakaoTalkFrontmost: Bool = true
) -> AccessibilityMessageSender {
    AccessibilityMessageSender(
        activity: IdleMonitor(idleSeconds: idleSeconds),
        screenPresence: FixedScreenPresence(visible: screenVisible),
        frontmost: FixedFrontmost(kakaoTalk: kakaoTalkFrontmost)
    )
}

/// The accident this rule exists for: a search term typed into KakaoTalk's own
/// field arrived in a chat and was sent. It needs KakaoTalk to be the app
/// receiving the keystrokes, and here it is.
@Test
func anAutomaticSendWaitsWhileSomebodyTypesIntoKakaoTalk() {
    #expect(!sender().mayTakeTheKeyboard(.automatic))
}

/// Typing into a different application is not a reason to hold a message back.
/// Idle time is machine-wide, and reading it as "somebody might be typing into
/// KakaoTalk" held a real draft for three and a half minutes while the frontmost
/// application was a text editor. Nothing on this path can reach that keyboard:
/// the focus moves happen inside KakaoTalk's own tree and Return is posted to its
/// process rather than into the global event stream.
@Test
func typingInAnotherApplicationDoesNotHoldAnAutomaticSend() {
    #expect(sender(kakaoTalkFrontmost: false).mayTakeTheKeyboard(.automatic))
}

/// Pressing 보내기 *is* a keystroke, so the gap this rule measures is never
/// satisfied on the path where a person asked. It refused the one send it had no
/// business refusing — and `.keyboardInUse` is the single refusal not allowed to
/// fall back to katok, so the button produced an error rather than a message.
@Test
func aSendThePersonAskedForIsNotHeldBackByTheirOwnKeystroke() {
    #expect(sender().mayTakeTheKeyboard(.userRequested))
}

/// Behind a shut lid there is nobody to interrupt, and that is the case the
/// direct sender exists for. Unchanged by everything above.
@Test
func anAutomaticSendBehindAShutLidDoesNotWait() {
    #expect(sender(screenVisible: false).mayTakeTheKeyboard(.automatic))
}

/// Once the typing stops the gate opens on its own, which is what makes it a
/// wait rather than a refusal.
@Test
func theGateOpensOnceTheKeyboardHasBeenIdleLongEnough() {
    #expect(sender(idleSeconds: 30).mayTakeTheKeyboard(.automatic))
}
