import SwiftUI
import TalkFlowDomain

/// The conversation an action answered, one line per message in the order it was
/// said.
///
/// Its own view because the two panes need different heights out of it. The
/// review pane has no scroll view — a text editor inside one fights the pointer
/// for the gesture — so a long run scrolls inside this block there. The record
/// pane scrolls already, and a scroll view nested in a scroll view is worse than
/// a tall page.
struct AnsweredRunBlock: View {
    let section: AnsweredRunSection
    let maxHeight: CGFloat?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(section.title).font(.headline)
            if let note = section.omittedNote {
                Label(note, systemImage: "scissors")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            quoted
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    @ViewBuilder
    private var quoted: some View {
        switch section.body {
        case let .triggerOnly(text):
            Text(text).frame(maxWidth: .infinity, alignment: .leading)
        case let .run(lines):
            bounded(messages(lines))
        }
    }

    /// One message a line: the time, who said it, and what they said. A run of
    /// one — still the common case — reads as the single quoted line it always
    /// was, and a batch of twenty reads as the exchange it is.
    private func messages(_ lines: [AnsweredRun.Line]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(lines, id: \.messageID) { line in
                Self.text(for: line).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// Hugs a short run and scrolls a long one. A scroll view on its own claims
    /// the whole allowance whatever it holds, which would put an empty box under
    /// the single message that most records still are.
    @ViewBuilder
    private func bounded(_ content: some View) -> some View {
        if let maxHeight {
            ViewThatFits(in: .vertical) {
                content
                ScrollView { content }
            }
            .frame(maxHeight: maxHeight)
        } else {
            content
        }
    }

    private static func text(for line: AnsweredRun.Line) -> Text {
        Text(timeFormatter.string(from: line.sentAt))
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            + Text("  \(line.senderName): ").foregroundStyle(.secondary)
            + Text(line.body)
    }

    /// Time only. A run spans minutes, and the record's own 시각 row already
    /// says which day it was.
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}
