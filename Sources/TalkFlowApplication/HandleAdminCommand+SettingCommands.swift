import Foundation
import TalkFlowDomain

/// The commands that write a room's policy: one field at a time, the 응답
/// switch on its own, and a named bundle of both.
///
/// All three follow the same order — load the stored policy, fold the change
/// in, save, tell the screen, then echo before → after. A value the field
/// cannot take is answered without a write, and a save that throws is answered
/// as a failure rather than a phantom success.
extension HandleAdminCommand {
    // MARK: - !세팅 <N> · !세팅 <N> <항목>

    /// `!세팅 <N>`: the room's settable fields with their current values, read
    /// straight off the stored policy — the step that shows what there is to change.
    func settingFieldsResponse(roomNumber: Int, sorted: [ChatRoom], account: AccountProfile) async -> String {
        guard let room = room(atNumber: roomNumber, in: sorted) else { return AdminCommandResponder.unknownRoom }
        let policy = (try? await policyStore.policy(for: room, accountFingerprint: account.fingerprint))
            ?? .makeDefault(accountFingerprint: account.fingerprint, room: room)
        let infos = PolicyEditor.settableFields.compactMap { PolicyEditor.describe(field: $0, in: policy) }
        return AdminCommandResponder.settingFields(roomNumber: roomNumber, roomName: room.displayName, infos: infos)
    }

    /// `!세팅 <N> <항목>`: that one field's value now and the values it takes, or
    /// 「그런 항목이 없어요」 when the 항목 is not one the console sets.
    func settingFieldResponse(roomNumber: Int, field: String, sorted: [ChatRoom], account: AccountProfile) async -> String {
        guard let room = room(atNumber: roomNumber, in: sorted) else { return AdminCommandResponder.unknownRoom }
        let policy = (try? await policyStore.policy(for: room, accountFingerprint: account.fingerprint))
            ?? .makeDefault(accountFingerprint: account.fingerprint, room: room)
        guard let info = PolicyEditor.describe(field: field, in: policy) else {
            return AdminCommandResponder.settingFailed(.unknownField)
        }
        return AdminCommandResponder.settingField(roomNumber: roomNumber, roomName: room.displayName, info: info)
    }

    // MARK: - !세팅 <N> <항목> <값>

    /// Loads the room's current policy, asks `PolicyEditor` to fold the one field
    /// into it, and — only on success — saves and echoes the change. A value the
    /// field cannot take is answered without a write; a save that throws is answered
    /// as a save failure rather than a phantom success, so a change the store never
    /// took is never echoed as if it had.
    func settingResponse(
        roomNumber: Int,
        field: String,
        value: String,
        sorted: [ChatRoom],
        account: AccountProfile
    ) async -> String {
        guard let room = room(atNumber: roomNumber, in: sorted) else { return AdminCommandResponder.unknownRoom }
        let policy = (try? await policyStore.policy(for: room, accountFingerprint: account.fingerprint))
            ?? .makeDefault(accountFingerprint: account.fingerprint, room: room)
        switch PolicyEditor.apply(field: field, value: value, to: policy) {
        case let .success(applied):
            do {
                try await policyStore.save(applied.policy)
            } catch {
                return AdminCommandResponder.settingSaveFailed
            }
            // The write landed; tell whoever is showing this room so its screen
            // catches up without a full reload. After the save, never before —
            // the listener re-reads the store and must not read the old value.
            await onRoomPolicyChanged?(applied.policy.chatRoomID)
            return AdminCommandResponder.settingApplied(
                roomNumber: roomNumber,
                roomName: room.displayName,
                label: applied.label,
                before: applied.before,
                after: applied.after
            )
        case let .failure(failure):
            return AdminCommandResponder.settingFailed(failure)
        }
    }

    // MARK: - !켬 · !끔

    /// Turns a room's 응답 on or off in one word. On uses the mode that suits the
    /// room's type — the same `initialEnabledMode` the app's list switch uses — so a
    /// group does not start auto-answering everything; off is `.off`. Saves, tells
    /// the screen to refresh, and echoes the before → after like a `!세팅` change.
    func toggleRoomResponse(roomNumber: Int, on: Bool, sorted: [ChatRoom], account: AccountProfile) async -> String {
        guard let room = room(atNumber: roomNumber, in: sorted) else { return AdminCommandResponder.unknownRoom }
        var policy = (try? await policyStore.policy(for: room, accountFingerprint: account.fingerprint))
            ?? .makeDefault(accountFingerprint: account.fingerprint, room: room)
        let before = policy.responseMode.title
        policy.responseMode = on ? RoomPolicy.initialEnabledMode(for: room) : .off
        do {
            try await policyStore.save(policy)
        } catch {
            return AdminCommandResponder.settingSaveFailed
        }
        await onRoomPolicyChanged?(room.id)
        return AdminCommandResponder.settingApplied(
            roomNumber: roomNumber,
            roomName: room.displayName,
            label: "응답",
            before: before,
            after: policy.responseMode.title
        )
    }

    // MARK: - !프리셋

    /// Applies a named bundle to a room and echoes what it set, refreshing the
    /// screen like any other write. An unknown name is answered with the menu's
    /// names rather than a change.
    func presetApplyResponse(roomNumber: Int, name: String, sorted: [ChatRoom], account: AccountProfile) async -> String {
        guard let room = room(atNumber: roomNumber, in: sorted) else { return AdminCommandResponder.unknownRoom }
        let policy = (try? await policyStore.policy(for: room, accountFingerprint: account.fingerprint))
            ?? .makeDefault(accountFingerprint: account.fingerprint, room: room)
        guard let updated = RoomPreset.apply(name, to: policy), let summary = RoomPreset.summary(name) else {
            return AdminCommandResponder.presetUnknown
        }
        do {
            try await policyStore.save(updated)
        } catch {
            return AdminCommandResponder.settingSaveFailed
        }
        await onRoomPolicyChanged?(room.id)
        return AdminCommandResponder.presetApplied(roomNumber: roomNumber, roomName: room.displayName, name: name, summary: summary)
    }

    /// The preset menu, named to a room when one was given so its example points
    /// back at it.
    func presetListResponse(roomNumber: Int?, sorted: [ChatRoom]) -> String {
        let roomName = roomNumber.flatMap { room(atNumber: $0, in: sorted) }?.displayName
        return AdminCommandResponder.presetList(roomNumber: roomNumber, roomName: roomName)
    }
}
