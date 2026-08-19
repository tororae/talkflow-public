import SwiftUI
import TalkFlowDomain

/// The 판단 주기 rows: 즉시, or a cycle the user types — a stretch of time, or a
/// number of messages.
///
/// The fields themselves are `IntervalRangeFields`, which owns the text being
/// typed into them and the unit that decides which of the two a cycle is. What is
/// left here is the choice between judging every message and judging in cycles,
/// and the number to hand over the moment somebody picks the second one.
struct RoomJudgementIntervalRow: View {
    private let roomID: String
    private let interval: JudgementInterval
    private let onChange: (JudgementInterval) -> Void

    init(
        roomID: String,
        interval: JudgementInterval,
        onChange: @escaping (JudgementInterval) -> Void
    ) {
        self.roomID = roomID
        self.interval = interval
        self.onChange = onChange
    }

    var body: some View {
        SettingHelpRow("판단 주기", help: .judgementInterval) {
            Picker("판단 주기", selection: batching) {
                Text("즉시").tag(false)
                Text("주기마다").tag(true)
            }
            .labelsHidden()
        }

        IntervalRangeFields(
            seedID: roomID,
            interval: interval,
            input: .judgement,
            isEnabled: interval.batches
        ) { parsed in
            guard parsed != interval else { return }
            onChange(parsed)
        }
    }

    /// 즉시 keeps no number of its own, so turning the cycle on takes the
    /// suggestion — which is also what the fields have been showing all along,
    /// for exactly this moment.
    ///
    /// The suggestion is measured in time, and stays that way even for somebody
    /// who was last in 개. A cycle is on or off here; which of the two it counts
    /// is a choice made in the unit beside the number, and this switch guessing
    /// at it would be the switch deciding a second thing nobody asked it.
    private var batching: Binding<Bool> {
        Binding(
            get: { interval.batches },
            set: { on in
                onChange(on ? JudgementIntervalInput.judgement.time.suggested : .immediate)
            }
        )
    }
}
