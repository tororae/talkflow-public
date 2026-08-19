import Foundation
import TalkFlowDomain

/// What the 활동 detail pane shows above a record: the run of conversation the
/// action answered, or — for a row written before runs were recorded — the one
/// trigger line those rows carry.
///
/// A value rather than branches inside the view. The fallback is the part that
/// must not break, since an old row going blank would take the whole record with
/// it, and a SwiftUI view cannot be asserted against.
struct AnsweredRunSection: Equatable {
    enum Body: Equatable {
        /// One line and no time, which is everything the older rows kept.
        case triggerOnly(String)
        case run([AnsweredRun.Line])
    }

    /// The two panes name the same thing differently. A draft waiting on a
    /// person is about to answer this run; the record pane also shows 보류, which
    /// answered nothing, so it cannot promise an answer.
    enum Voice {
        case answering
        case recorded

        func title(lineCount: Int) -> String {
            switch self {
            case .answering: lineCount > 1 ? "이 대화에 답합니다" : "이 메시지에 답합니다"
            case .recorded: lineCount > 1 ? "판단한 대화" : "촉발 메시지"
            }
        }
    }

    let title: String
    let body: Body
    /// Said out loud when only part of the run was kept. The model read those
    /// messages; the record did not keep them, and showing what is left as the
    /// whole run is the misreading this screen exists to end.
    let omittedNote: String?

    static func of(_ action: AgentAction, voice: Voice) -> AnsweredRunSection? {
        if let run = action.answeredRun, !run.lines.isEmpty {
            return AnsweredRunSection(
                title: voice.title(lineCount: run.lines.count),
                body: .run(run.lines),
                omittedNote: run.omittedCount > 0
                    ? "답한 대화 중 앞선 \(run.omittedCount)개 메시지는 기록에 남기지 않았습니다."
                    : nil
            )
        }

        guard let text = action.triggerText, !text.isEmpty else { return nil }
        return AnsweredRunSection(
            title: voice.title(lineCount: 1),
            body: .triggerOnly("\(action.triggerSenderName ?? "상대"): \(text)"),
            omittedNote: nil
        )
    }
}
