import Foundation
import Testing
import TalkFlowDomain
@testable import TalkFlowInfrastructure

private struct StubLid: LidStateReading {
    let closed: Bool

    func isLidClosed() -> Bool { closed }
}

/// Behind a shut lid the accessibility window list comes back empty, so katok
/// has to open the room, and it refuses to do that while it is waiting for a gap
/// in typing. Closing a laptop stopped delivery entirely because of it.
@Test
func aSendWithNoScreenToInterruptTakesFocusImmediately() {
    let arguments = KatokMessageSender.arguments(chatRoomID: "42", origin: .automatic)

    #expect(arguments.contains("--take-focus-now"))
    #expect(!arguments.contains("--focus-wait"))
}

/// Waiting for a gap in typing was tried with someone in front of a screen and
/// was worse than not waiting. The wait ends in a refusal, the refusal is
/// retryable, and every retry brings KakaoTalk forward again — so one polite
/// interruption became three, spread over ten seconds. One deliberate switch
/// interrupts less than three apologetic ones, and the stop hotkey is there for
/// anyone who disagrees in the moment.
@Test
func aSendSomeoneCouldSeeAlsoTakesFocusRatherThanInterruptingThreeTimes() {
    let arguments = KatokMessageSender.arguments(chatRoomID: "42", origin: .automatic)

    #expect(arguments.contains("--take-focus-now"))
    #expect(!arguments.contains("--focus-wait"))
}

/// Names are not unique and a name-based send can land in the wrong
/// conversation, so the room is always addressed by id.
@Test
func everySendAddressesTheRoomByIdAndCarriesTheAcceptedPolicy() {
    let arguments = KatokMessageSender.arguments(chatRoomID: "42", origin: .automatic)

    #expect(arguments.first == "send")
    #expect(!arguments.contains("--room"))
    #expect(arguments.contains("--chat"))
    #expect(arguments.contains("42"))
    #expect(arguments.contains("--accept-use-policy"))
}

/// An open lid is the one answer that needs no display reading at all, which is
/// what keeps this off the readings that have been wrong before: behind a shut
/// lid `CGDisplayIsAsleep` still answers "awake" and the active-display list
/// still counts the built-in panel.
@Test
func anOpenLidMeansThereIsAScreenToInterrupt() {
    let presence = MacScreenPresence(lidState: StubLid(closed: false))

    #expect(presence.hasVisibleScreen())
}

// MARK: - Telling a closed room apart from a passing screen state

/// The exact line katok prints for a room whose window is not open. It is
/// retryable — opening the conversation makes it work — but nothing the app does
/// will clear it, so it is the one failure a person has to be told about.
@Test
func aRoomMissingFromTheChatListIsReportedAsAClosedWindow() {
    let failure = KatokMessageSender.failure(from: "Error: 'hangyeol' is not in the chat list")

    #expect(failure.isRetryable)
    #expect(failure.cause == .roomWindowClosed)
    #expect(failure.needsUserAction)
    #expect(failure.explanation.contains("대화창을 열어두어야"))
}

/// Everything else keeps the connector's own words. A screen state that passes
/// on its own is not something to send somebody looking for a window to open.
@Test
func aPassingScreenStateIsNotBlamedOnAClosedWindow() {
    let failure = KatokMessageSender.failure(from: "KakaoTalk is not frontmost; retry")

    #expect(failure.isRetryable)
    #expect(failure.cause == .unspecified)
    #expect(!failure.needsUserAction)
    #expect(failure.explanation == failure.message)
}

// MARK: - Choosing between the two ways of sending

private actor RecordingSender: MessageSender {
    private(set) var calls: [String] = []
    private let failure: Error?
    private let route: SendReceipt.Route

    init(failure: Error? = nil, route: SendReceipt.Route = .direct) {
        self.failure = failure
        self.route = route
    }

    func send(
        text: String,
        toChatRoomID chatRoomID: String,
        named chatRoomName: String,
        origin: SendOrigin
    ) async throws -> SendReceipt {
        calls.append(text)
        if let failure { throw failure }
        return SendReceipt(route: route)
    }
}

/// Typing straight into the window takes no focus and is the only thing that
/// works behind a shut lid, so it is tried first and katok is never woken.
@Test
func katokIsNotRunWhenTypingDirectlyWorked() async throws {
    let direct = RecordingSender()
    let katok = RecordingSender()

    try await AccessibilityFirstMessageSender(direct: direct, fallback: katok)
        .send(text: "네", toChatRoomID: "42", named: "가족", origin: .automatic)

    #expect(await direct.calls == ["네"])
    #expect(await katok.calls.isEmpty)
}

/// The direct path refuses whenever it cannot prove which window it is typing
/// into — a closed room, or a name shared by two of them. katok can open a room,
/// so a refusal is a handover rather than a failure.
@Test
func aRefusalToTypeDirectlyHandsTheMessageToKatok() async throws {
    let direct = RecordingSender(
        failure: MessageSendFailure(message: "창이 열려 있지 않습니다.", isRetryable: true)
    )
    let katok = RecordingSender()

    try await AccessibilityFirstMessageSender(direct: direct, fallback: katok)
        .send(text: "네", toChatRoomID: "42", named: "가족", origin: .automatic)

    #expect(await katok.calls == ["네"])
}

/// A terminal failure is terminal for both. Handing it on would only produce the
/// same answer from a second tool.
@Test
func aTerminalFailureIsNotRetriedThroughKatok() async {
    let katok = RecordingSender()
    let sender = AccessibilityFirstMessageSender(
        direct: RecordingSender(failure: MessageSendFailure(message: "동의 필요", isRetryable: false)),
        fallback: katok
    )

    await #expect(throws: MessageSendFailure.self) {
        try await sender.send(text: "네", toChatRoomID: "42", named: "가족", origin: .automatic)
    }
    #expect(await katok.calls.isEmpty)
}

// MARK: - Not typing over a person

private struct StubScreen: ScreenPresenceReading {
    let visible: Bool

    func hasVisibleScreen() -> Bool { visible }
}

private struct StubActivity: SystemActivityMonitor {
    let idleSeconds: TimeInterval

    func snapshot() -> SystemActivitySnapshot {
        SystemActivitySnapshot(idleSeconds: idleSeconds, screenLocked: false)
    }
}

/// Filling a box in another application moves that application's keyboard focus
/// onto it. Doing that mid-keystroke put a search term the user was typing into
/// a conversation and sent it. Nothing here is worth putting words in someone's
/// mouth, so it waits for their hands to stop.
@Test
func nothingIsTypedIntoKakaoTalkWhileSomeoneIsUsingTheKeyboard() async {
    let sender = AccessibilityMessageSender(
        activity: StubActivity(idleSeconds: 0),
        screenPresence: StubScreen(visible: true)
    )

    await #expect(throws: MessageSendFailure.self) {
        try await sender.send(text: "네", toChatRoomID: "42", named: "가족", origin: .automatic)
    }
}

/// The refusal is retryable, not terminal: hands stop moving a moment later and
/// the reply should still go.
@Test
func waitingForTheKeyboardIsRetryableSoTheReplyIsNotLost() async {
    let sender = AccessibilityMessageSender(
        activity: StubActivity(idleSeconds: 0),
        screenPresence: StubScreen(visible: true)
    )

    do {
        try await sender.send(text: "네", toChatRoomID: "42", named: "가족", origin: .automatic)
        Issue.record("전송이 거부되지 않았습니다.")
    } catch let failure as MessageSendFailure {
        #expect(failure.isRetryable)
    } catch {
        Issue.record("예상과 다른 오류: \(error)")
    }
}

/// Behind a shut lid there is no one to interrupt, so the wait does not apply —
/// which matters because that is the one case only this path can serve.
@Test
func aShutLidNeedsNoKeyboardGapBecauseNobodyIsThere() async {
    let sender = AccessibilityMessageSender(
        activity: StubActivity(idleSeconds: 0),
        screenPresence: StubScreen(visible: false)
    )

    // Gets past the keyboard check and fails later, on a window that is not
    // there in a test environment — which is the point: a different refusal.
    do {
        try await sender.send(text: "네", toChatRoomID: "42", named: "존재하지 않는 방", origin: .automatic)
        Issue.record("테스트 환경에 그런 창이 있을 리 없습니다.")
    } catch let failure as MessageSendFailure {
        #expect(!failure.message.contains("키보드"))
    } catch {
        Issue.record("예상과 다른 오류: \(error)")
    }
}

/// The interlock was only ever on the direct path, so a refusal meaning "not
/// now" was read as "not this way" and the message was handed to katok, which
/// has no interlock at all. That is how a room name being typed into KakaoTalk's
/// search box landed in a conversation: the polite path declined and passed the
/// job to the one that would not.
@Test
func typingSomewhereElseIsNotHandedToKatok() async {
    let katok = RecordingSender()
    let sender = AccessibilityFirstMessageSender(
        direct: RecordingSender(
            failure: MessageSendFailure(
                message: "지금 키보드를 쓰고 있어 전송을 미룹니다.",
                isRetryable: true,
                cause: .keyboardInUse
            )
        ),
        fallback: katok
    )

    await #expect(throws: MessageSendFailure.self) {
        try await sender.send(text: "네", toChatRoomID: "42", named: "가족", origin: .automatic)
    }
    #expect(await katok.calls.isEmpty)
}

/// It stays retryable, so the reply waits for their hands to stop rather than
/// being dropped.
@Test
func waitingOutTheKeyboardKeepsTheReply() async {
    let sender = AccessibilityFirstMessageSender(
        direct: RecordingSender(
            failure: MessageSendFailure(message: "키보드 사용 중", isRetryable: true, cause: .keyboardInUse)
        ),
        fallback: RecordingSender()
    )

    do {
        try await sender.send(text: "네", toChatRoomID: "42", named: "가족", origin: .automatic)
        Issue.record("거절되지 않았습니다.")
    } catch let failure as MessageSendFailure {
        #expect(failure.isRetryable)
        #expect(!failure.allowsAnotherAttemptNow)
    } catch {
        Issue.record("예상과 다른 오류: \(error)")
    }
}

/// Every other refusal is still about the method, and katok can do things the
/// direct path cannot — opening a closed room among them.
@Test
func aRefusalAboutTheMethodStillReachesKatok() async throws {
    let katok = RecordingSender()
    let sender = AccessibilityFirstMessageSender(
        direct: RecordingSender(
            failure: MessageSendFailure(message: "창이 열려 있지 않습니다.", isRetryable: true)
        ),
        fallback: katok
    )

    try await sender.send(text: "네", toChatRoomID: "42", named: "가족", origin: .automatic)

    #expect(await katok.calls == ["네"])
}

/// Which way in a message actually took, on the record.
///
/// The two routes cost about ten times apart — typing into an open window is
/// about a second, driving KakaoTalk's interface to open a closed one is ten to
/// twenty — and without this a send that took twenty-three seconds looked exactly
/// like one that took one.
@Test
func aReceiptSaysWhichRouteDeliveredTheMessage() async throws {
    let direct = RecordingSender()

    let receipt = try await AccessibilityFirstMessageSender(direct: direct, fallback: RecordingSender())
        .send(text: "네", toChatRoomID: "42", named: "가족", origin: .automatic)

    #expect(receipt.route == .direct)
    #expect(receipt.fellBackBecause == nil)
}

/// And when the cheap route was not available, why. Measured on this Mac:
/// `katok send --list-windows` reported `open_windows: []`, so the direct path
/// refuses every time and every send pays for the expensive one.
@Test
func aReceiptSaysWhyTheDirectRouteWasNotUsed() async throws {
    let refused = RecordingSender(
        failure: MessageSendFailure(message: "이 데스크탑에 가족 창이 열려 있지 않습니다.", isRetryable: true)
    )

    let receipt = try await AccessibilityFirstMessageSender(
        direct: refused,
        fallback: RecordingSender(route: .katok)
    )
    .send(text: "네", toChatRoomID: "42", named: "가족", origin: .automatic)

    #expect(receipt.route == .katok)
    #expect(receipt.fellBackBecause == "이 데스크탑에 가족 창이 열려 있지 않습니다.")
    #expect(receipt.explanation.contains("katok"))
}

/// Opening a closed room posts a **global** Return, and a global event lands
/// wherever the focus is. When that was not where katok expected, the keystrokes
/// meant to open a room were typed as text: the room's own name appeared in a
/// chat window, nothing was sent, and KakaoTalk was left showing a dialog.
///
/// So a send the app decided on by itself refuses instead, and the draft waits
/// for a window that is already open.
@Test
func anAutomaticSendRefusesToOpenAClosedRoom() {
    let arguments = KatokMessageSender.arguments(chatRoomID: "42", origin: .automatic)

    #expect(arguments.contains("--no-open"))
}

/// A person pressing 보내기 gets the other answer. They are watching, they asked
/// for the message now, and a window moving is what they expect.
@Test
func aSendThePersonAskedForMayOpenTheRoom() {
    let arguments = KatokMessageSender.arguments(chatRoomID: "42", origin: .userRequested)

    #expect(!arguments.contains("--no-open"))
    #expect(arguments.contains("--take-focus-now"))
}
