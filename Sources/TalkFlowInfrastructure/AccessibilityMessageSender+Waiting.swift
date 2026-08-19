import ApplicationServices
import Foundation

/// 카카오톡이 글자를 받았는지, 보냈는지를 기다려서 읽는 부분. 두 기다림의 상한이
/// 왜 그 값인지가 여기 함께 있다.
extension AccessibilityMessageSender {
    static func waitForBoxToEmpty(_ box: AXUIElement) -> Bool {
        for _ in 0..<deliveryChecks {
            usleep(deliveryCheckGap)
            if ((value(box, kAXValueAttribute) as? String) ?? "").isEmpty { return true }
        }
        return false
    }

    /// KakaoTalk keeps 전송 disabled while the box is empty, so it turning on is
    /// the app confirming it holds the staged text and considers it sendable.
    static func waitForSendToBeOffered(_ button: AXUIElement) -> Bool {
        for _ in 0..<stagingChecks {
            if (value(button, kAXEnabledAttribute) as? Bool) == true { return true }
            usleep(stagingCheckGap)
        }
        return false
    }

    /// Up to two seconds for KakaoTalk to take the staged text, in twentieths.
    ///
    /// Measured on this Mac it needs about three tenths, so this is nearly seven
    /// times what was observed — the ceiling is here to end the wait when the
    /// text never arrived at all, not to cut short a slow machine. Checking
    /// twenty times a second keeps the usual case near what KakaoTalk actually
    /// costs rather than rounding it up to the ceiling.
    static let stagingCheckGap: UInt32 = 50_000
    static let stagingChecks = 40

    /// Up to three seconds of watching, in tenths.
    ///
    /// The ceiling is set against what giving up costs, not against what
    /// KakaoTalk usually needs: handing over to katok is a fresh process that
    /// drives the interface and takes nine to twenty-two seconds. Three seconds
    /// of patience is cheap next to that, and the common case still returns in a
    /// tenth because the loop stops the moment the box empties.
    static let deliveryCheckGap: UInt32 = 100_000
    static let deliveryChecks = 30
}
