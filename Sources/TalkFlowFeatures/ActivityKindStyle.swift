import SwiftUI
import TalkFlowDomain

/// How one recorded action is labelled wherever it appears, so the table and
/// the detail pane cannot drift into naming the same row two different things.
enum ActivityKindStyle {
    /// A draft nobody has answered yet says so. "초안 생성" describes what the
    /// app did; what the user needs from the column is that it is their turn.
    static func title(for action: AgentAction, isPending: Bool) -> String {
        if isPending { return "검토 대기" }
        // An opener the model passed on is still an attempt at one, and the
        // column has to say that nothing was said. "먼저 말 걸기" on a row with no
        // text reads as a message that went out.
        if action.kind == .opened, action.replyText == nil { return "말 걸지 않음" }
        return action.kind.title
    }

    static func symbol(for action: AgentAction, isPending: Bool) -> String {
        switch action.kind {
        case .held: "pause.circle"
        case .drafted: isPending ? "tray.full" : "square.and.pencil"
        case .opened: opened(action, isPending: isPending)
        case .sent: "paperplane.fill"
        case .failed: "exclamationmark.triangle"
        case .dismissed: "xmark.circle"
        case .commanded: "terminal"
        }
    }

    static func tint(for action: AgentAction, isPending: Bool) -> Color {
        switch action.kind {
        case .held: .secondary
        case .drafted: isPending ? .accentColor : .secondary
        case .opened: action.replyText == nil ? .secondary : (isPending ? .accentColor : .secondary)
        case .sent: .green
        case .failed: .orange
        case .dismissed: .secondary
        case .commanded: .green
        }
    }

    private static func opened(_ action: AgentAction, isPending: Bool) -> String {
        guard action.replyText != nil else { return "pause.circle" }
        return isPending ? "tray.full" : "text.bubble"
    }
}
