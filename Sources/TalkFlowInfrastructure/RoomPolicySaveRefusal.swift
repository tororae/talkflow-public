import Foundation

/// A save that did not happen because the row it would have replaced could not be
/// read.
///
/// Refusing is the whole point. A row this build cannot decode reads as
/// `RoomPolicy.makeDefault` for display — the room list has to draw something —
/// and a default is a complete policy, so saving it back writes all 46 non-key
/// columns and the user's 답변 조건, 참고 지시 and 키워드 are gone with no copy
/// anywhere. One flipped switch in the room screen, or one `!켬` from the console,
/// was enough. So the store refuses the write instead, and the person is told
/// which room and that nothing was touched.
///
/// Lives here rather than in `TalkFlowDomain` because nothing branches on it: it
/// is a schema fact — this file's bytes do not fit this build's columns — and the
/// rest of the app only shows it. `MessageSendFailure` is in the domain for the
/// opposite reason, that the send path decides what to do next by reading it.
public struct RoomPolicySaveRefusal: LocalizedError, Equatable, Sendable {
    public let chatRoomID: String

    public init(chatRoomID: String) {
        self.chatRoomID = chatRoomID
    }

    /// Two lines, because that is what `RoomSaveBar` shows. It says what did not
    /// happen before what went wrong: the reader of this message clicked 저장 and
    /// the first thing they need is that their click did nothing.
    public var explanation: String {
        """
        이 방에 저장된 설정을 읽을 수 없어 아무것도 덮어쓰지 않았습니다. \
        저장된 값이 손상됐을 수 있습니다. 그 값을 고치거나 지우기 전에는 이 방 설정을 저장할 수 없습니다. \
        (방 \(chatRoomID))
        """
    }

    public var errorDescription: String? { explanation }
}
