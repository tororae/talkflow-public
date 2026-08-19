import Foundation
import Observation
import TalkFlowApplication
import TalkFlowDomain

/// The room screen's view of 채팅방 요약.
///
/// A model of its own rather than more state on `ChatRoomListModel`. That one
/// holds the board of rooms and their policies, which the whole screen reads; this
/// holds one room's note, an in-flight model call, and a refusal message — state
/// that only one section reads and that has to be cleared every time another room
/// is opened.
@MainActor
@Observable
public final class RoomSummaryModel {
    /// The note for the room on screen, or nil for a room that has none.
    public private(set) var summary: ConversationSummary?
    /// True while the manual refresh is out. The button spends money, so it says
    /// so rather than looking like it did nothing for twenty seconds.
    public private(set) var isRefreshing = false
    /// Set when an edit was refused or a refresh failed, so the field keeps what
    /// was typed instead of the text disappearing under the cursor.
    public private(set) var issue: String?

    private let manage: ManageConversationSummary
    /// Which room the state above belongs to. Held so a reply from a call started
    /// in one room cannot land in another room's section.
    private var roomID: String?
    /// The newest text the field has reported, so an older save finishing late
    /// cannot put its answer back on screen.
    private var pendingEdit: String?

    public init(manage: ManageConversationSummary) {
        self.manage = manage
    }

    public func load(_ room: ChatRoom) async {
        roomID = room.id
        summary = nil
        issue = nil
        pendingEdit = nil
        let loaded = try? await manage.summary(for: room)
        guard roomID == room.id else { return }
        summary = loaded
    }

    /// Saves as the user types, like every other field on the room screen.
    ///
    /// Refuses rather than shortens. This box holds a paragraph, and a field that
    /// rewrites itself mid-sentence is what made the keyword box impossible to
    /// type into.
    public func edit(_ text: String, in room: ChatRoom) {
        guard !ConversationSummary.exceedsLimit(text) else {
            issue = ConversationSummaryError.tooLong.errorDescription
            return
        }
        issue = nil
        pendingEdit = text
        Task {
            guard let saved = try? await manage.saveEdit(text, for: room) else { return }
            // One write per keystroke, and they can finish out of order. Only the
            // newest may reach the field: an older answer put back would rewrite
            // the text under the cursor, which is exactly what `EditableTextField`
            // exists to prevent.
            guard roomID == room.id, pendingEdit == text else { return }
            summary = saved
        }
    }

    /// 고정. Written immediately rather than on a 저장 press, because it is a
    /// switch and the sweep may read it before anybody would have got around to
    /// saving.
    public func setPinned(_ pinned: Bool, in room: ChatRoom) async {
        guard let current = summary, current.isPinned != pinned else { return }
        do {
            let saved = try await manage.setPinned(pinned, for: room)
            guard roomID == room.id else { return }
            summary = saved
            issue = nil
        } catch {
            guard roomID == room.id else { return }
            issue = error.localizedDescription
        }
    }

    /// The button, and it respects 고정 exactly as the sweep does. Pressing 지금
    /// 갱신 on a pinned note used to rewrite it — the flag only stopped the
    /// background sweep — which made the pin mean "unless you press this", a
    /// distinction nothing on the screen drew.
    public func refresh(_ room: ChatRoom) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        issue = nil
        pendingEdit = nil
        defer { isRefreshing = false }

        do {
            let refreshed = try await manage.refreshNow(for: room)
            guard roomID == room.id else { return }
            summary = refreshed
        } catch {
            guard roomID == room.id else { return }
            issue = error.localizedDescription
        }
    }

    public func clear(_ room: ChatRoom) async {
        do {
            try await manage.clear(for: room)
        } catch {
            issue = error.localizedDescription
            return
        }
        guard roomID == room.id else { return }
        summary = nil
        issue = nil
        pendingEdit = nil
    }
}
