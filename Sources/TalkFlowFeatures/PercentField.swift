import SwiftUI
import TalkFlowDomain

/// A 0–100 field, without the row it sits in.
///
/// Lifted out of `RoomInterjectionChanceRow` when 집중 시간 arrived needing two
/// more of them. The row keeps its own title and help button because those are
/// what it is; this is the part that holds typed text, refuses what will not
/// parse, and reports only what does.
///
/// Held text rather than a binding straight to the policy, and that is the whole
/// reason this is a view. Bound directly, the stored value is written back on
/// every keystroke: "10" could never become "100" — the field rewrote itself
/// between the two keys — and Hangul was eaten mid-composition on the settings
/// screen the same way.
struct PercentField: View {
    /// What the held text belongs to. The view keeps its identity while the room
    /// under it changes, so it has to be told when the text it owns stopped
    /// describing what is on screen.
    private let seedID: String
    private let title: String
    private let chance: InterjectionChance
    private let isEnabled: Bool
    private let onChange: (InterjectionChance) -> Void

    @State private var typed: String
    @State private var issue: String?

    init(
        seedID: String,
        title: String,
        chance: InterjectionChance,
        isEnabled: Bool = true,
        onChange: @escaping (InterjectionChance) -> Void
    ) {
        self.seedID = seedID
        self.title = title
        self.chance = chance
        self.isEnabled = isEnabled
        self.onChange = onChange
        _typed = State(initialValue: String(chance.percent))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                // The label belongs to whatever placed this field. Passing the
                // title as the placeholder drew the number twice.
                TextField(title, text: $typed)
                    .settingsNumberField(width: 56)
                    .onChange(of: typed) { _, _ in apply() }
                Text("%")
                    .foregroundStyle(.secondary)
            }
            .disabled(!isEnabled)

            if let issue {
                Label(issue, systemImage: "exclamationmark.circle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
        .onChange(of: seedID) { _, _ in reseed() }
    }

    /// Typing only ever changes a field that is live. Reseeding for another room
    /// writes here too, and without the guard opening a room would save it.
    private func apply() {
        guard isEnabled else { return }
        let trimmed = typed.trimmingCharacters(in: .whitespaces)
        guard let percent = Int(trimmed), (0...100).contains(percent) else {
            // The refused text stays where it was typed. Putting the last good
            // value back under somebody's cursor is what makes a field
            // impossible to type a three-digit number into.
            issue = "0에서 100 사이로 적어 주세요."
            return
        }

        issue = nil
        guard percent != chance.percent else { return }
        onChange(InterjectionChance(percent: percent))
    }

    private func reseed() {
        typed = String(chance.percent)
        issue = nil
    }
}
