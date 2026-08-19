import SwiftUI

/// What the `?` opens.
///
/// Headings and short lines rather than a paragraph. These explanations exist
/// because a setting was misread once already, and a block of prose is exactly
/// what does not get read the second time either. A heading and two lines can be
/// found by eye, which is the whole point of opening it.
struct SettingHelpCard: View {
    let help: SettingHelp

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(help.title)
                    .font(.headline)
                Text(help.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(help.topics) { topic in
                VStack(alignment: .leading, spacing: 6) {
                    Text(topic.question.heading)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(topic.lines, id: \.text) { line in
                        Self.row(line)
                    }
                }
            }
        }
        .padding(18)
        // Wide enough for two lines a sentence, narrow enough to stay a card. The
        // height follows the content: a popover with a scroll view in it has no
        // ideal size, and one that has to be scrolled is the paragraph again.
        .frame(width: 340, alignment: .leading)
    }

    private static func row(_ line: SettingHelp.Line) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("·")
                .foregroundStyle(.secondary)
            sentence(line)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// One `Text`, not two views side by side: an option's name and its sentence
    /// have to wrap as a single paragraph, or a long line breaks underneath the
    /// name instead of continuing beside it.
    private static func sentence(_ line: SettingHelp.Line) -> Text {
        guard let lead = line.lead else { return Text(line.text) }
        return Text("\(lead)  ").fontWeight(.semibold) + Text(line.text)
    }
}
