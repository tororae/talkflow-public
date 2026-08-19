import Foundation
import Testing
@testable import TalkFlowDomain

private let account = "katok-test"
private let now = Date(timeIntervalSince1970: 1_000_000)
private let gate = SendGate()

@Test
func aDraftGoesOutOnlyWhenEveryConditionHolds() {
    #expect(gate.evaluate(request()) == .send)
}

/// The emergency stop has to reach drafts that were already queued, otherwise
/// pressing it still lets messages go out.
@Test
func theGlobalPauseCancelsQueuedDraftsRatherThanDelayingThem() {
    #expect(gate.evaluate(request(globalEnabled: false)) == .cancel(.globalPause))
}

@Test
func aDifferentAccountAtSendTimeCancelsTheDraft() {
    #expect(gate.evaluate(request(currentFingerprint: "katok-other")) == .cancel(.accountMismatch))
    #expect(gate.evaluate(request(currentFingerprint: nil)) == .cancel(.accountMismatch))
}

@Test
func turningOffAutoSendAfterTheDraftWasMadeCancelsIt() {
    #expect(gate.evaluate(request(delivery: .draftOnly)) == .cancel(.roomNoLongerAutoSends))
    #expect(gate.evaluate(request(mode: .off)) == .cancel(.roomNoLongerAutoSends))
    #expect(gate.evaluate(request(mode: .detectOnly)) == .cancel(.roomNoLongerAutoSends))
}

/// The reply answers 지수, and 지수 has said more since. It still goes out.
///
/// This used to be a cancellation, and it did not converge: the next sync drafted
/// the room again, that took another eight seconds, and 지수 could speak inside
/// that too. Three days of it cost 113 drafts — a quarter of everything written,
/// every one a model call already paid for. Whether more was coming is asked of
/// the model now, before the draft is queued at all.
@Test
func theAnsweredPersonSayingMoreDoesNotCancelTheDraft() {
    let verdict = gate.evaluate(
        request(latestMessageID: "m2", triggerSenderID: "지수", latestMessageSenderID: "지수")
    )

    #expect(verdict == .send)
}

/// Somebody else talking is not the conversation moving on — it is a group
/// chat. Reading it as staleness made busy rooms unanswerable: a model call
/// takes about ten seconds, someone speaks inside that window nearly every
/// time, and the draft died within two seconds of being written.
@Test
func anotherPersonTalkingDoesNotCancelTheDraft() {
    let verdict = gate.evaluate(
        request(latestMessageID: "m2", triggerSenderID: "지수", latestMessageSenderID: "민수")
    )

    #expect(verdict == .send)
}

@Test
func theUsersOwnLaterMessageDoesNotCancelTheDraft() {
    let verdict = gate.evaluate(
        request(latestMessageID: "m2", latestMessageSenderID: nil)
    )

    #expect(verdict == .send)
}

@Test
func aDraftThatSatTooLongIsDroppedRatherThanSentLate() {
    let verdict = gate.evaluate(request(createdAt: now.addingTimeInterval(-1000)))

    #expect(verdict == .cancel(.tooOld))
}

/// The minute is the whole point of the tightened limit: a draft that missed it
/// is handed back to review rather than sent late. Under the old fifteen-minute
/// window this same draft went out.
@Test
func aDraftPastItsMinuteIsNoLongerAutoSent() {
    let verdict = gate.evaluate(request(createdAt: now.addingTimeInterval(-90)))

    #expect(verdict == .cancel(.tooOld))
}

/// Waiting, not cancelling: the user can accept the policy at any time and the
/// queued draft should still be usable when they do.
@Test
func nothingIsSentBeforeTheUsePolicyIsAccepted() {
    #expect(gate.evaluate(request(usePolicyAccepted: false)) == .wait(.usePolicyNotAccepted))
}

@Test
func theSettlingDelayIsRespected() {
    let verdict = gate.evaluate(request(eligibleAt: now.addingTimeInterval(30)))

    #expect(verdict == .wait(.stillSettling(remaining: 30)))
}

@Test
func nothingIsSentWhileTheUserIsAtTheKeyboard() {
    let verdict = gate.evaluate(request(idleSeconds: 2))

    #expect(verdict == .wait(.userIsActive(idleSeconds: 2)))
}

@Test
func aLockedScreenHoldsTheDraftBecauseAutomationCannotRunThere() {
    #expect(gate.evaluate(request(screenLocked: true)) == .wait(.screenLocked))
}

/// Cancels are checked before waits: a draft that can never be correct should
/// not sit in the queue reporting that it is merely settling.
@Test
func aCancellingConditionOutranksAWaitingOne() {
    let verdict = gate.evaluate(
        request(globalEnabled: false, eligibleAt: now.addingTimeInterval(30), idleSeconds: 0)
    )

    #expect(verdict == .cancel(.globalPause))
}

// MARK: - Fixtures

private func request(
    globalEnabled: Bool = true,
    usePolicyAccepted: Bool = true,
    currentFingerprint: String? = account,
    mode: ResponseMode = .automatic,
    delivery: DeliveryMode = .autoSendWhenIdle,
    latestMessageID: String? = "m1",
    triggerSenderID: String? = "지수",
    latestMessageSenderID: String? = "지수",
    opensConversationAfterMessageID: String? = nil,
    eligibleAt: Date = now.addingTimeInterval(-1),
    createdAt: Date = now.addingTimeInterval(-1),
    idleSeconds: TimeInterval = 30,
    screenLocked: Bool = false
) -> SendGateRequest {
    SendGateRequest(
        send: PendingSend(
            id: 1,
            accountFingerprint: account,
            chatRoomID: "room-1",
            triggerMessageID: "m1",
            triggerSenderID: triggerSenderID,
            opensConversationAfterMessageID: opensConversationAfterMessageID,
            text: "네 좋아요",
            eligibleAt: eligibleAt,
            createdAt: createdAt
        ),
        policy: RoomPolicy(
            accountFingerprint: account,
            chatRoomID: "room-1",
            responseMode: mode,
            deliveryMode: delivery
        ),
        globalResponsesEnabled: globalEnabled,
        usePolicyAccepted: usePolicyAccepted,
        currentAccountFingerprint: currentFingerprint,
        latestMessageID: latestMessageID,
        latestMessageSenderID: latestMessageSenderID,
        activity: SystemActivitySnapshot(
            idleSeconds: idleSeconds,
            screenLocked: screenLocked
        ),
        now: now
    )
}

// MARK: - Always-on delivery

/// Waiting for idle means never replying while someone is at their machine,
/// which is most of the working day. This mode trades the interruption for
/// actually delivering.
@Test
func alwaysOnDeliveryDoesNotWaitForTheUserToStepAway() {
    let verdict = gate.evaluate(request(delivery: .always, idleSeconds: 0))

    #expect(verdict == .send)
}

/// A locked session cannot be typed into whatever the mode says.
@Test
func alwaysOnDeliveryStillWaitsForALockedScreen() {
    let verdict = gate.evaluate(request(delivery: .always, screenLocked: true))

    #expect(verdict == .wait(.screenLocked))
}

@Test
func alwaysOnDeliveryStillRespectsTheSettlingDelay() {
    let verdict = gate.evaluate(
        request(delivery: .always, eligibleAt: now.addingTimeInterval(30), idleSeconds: 0)
    )

    #expect(verdict == .wait(.stillSettling(remaining: 30)))
}

/// 상시 전송 in a room where the conversation kept going is the case the old
/// staleness rule hurt most, and it is the one this room's owner chose the mode
/// for: they want the answer to arrive, not to be withdrawn.
@Test
func alwaysOnDeliverySendsEvenWhenTheAnsweredPersonSaidMore() {
    let verdict = gate.evaluate(
        request(
            delivery: .always,
            latestMessageID: "m2",
            triggerSenderID: "지수",
            latestMessageSenderID: "지수",
            idleSeconds: 0
        )
    )

    #expect(verdict == .send)
}

@Test
func draftOnlyNeverDeliversAutomatically() {
    #expect(DeliveryMode.draftOnly.deliversAutomatically == false)
    #expect(DeliveryMode.autoSendWhenIdle.deliversAutomatically)
    #expect(DeliveryMode.always.deliversAutomatically)
    #expect(DeliveryMode.always.interruptsWork)
    #expect(DeliveryMode.autoSendWhenIdle.interruptsWork == false)
}

// MARK: - Openers

/// An opener holds one permission and one only: the room had gone quiet. Anybody
/// at all speaking since takes it away, so it is cancelled where a reply from the
/// same situation would go out.
@Test
func aQueuedOpenerIsCancelledAsSoonAsTheRoomSaysAnything() {
    let opener = gate.evaluate(
        request(
            latestMessageID: "m2",
            triggerSenderID: nil,
            latestMessageSenderID: "민수",
            opensConversationAfterMessageID: "m1"
        )
    )
    let reply = gate.evaluate(
        request(latestMessageID: "m2", triggerSenderID: "지수", latestMessageSenderID: "민수")
    )

    #expect(opener == .cancel(.conversationMovedOn))
    #expect(reply == .send)
}

/// Still quiet, so it still goes.
@Test
func aQueuedOpenerIntoAStillQuietRoomGoesOut() {
    let verdict = gate.evaluate(
        request(
            latestMessageID: "m1",
            triggerSenderID: nil,
            latestMessageSenderID: "지수",
            opensConversationAfterMessageID: "m1"
        )
    )

    #expect(verdict == .send)
}

/// Speaking unasked is the opener's own permission; sending at all is the room's.
/// This may never be the setting that widens that one.
@Test
func anOpenerNeverDeliversMoreFreelyThanTheRoomsOwnRepliesDo() {
    var policy = RoomPolicy(
        accountFingerprint: account,
        chatRoomID: "room-1",
        responseMode: .automatic,
        deliveryMode: .draftOnly,
        conversationOpener: .delivers
    )
    #expect(policy.openerDeliversAutomatically == false)

    policy.deliveryMode = .always
    #expect(policy.openerDeliversAutomatically)

    policy.conversationOpener = .draftOnly
    #expect(policy.openerDeliversAutomatically == false)
}
