import AppKit
import ApplicationServices
import Foundation
import TalkFlowDomain

/// Types into KakaoTalk directly instead of driving it from the outside.
///
/// katok sends by posting a global Return, which lands on whatever owns the
/// front — so it has to bring KakaoTalk forward first, and behind a shut lid
/// there is no front for it to become. Measured with the lid down: the room
/// opens, the text goes in, and the Return goes nowhere.
///
/// This path fills the room's compose box and presses the room's own 전송
/// button, both through the accessibility tree. Every step names the window it
/// acts on, so none of them needs the front, the keyboard, or KakaoTalk's
/// attention: verified sending with the lid shut while Finder stayed frontmost
/// throughout.
///
/// Naming the window is also what keeps a message in the room it was written
/// for. This used to press Return by posting a key event to KakaoTalk's process,
/// which is addressed to the app and not to a window, so KakaoTalk delivered it
/// to whichever room the user last touched. See `type` for what that cost.
///
/// It is narrow on purpose, and most of that is not caution about tidiness. It
/// refuses whenever it cannot prove which window it is typing into, whenever the
/// box holds something a person wrote, and whenever a person is using the
/// keyboard it is about to take. Sending is not undoable and the words go out
/// under the user's name; every one of those refusals is a message that would
/// otherwise have been theirs to answer for.
///
/// Refusals are retryable, so the caller falls back to katok, which can also
/// open a closed room.
public struct AccessibilityMessageSender: MessageSender {
    private let activity: any SystemActivityMonitor
    private let screenPresence: any ScreenPresenceReading
    private let frontmost: any FrontmostApplicationReading

    public init(activity: any SystemActivityMonitor = MacSystemActivityMonitor()) {
        self.init(activity: activity, screenPresence: MacScreenPresence())
    }

    init(
        activity: any SystemActivityMonitor,
        screenPresence: any ScreenPresenceReading,
        frontmost: any FrontmostApplicationReading = WorkspaceFrontmostApplication()
    ) {
        self.activity = activity
        self.screenPresence = screenPresence
        self.frontmost = frontmost
    }

    public func send(
        text: String,
        toChatRoomID chatRoomID: String,
        named chatRoomName: String,
        origin: SendOrigin
    ) async throws -> SendReceipt {
        let name = chatRoomName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else {
            throw MessageSendFailure(message: "채팅방 이름을 몰라 창을 찾을 수 없습니다.", isRetryable: true)
        }
        guard mayTakeTheKeyboard(origin) else {
            throw MessageSendFailure(
                message: "지금 키보드를 쓰고 있어 전송을 미룹니다.",
                isRetryable: true,
                cause: .keyboardInUse
            )
        }

        try await Task.detached { try Self.type(text, intoWindowTitled: name) }.value
        return SendReceipt(route: .direct)
    }

    /// Typing into another application's window means moving its keyboard focus
    /// to the box we are about to fill. Do that while someone is using that
    /// keyboard and the keystrokes they are in the middle of land in a
    /// conversation instead of wherever they were aiming — a search term typed
    /// into KakaoTalk's own search field arrived in a chat and was sent. Nothing
    /// this feature does is worth putting words in someone's mouth.
    ///
    /// Behind a shut lid there is no one to interrupt, and that is the case the
    /// direct path exists for.
    ///
    /// So is a person pressing 보내기, and that one used to be refused. The gap
    /// asks "is somebody in the middle of typing something else" and reads a
    /// fresh keystroke as yes — but the freshest keystroke of all is the one that
    /// asked for this send. The app told itself as much: `ReviewDrafts.send` says
    /// the idle checks do not apply because the user is present by definition,
    /// and then this layer applied one anyway. Worse than refusing: `.keyboardInUse`
    /// is the one refusal that is not allowed to fall back to katok, so pressing
    /// the button produced an error instead of a message.
    ///
    /// And so is somebody typing in another application, which is what this
    /// used to refuse. Idle time is machine-wide: a keystroke aimed at a browser
    /// counted as a reason not to type into KakaoTalk, and in a session where
    /// the user works at the keyboard that is nearly always true. Measured on
    /// this Mac: a draft written at 10:10:04 sat for three and a half minutes
    /// with 「지금 키보드를 쓰고 있어 전송을 미룹니다」 while the frontmost app was
    /// a text editor.
    ///
    /// Nothing about this path can reach that keyboard. It posts no key events
    /// and moves nobody's focus: the box is filled and the button is pressed
    /// through the accessibility tree, on elements belonging to the one window.
    /// The accident this rule exists for — a search term typed into KakaoTalk's
    /// own field arriving in a chat — needs KakaoTalk to be the app receiving the
    /// keystrokes. So that is what is asked, and the gate is kept even though the
    /// path beneath it no longer types, because a room whose window is filled in
    /// under someone's hands is still a room they are in the middle of using.
    ///
    /// Internal so a test can ask it directly. Reaching it through `send` means
    /// reaching the live accessibility tree just past it, and a test that queries
    /// another running application's windows hangs whenever that application is
    /// busy — which, while TalkFlow is delivering, it is.
    func mayTakeTheKeyboard(_ origin: SendOrigin) -> Bool {
        guard origin == .automatic else { return true }
        guard screenPresence.hasVisibleScreen() else { return true }
        guard frontmost.isKakaoTalkFrontmost() else { return true }
        return activity.snapshot().idleSeconds >= Self.requiredKeyboardGap
    }

    private static func type(_ text: String, intoWindowTitled name: String) throws {
        let window = try chatWindow(titled: name)
        guard let box = composeBox(in: window) else {
            throw MessageSendFailure(message: "\(name) 창에서 입력란을 찾지 못했습니다.", isRetryable: true)
        }
        // The room's own 전송 button, and the reason this path stopped pressing
        // Return. A key event posted to the process is delivered to whichever
        // window KakaoTalk considers key, which is the room the user last
        // touched — not the room being written to. Measured 2026-08-10 with nine
        // windows open: the target room sat at `AXMain=false` while the app's
        // `AXFocusedWindow` was another room, and every send into the target
        // failed while sends into that other room went through. Setting AX focus
        // on this box does not move the app's key window, so there was nothing
        // in the target room for Return to land on.
        //
        // Worse than not sending: the Return still landed somewhere. It went to
        // another room's compose box, and had the user left half a sentence
        // sitting in one, that is what would have been sent under their name.
        //
        // A button press is addressed to the window that owns the button, so it
        // cannot arrive in the wrong conversation, and it needs neither the
        // keyboard nor the front.
        guard let sendButton = sendButton(in: window) else {
            throw MessageSendFailure(message: "\(name) 창에서 전송 버튼을 찾지 못했습니다.", isRetryable: true)
        }

        // Whatever is already in the box is something the user typed and has not
        // sent yet. Overwriting it would destroy their message and send ours in
        // its place.
        let existing = (value(box, kAXValueAttribute) as? String) ?? ""
        guard existing.isEmpty else {
            throw MessageSendFailure(message: "입력란에 작성 중인 내용이 있습니다.", isRetryable: true)
        }

        // Nobody's focus is touched. Filling the box and pressing the button both
        // work on elements inside this window, so the keyboard stays wherever the
        // user left it — including inside KakaoTalk. This used to move focus onto
        // the compose box and put it back afterwards, which was only ever needed
        // to give a posted Return somewhere to land.
        guard AXUIElementSetAttributeValue(box, kAXValueAttribute as CFString, text as CFString) == .success
        else {
            throw MessageSendFailure(message: "입력란에 글자를 넣지 못했습니다.", isRetryable: true)
        }

        // Writing the value and KakaoTalk noticing it are not the same moment.
        // Measured on this Mac: the box reads back the new text immediately, but
        // 전송 stays disabled for around three tenths of a second and only then
        // turns on. Committing before that is committing an empty message —
        // which is what the old Return did, sixty milliseconds after the write.
        //
        // So the button's own enabled state is the go-ahead, and waiting for it
        // beats any fixed pause: it is KakaoTalk saying it has the text, rather
        // than us guessing how long it needs. A button that never turns on means
        // the text never arrived, and pressing then would send nothing at all.
        guard Self.waitForSendToBeOffered(sendButton) else {
            AXUIElementSetAttributeValue(box, kAXValueAttribute as CFString, "" as CFString)
            throw MessageSendFailure(message: "카카오톡이 입력한 내용을 받지 않았습니다.", isRetryable: true)
        }

        // Read back here and not a line earlier. Someone can type into the box
        // while KakaoTalk is taking the text, and 전송 does not ask what it is
        // sending — it would deliver their half-finished words as ours. The
        // check belongs against the moment of the press, so it is the last thing
        // done before it.
        let staged = (value(box, kAXValueAttribute) as? String) ?? ""
        guard staged == text else {
            AXUIElementSetAttributeValue(box, kAXValueAttribute as CFString, "" as CFString)
            throw MessageSendFailure(message: "입력란이 도중에 바뀌어 보내지 않았습니다.", isRetryable: true)
        }

        // The result is deliberately discarded, and this is the one line here
        // that must not be tidied into a `guard`. KakaoTalk answers a press that
        // delivered with `kAXErrorFailure`: verified 2026-08-10 by pressing 전송
        // in a room that was not the key window, getting -25200 back, and finding
        // the message in the archive a second later.
        //
        // Believing that code would mark every successful send a failure, and a
        // retryable one, so the queue would hand the same message to katok and
        // the room would get it twice. Nothing the press returns is evidence
        // either way; the box emptying is, and that is what is checked below.
        _ = AXUIElementPerformAction(sendButton, kAXPressAction as CFString)

        // KakaoTalk empties the box when it accepts the message, so the box is
        // the receipt. Anything left behind was not sent, and is cleared rather
        // than left sitting in the conversation for the user to find later.
        //
        // Watched rather than waited out. A single fixed grace has to be either
        // too short or too slow, and it was too short: measured on this Mac,
        // 「카카오톡이 Enter를 받지 않았습니다」 was the reason this path handed
        // over to katok, which then redid the whole send for nine to
        // twenty-two seconds. Being wrong that way costs ten times what being
        // patient does, so the receipt is checked every fraction of a second and
        // a KakaoTalk that answers late still counts as having answered.
        guard Self.waitForBoxToEmpty(box) else {
            AXUIElementSetAttributeValue(box, kAXValueAttribute as CFString, "" as CFString)
            throw MessageSendFailure(message: "카카오톡이 전송을 받지 않았습니다.", isRetryable: true)
        }
    }

    /// Two seconds of no keyboard or mouse. Short enough that a reply still
    /// feels immediate, long enough that it never lands inside someone's
    /// sentence.
    private static let requiredKeyboardGap: TimeInterval = 2
}
