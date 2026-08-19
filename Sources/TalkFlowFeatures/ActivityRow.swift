import Foundation
import TalkFlowDomain

/// One line in the 활동 표: everything the app recorded about one message.
///
/// The record is written per event and read per message. Answering somebody once
/// leaves 초안 and 전송 as two rows, and three when a delivery failed in between —
/// 1,355 messages on one measured account are two rows and 172 are three or
/// more. Read as written, the table tells the same story three times and the one
/// line that says what happened is whichever scrolled into view.
///
/// So the rows are gathered here rather than shown as stored. Nothing is merged on
/// disk: each event is still its own row, still queryable, and 「초안은 만들었는데
/// 못 보냈다」 is still recoverable — which it would not be if the write path had
/// been made to overwrite instead.
///
/// The key is the trigger message id, the same one `ActivityTimelineModel.timeline(for:)`
/// already merges timelines by and the same one the send queue keys on.
public struct ActivityRow: Identifiable, Equatable, Sendable {
    /// Every event about this message, oldest first.
    public let actions: [AgentAction]
    /// All their stages folded together, which is the only way the pipeline reads
    /// as one story: the draft row holds the model's seconds and the delivery row
    /// holds the queue's, and no single row holds both.
    public let timeline: ActionTimeline

    /// The row's identity *is* the newest event's id, so selection stays an
    /// `Int64` and the detail pane keeps working on an `AgentAction` unchanged.
    /// A synthetic id here would have meant translating it back at every use.
    public var id: Int64 { latest.id }

    /// What the row says happened, and what the detail pane opens onto.
    ///
    /// The newest event rather than the first. A message that was drafted and then
    /// sent has been *sent*, and a table that titled that line 초안 would report
    /// the app as having stopped halfway.
    public var latest: AgentAction { actions[actions.count - 1] }

    /// The instant the row sorts and displays by — when this message was first
    /// acted on, not when the last event landed. Sorting by the last event would
    /// move a line down the table while somebody read it, because a draft waiting
    /// in the queue gets stamped again every ten seconds.
    public var startedAt: Date { actions[0].createdAt }

    /// How far the whole message got. Read off the merged timeline, never off one
    /// event: the 전송 row carries no 판단 stamp and the 초안 row carries no 전송,
    /// so either alone would answer for the wrong part of the story.
    public var reach: ActionReach { timeline.reach }

    /// Whether this row is a 관리자 명령(콘솔) reply rather than a message outcome. A
    /// console reply is a single `.commanded` event keyed on the command line and
    /// nothing merges into it, so any `.commanded` event marks the whole row one —
    /// which is how the filter keeps 관리자 명령 on their own switch.
    public var isCommand: Bool {
        actions.contains { $0.kind == .commanded }
    }

    /// The event in this row that kept what the reply answered — the trigger line
    /// and, when it was recorded, the run of conversation around it. A 전송 row
    /// keeps neither; the draft it came from does, which is why this is read off
    /// the group rather than the newest event. Nil only when nothing in the row
    /// kept either — an opener, or a sweep's own record, where there was no
    /// incoming message to show.
    public var answeredContextAction: AgentAction? {
        actions.first { $0.answeredRun.map { !$0.lines.isEmpty } ?? false }
            ?? actions.first { !($0.triggerText ?? "").isEmpty }
    }

    /// What triggered this reply — a mention, a direct message, or a group the
    /// account joined on its own. A 전송 row does not store it; the draft it came
    /// from does, so it is read off the group like the trigger line beside it.
    public var replyTrigger: ReplyTrigger? {
        actions.compactMap(\.replyMode).first
    }

    /// How many events are folded here. One means nothing was folded, and the
    /// screen says nothing rather than 「1개」.
    public var eventCount: Int { actions.count }

    public init(actions: [AgentAction]) {
        precondition(!actions.isEmpty, "빈 활동으로 줄을 만들 수 없습니다")
        let ordered = actions.sorted { $0.id < $1.id }
        self.actions = ordered
        timeline = ordered.reduce(ActionTimeline()) { $0.merging($1.timeline) }
    }

    /// Groups a flat history into rows, keeping the order it arrived in.
    ///
    /// Not sorted here. The history comes from `AgentActionLog.recent(limit:)`
    /// already newest-first, and re-sorting would both second-guess that query and
    /// leave rows that share an instant in whatever order the sort algorithm
    /// happens to produce — the same instability `ActionStage.order` exists to fix
    /// one layer down. A group takes the position of its first event.
    ///
    /// Actions with no trigger message stand alone. They are the ones nobody sent
    /// — a manual 먼저 말 걸기, a sweep's own record — and folding them by a nil key
    /// would collect every unrelated one into a single line.
    public static func rows(from actions: [AgentAction]) -> [ActivityRow] {
        var order: [String] = []
        var grouped: [String: [AgentAction]] = [:]

        for action in actions {
            let key = action.triggerMessageID.map { "\(action.chatRoomID)\u{1}\($0)" }
                ?? "action\u{1}\(action.id)"
            if grouped[key] == nil { order.append(key) }
            grouped[key, default: []].append(action)
        }

        return order.compactMap { grouped[$0] }.map(ActivityRow.init(actions:))
    }
}
