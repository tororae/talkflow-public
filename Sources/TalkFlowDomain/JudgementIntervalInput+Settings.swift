import Foundation

/// The two settings that are typed as a range, and the numbers each will take.
///
/// Apart from the parser because the parser is a mechanism and these are
/// decisions: every bound below is somewhere the setting stops doing what its
/// name says, and that is an argument, not a rule.
public extension JudgementIntervalInput {
    /// 판단 주기, which may be counted either way.
    ///
    /// On a clock the floor is five seconds, because that is the sync interval
    /// and so the oftenest a room can possibly be looked at — a shorter wait
    /// expires before anyone asks about it again, which would be a setting that
    /// changes nothing. The ceiling is two hours: past that the room is no longer
    /// answering the conversation it accumulated, and the batch gets trimmed to
    /// the newest messages anyway, so the extra wait buys silence rather than
    /// cheaper calls.
    ///
    /// In messages the floor is two, for the same reason zero is refused: one
    /// message is 즉시 said a second way, and a setting with two spellings of the
    /// same thing is how this app has misled its user before.
    ///
    /// The ceiling is twenty, and that one is a hard limit rather than taste. The
    /// cycle counts what it can see, and what it can see is the context window —
    /// `ConversationWindow.messageLimit` messages. Only other people's messages
    /// count, so a target near the window's size could sit unreachable in a room
    /// where the user is also talking, and the room would accumulate for ever
    /// with nothing on screen to explain it. Twenty leaves ten of those thirty
    /// slots for the user's own side of the conversation.
    ///
    /// The suggestions are fixed rather than ranges: spreading the cadence is
    /// worth offering, not worth turning on for somebody who did not ask.
    static let judgement = JudgementIntervalInput(
        time: Bounds(
            lowest: 5,
            highest: 7200,
            suggested: JudgementInterval(fixed: 300),
            floorHint: judgementFloorHint
        ),
        messages: Bounds(
            lowest: 2,
            highest: Double(ConversationWindow.messageLimit - 10),
            suggested: JudgementInterval(fixed: 10, measure: .messages),
            floorHint: judgementFloorHint
        )
    )

    /// 먼저 말 걸기: ten minutes at the bottom. This one is not paced by how often
    /// a room can be read but by how often a person plausibly opens a subject, and
    /// something that starts a new topic every few seconds is recognisable as a
    /// machine before anyone reads a word of it. The ceiling is a day, because
    /// "말 걸어도 하루에 한 번쯤" is a cadence somebody may genuinely want and there
    /// is nothing about a long wait here that stops the setting working.
    ///
    /// Time only, and no 개 in the picker. This cycle counts a silence, and a
    /// silence has no messages in it to count.
    ///
    /// The suggestion is a range rather than a fixed number, unlike 판단 주기. The
    /// regularity a fixed number produces is the exact tell this feature cannot
    /// afford: a reply at 5분 intervals reads as a busy person, an unprompted
    /// opener at 30분 intervals reads as a cron job.
    static let conversationOpener = JudgementIntervalInput(
        time: Bounds(
            // One minute at the bottom: the silence a room needs before an opener
            // is the room's to set, and some want to speak up the moment a beat
            // passes. Was ten minutes, which forced every room to sit out the same
            // long lull whether it suited them or not.
            lowest: 60,
            highest: 86400,
            suggested: JudgementInterval(shortest: 1800, longest: 10800)
        )
    )

    /// 집중 시간's own length: one minute at the bottom, because a burn shorter
    /// than that never gets a second message into it and the whole shape — a
    /// stretch of being present — needs a stretch. Six hours at the top, which is
    /// somebody who sat down after dinner.
    ///
    /// Time only, and the suggestion is a range for the reason 먼저 말 걸기's is:
    /// a burn that ran exactly twelve minutes every time is the most readable
    /// tell the feature could have.
    static let burningDuration = JudgementIntervalInput(
        time: Bounds(
            lowest: 60,
            highest: 21_600,
            suggested: BurningMode.defaultDuration
        )
    )

    /// The wait between burns. Ten minutes at the bottom rather than one: a
    /// cooldown short enough to land inside the same conversation makes the room
    /// look like it left and came straight back, which is worse than never having
    /// left. A week at the top, for a room somebody wants to hear from rarely.
    static let burningCooldown = JudgementIntervalInput(
        time: Bounds(
            lowest: 600,
            highest: 604_800,
            suggested: BurningMode.defaultCooldown
        )
    )

    /// Both floors point at the same door. Whichever unit the user is in, the
    /// thing under the floor is 즉시, and it is one picker away.
    private static let judgementFloorHint = "메시지마다 판단하려면 \"즉시\"를 고르세요."
}
