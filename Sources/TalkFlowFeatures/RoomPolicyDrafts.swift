import TalkFlowApplication
import TalkFlowDomain

/// Room settings edited but not yet written, one pending copy per room.
///
/// The room screen's half of `Drafts`, which is where the bargain 저장 and 취소
/// make is written down. A room's draft is its `RoomPolicy` unchanged: nothing
/// about a policy is trimmed or derived on the way to disk, so there is no
/// projection to make and the stored value compares directly.
typealias RoomPolicyDrafts = Drafts<ChatRoomPolicy>

extension ChatRoomPolicy: DraftableEntry {
    var savedValue: RoomPolicy { policy }
}
