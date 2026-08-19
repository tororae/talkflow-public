import AppKit
import Foundation

/// Whether KakaoTalk is the application receiving the user's keystrokes.
///
/// The one question that decides whether an automatic send could steal a
/// keystroke. Idle time cannot answer it — that is machine-wide, and somebody
/// typing into an editor reads exactly like somebody typing into a chat.
protocol FrontmostApplicationReading: Sendable {
    func isKakaoTalkFrontmost() -> Bool
}

struct WorkspaceFrontmostApplication: FrontmostApplicationReading {
    static let kakaoTalkBundleID = "com.kakao.KakaoTalkMac"

    /// Nil frontmost means no application owns the front — a screen saver, a
    /// login window, a moment between switches. None of those is KakaoTalk
    /// receiving typing, so none of them is a reason to hold a message back.
    func isKakaoTalkFrontmost() -> Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Self.kakaoTalkBundleID
    }
}
