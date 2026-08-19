import Foundation
import TalkFlowDomain

/// Where the time went, as the 활동 detail pane says it.
///
/// A value rather than branches inside the view, for the reason the whole screen
/// is built this way: the numbers here are the ones a user will quote back when
/// they say the app is slow, and a SwiftUI view cannot be asserted against.
///
/// The elapsed figure belongs to the stage it sits on and means "time spent
/// getting here", so 모델 답변 받음 carries the model's own seconds. That is the
/// reading somebody scanning the column will take whether or not it is the one
/// intended, so it is the one built.
struct ActionTimelineSection: Equatable {
    struct Row: Equatable, Identifiable {
        let stage: ActionStage
        let time: String
        /// Nil on the first row: nothing preceded it, and a zero there would read
        /// as instant when the truth is that the clock started.
        let elapsed: String?
        let note: String?
        /// The stage that took longest, marked so the eye lands on it instead of
        /// comparing ten numbers.
        let isSlowest: Bool

        var id: String { stage.rawValue }
    }

    let rows: [Row]
    /// Start to finish, said once so nobody has to add the column up.
    let total: String

    /// Nil when there is nothing to draw: a row written before timings existed, or
    /// one that recorded a single instant and so has no duration to show.
    static func of(_ timeline: ActionTimeline) -> ActionTimelineSection? {
        let spans = timeline.spans
        guard spans.count > 1, let total = timeline.duration else { return nil }

        let slowest = timeline.slowestStage
        return ActionTimelineSection(
            rows: spans.map { span in
                Row(
                    stage: span.stage,
                    time: timeFormatter.string(from: span.at),
                    elapsed: span.elapsed.map(duration(_:)),
                    note: span.note,
                    isSlowest: span.stage == slowest
                )
            },
            total: duration(total)
        )
    }

    /// Tenths below a minute, because the differences that matter on this screen
    /// are seconds — a model call against a file read — and rounding those to
    /// whole seconds throws away the comparison. Above a minute the tenth is
    /// noise, and a bare "127.4초" is a number nobody converts in their head.
    static func duration(_ seconds: TimeInterval) -> String {
        let seconds = max(0, seconds)
        guard seconds >= 60 else {
            return String(format: "%.1f초", seconds)
        }
        let whole = Int(seconds.rounded())
        let remainder = whole % 60
        guard remainder > 0 else { return "\(whole / 60)분" }
        return "\(whole / 60)분 \(remainder)초"
    }

    /// Seconds included, unlike everywhere else this app prints a time. The whole
    /// section is about differences of a few seconds, and a column reading 21:04
    /// four times over would hide exactly what it was added to show.
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}
