import SwiftUI
import TalkFlowDomain

/// The stages one reply passed through, with how long each took.
///
/// Reads down rather than across: the pane is narrow, the stage names are the
/// part being scanned, and a horizontal bar chart of eight segments would spend
/// its width on the segments too small to see.
struct ActionTimelineBlock: View {
    let section: ActionTimelineSection

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("걸린 시간").font(.headline)
                Spacer()
                Text("전체 \(section.total)")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(section.rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { Divider() }
                    line(row)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func line(_ row: ActionTimelineSection.Row) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(row.time)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text(row.stage.title)
                    .font(.callout)
                Spacer(minLength: 8)
                if let elapsed = row.elapsed {
                    // The slowest stage is the answer to the question this
                    // section is opened to ask, so it is the one thing here that
                    // is allowed to be loud.
                    Text("+\(elapsed)")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(row.isSlowest ? .orange : .secondary)
                        .fontWeight(row.isSlowest ? .semibold : .regular)
                }
            }
            if let note = row.note {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
