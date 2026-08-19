/// Keeps the Mac in a state where queued replies can actually be delivered.
///
/// Sending drives KakaoTalk's UI, which needs an unlocked session. The session
/// locks when the display sleeps — measured at about a second after it does. So
/// while auto-reply is armed TalkFlow holds the machine awake, and while the lid
/// is shut it also holds the display awake: behind a closed lid that costs
/// nothing visible, and it is what keeps the session unlocked.
///
/// Opening the lid releases the display hold immediately, so a screen the user
/// can actually see goes back to sleeping normally.
public protocol WakefulnessController: Sendable {
    func setArmed(_ armed: Bool) async
}
