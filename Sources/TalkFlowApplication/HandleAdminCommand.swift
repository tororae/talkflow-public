import Foundation
import TalkFlowDomain

/// Runs the one deliberate carve-out of the app's "message text is never
/// executed as instructions" rule: in a room the operator designated a console,
/// a `!`-prefixed command is read and TalkFlow answers into that room.
///
/// The authority is two things that live *outside* the text — the room is a
/// designated admin room, and everyone in it is trusted (Model A). It does **not**
/// gate on `isFromMe`: the operator is a different KakaoTalk account from the one
/// TalkFlow runs as, so `isFromMe` would reject exactly the person it exists for.
/// A room that is not a console never parses anything, so an ordinary line with a
/// leading `!` there is just a message.
///
/// It runs at the very top of a room's turn, before the global-responses switch
/// and the room's own mode are consulted, so a command works even when responses
/// are paused or the console is set to answer nobody. When it consumes a command
/// the caller skips normal drafting for that room.
public struct HandleAdminCommand: Sendable {
    let connection: any KakaoConnection
    let sender: any MessageSender
    let policyStore: any RoomPolicyStore
    let adminRoomStore: any AdminRoomStore
    /// Optional for the same reason it is everywhere else: a build without a
    /// database keeps no person notes, and the member commands say so rather than
    /// claiming nobody is remembered.
    let personNotes: (any PersonNoteStore)?
    /// The record, for dedup and for the audit trail. A command already answered
    /// is not answered again, and every console reply lands in 활동 like any other
    /// thing the app did in the user's name.
    let actionLog: any AgentActionLog
    /// Told the id of a room whose policy a `!세팅` write just changed, so the UI can
    /// refresh that one room without a full reload. Optional and named as a plain
    /// closure so this file knows nothing of the screen it feeds — the same way
    /// `adminCommand` is threaded into the pipeline. Nil in tests and in a headless
    /// build, where the write still lands and simply nobody is listening.
    let onRoomPolicyChanged: (@Sendable (String) async -> Void)?

    public init(
        connection: any KakaoConnection,
        sender: any MessageSender,
        policyStore: any RoomPolicyStore,
        adminRoomStore: any AdminRoomStore,
        personNotes: (any PersonNoteStore)? = nil,
        actionLog: any AgentActionLog,
        onRoomPolicyChanged: (@Sendable (String) async -> Void)? = nil
    ) {
        self.connection = connection
        self.sender = sender
        self.policyStore = policyStore
        self.adminRoomStore = adminRoomStore
        self.personNotes = personNotes
        self.actionLog = actionLog
        self.onRoomPolicyChanged = onRoomPolicyChanged
    }

    /// The pipeline's entry point: resolves the connected account, then hands off.
    ///
    /// A convenience over the account-taking method so the drafting loop, which
    /// holds no account, can call this the way it calls `draftReplies`. Not
    /// connected means no command — the same answer the drafting pipeline gives
    /// itself when the account cannot be verified.
    public func handle(roomID: String) async -> Bool {
        guard case let .connected(account) = await connection.status() else { return false }
        return await handle(roomID: roomID, account: account)
    }

    /// True when a command was consumed — so the caller skips normal drafting for
    /// this room — false when the room is no console, has nothing to read, or the
    /// newest line is not a command.
    public func handle(roomID: String, account: AccountProfile) async -> Bool {
        // 1. The fence. Everything past here trusts the room's text; a room that
        // was never designated a console never gets here.
        guard let adminRoomIDs = try? await adminRoomStore.adminRoomIDs(accountFingerprint: account.fingerprint),
              adminRoomIDs.contains(roomID)
        else {
            return false
        }

        // The one fixed ordering every number is read against, re-derived each
        // command and stored nowhere — the same sort `LoadChatRooms` uses. The
        // console room has to be in it to be read; if the list cannot be had, or
        // this room is not in it, there is nothing to consume and the room falls
        // through to normal handling.
        guard let rooms = try? await connection.chatRooms() else { return false }
        let sorted = rooms.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        guard let room = sorted.first(where: { $0.id == roomID }) else { return false }

        // 2. The line to act on is the newest, the one that just arrived.
        guard let latest = try? await connection.recentMessages(in: room, limit: 1).last else { return false }

        // The account's own messages are never commands. Every console reply is
        // plain text sent from this same account, and a reply that read back as a
        // command — the 사용법 line, which used to lead with the prefix — was answered
        // forever. This is NOT the fence: the operator is a different account, so
        // their commands are isFromMe == false and still run (see the type's note on
        // why isFromMe cannot authorize). It only stops the console from hearing its
        // own echo. Falling through is safe — the normal pipeline ignores own
        // messages too, which is why the read commands never looped.
        guard !latest.isFromMe else { return false }

        // 3. Already handled. A sync fires on any room changing, so without this
        // the same command would be re-run — and re-sent — on every later update.
        if (try? await actionLog.hasAction(chatRoomID: room.id, triggerMessageID: latest.id)) == true {
            return true
        }

        // 4. Parse. An unknown verb still gets an answer, but only when the line
        // was meant as a command — it opens with the prefix. A plain line falls
        // through to normal drafting untouched.
        guard let command = AdminCommandParser.parse(latest.body) else {
            guard latest.body.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix(AdminCommandParser.prefix) else {
                return false
            }
            await respond(AdminCommandResponder.unknownCommand, in: room, to: latest, account: account)
            return true
        }

        // 5–7. Run the command, send the answer, and leave a row either way.
        let response = await respond(to: command, consoleRoom: room, sorted: sorted, account: account)
        await respond(response, in: room, to: latest, account: account)
        return true
    }

    /// Sends the answer straight into the console room and records what happened.
    ///
    /// Direct like `ReviewDrafts.send`, not through the queue: the operator is
    /// present by definition, so `.userRequested` is the honest origin and the
    /// idle/settling checks that guard automatic delivery do not apply. A send
    /// that throws is recorded as `.failed` rather than swallowed — the row still
    /// keys on the trigger message, so dedup holds and the console is not answered
    /// twice, and the operator can re-type to try again.
    private func respond(
        _ text: String,
        in room: ChatRoom,
        to latest: ChatMessage,
        account: AccountProfile
    ) async {
        var timeline = ActionTimeline().stamping(.sendAttempted)
        do {
            let receipt = try await sender.send(
                text: text,
                toChatRoomID: room.id,
                // The room's name, because KakaoTalk titles its windows by it and
                // the sender has nothing else to find the window by.
                named: room.displayName,
                origin: .userRequested
            )
            timeline.stamp(.sent, note: receipt.explanation)
            try? await actionLog.record(action(kind: .commanded, in: room, to: latest, account: account, replyText: text, detail: "관리자 명령에 답했습니다.", timeline: timeline))
        } catch {
            timeline.stamp(.failed, note: error.localizedDescription)
            try? await actionLog.record(action(kind: .failed, in: room, to: latest, account: account, replyText: nil, detail: error.localizedDescription, timeline: timeline))
        }
    }

    private func action(
        kind: AgentAction.Kind,
        in room: ChatRoom,
        to latest: ChatMessage,
        account: AccountProfile,
        replyText: String?,
        detail: String,
        timeline: ActionTimeline
    ) -> AgentAction {
        AgentAction(
            accountFingerprint: account.fingerprint,
            chatRoomID: room.id,
            chatRoomName: room.displayName,
            kind: kind,
            triggerMessageID: latest.id,
            // No sender id on purpose. A console command is not a person to
            // remember, and leaving it off keeps this row out of 사람 기억's
            // sender counts by construction rather than by a filter downstream.
            triggerText: latest.body,
            replyText: replyText,
            detail: detail,
            timeline: timeline
        )
    }
}
