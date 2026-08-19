import AppKit
import ApplicationServices
import TalkFlowDomain

/// 접근성 트리에서 창과 요소를 찾는 낮은 층. 보내는 절차는
/// `AccessibilityMessageSender`에 있고, 여기에는 그 절차가 만지는 요소를 어떻게
/// 찾아내는지만 둔다.
///
/// 파일이 갈리면서 `private`이던 것들이 모듈 안에서 보이게 되었다. 이 타입 밖에서
/// 부를 것은 없다.
extension AccessibilityMessageSender {
    /// The one window this text may be typed into.
    ///
    /// Every refusal here is retryable: not finding the window means katok gets
    /// the job, which can also open a closed room.
    static func chatWindow(titled name: String) throws -> AXUIElement {
        guard let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == kakaoTalkBundleID
        }) else {
            throw MessageSendFailure(message: "카카오톡이 실행 중이 아닙니다.", isRetryable: true)
        }

        let application = AXUIElementCreateApplication(app.processIdentifier)
        let windows = (value(application, kAXWindowsAttribute) as? [AXUIElement]) ?? []
        // Matched on `RoomNameKey`, not on the title as written. A group room
        // nobody named is titled with its members, and KakaoTalk's window title
        // and the archive order them differently — so a room whose window was
        // plainly open could not be found, this path gave up, and katok was
        // handed a job it failed at for the same reason. Measured 2026-08-10:
        // six sends refused as 「대화창이 닫혀 있어」 against an open window.
        let wanted = RoomNameKey.of(name)
        let matching = windows.filter {
            (value($0, kAXTitleAttribute) as? String).map(RoomNameKey.of) == wanted
        }

        // Room names are not unique, and the accessibility tree offers nothing
        // else to tell two windows apart. Typing into a guess would deliver
        // someone's message to the wrong conversation, so it declines instead.
        guard matching.count == 1, let window = matching.first else {
            throw MessageSendFailure(
                message: matching.isEmpty
                    ? "이 데스크탑에 \(name) 창이 열려 있지 않습니다."
                    : "\(name)이라는 창이 여러 개라 어느 방인지 정할 수 없습니다.",
                isRetryable: true
            )
        }
        return window
    }

    /// The message bubbles carry the same role as the compose box. The one that
    /// can be written to is the compose box.
    static func composeBox(in element: AXUIElement) -> AXUIElement? {
        firstElement(in: element) { node in
            ((value(node, kAXRoleAttribute) as? String) ?? "").contains("TextArea")
                && isSettable(node)
        }
    }

    /// Found by its label, because nothing else tells it apart. A chat window
    /// carries a dozen buttons and several of them answer to a press — close,
    /// full screen, minimise. Pressing the wrong one would not send anything, but
    /// it would do something to a window the user is looking at.
    ///
    /// A label is language-shaped, and a KakaoTalk running in another language
    /// would not match. That degrades into a refusal rather than a mistake, and a
    /// refusal is retryable, so the message goes to katok instead of nowhere.
    static func sendButton(in element: AXUIElement) -> AXUIElement? {
        firstElement(in: element) { node in
            (value(node, kAXRoleAttribute) as? String) == (kAXButtonRole as String)
                && sendButtonLabels.contains((value(node, kAXTitleAttribute) as? String) ?? "")
        }
    }

    /// Breadth-first, and that is the whole performance of this path. Depth-first
    /// descends into the message list before it looks at the window's own
    /// controls, and every bubble in a long conversation is an accessibility
    /// query across a process boundary. Measured on this Mac: sends that took the
    /// direct route were finishing in twenty-three and twenty-four seconds — worse
    /// than handing the job to katok, which the direct route exists to avoid.
    ///
    /// Both things this looks for sit shallow — the compose box a couple of
    /// levels under the window, the send button directly beneath it — while the
    /// scrollback is deep. Reaching them a level at a time finds them after tens
    /// of queries instead of thousands.
    static func firstElement(
        in element: AXUIElement,
        matching predicate: (AXUIElement) -> Bool
    ) -> AXUIElement? {
        var frontier = [element]
        var visited = 0

        while !frontier.isEmpty, visited < searchBudget {
            var next: [AXUIElement] = []
            for node in frontier {
                visited += 1
                if visited > searchBudget { break }

                if predicate(node) { return node }

                next.append(contentsOf: (value(node, kAXChildrenAttribute) as? [AXUIElement]) ?? [])
            }
            frontier = next
        }
        return nil
    }

    /// A ceiling on how much of somebody's conversation this will walk before it
    /// gives up and lets katok try. Generous next to where the box actually is,
    /// and small next to a room with a year of scrollback in it.
    static let searchBudget = 2_000

    static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success else {
            return nil
        }
        return result
    }

    static func isSettable(_ element: AXUIElement) -> Bool {
        var settable = DarwinBoolean(false)
        AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable)
        return settable.boolValue
    }

    static let kakaoTalkBundleID = "com.kakao.KakaoTalkMac"

    /// What KakaoTalk calls the button, in the languages this has been seen in.
    static let sendButtonLabels: Set<String> = ["전송", "Send"]
}
