import SwiftUI
import TalkFlowDomain

/// 끼어들기 확률, typed rather than chosen.
///
/// A menu is what this setting used to be — 꺼짐 / 낮음 / 보통 — and a menu is what
/// let two of those three words stand for the same behaviour for months. A field
/// that takes 40 cannot make that mistake: whatever it holds is what the room
/// does.
///
/// Its own view because of the field. Text bound straight to the policy is
/// rewritten from the stored value on every keystroke, which is how "10" could
/// never become "100" in the interval fields and how the settings screen used to
/// eat Hangul as it was composed. So the typed text is held here, only a number
/// that parses is reported outward, and a refused entry stays on screen with the
/// reason beside it.
struct RoomInterjectionChanceRow: View {
    /// What the held text belongs to. The view keeps its identity while the room
    /// under it changes, so it has to be told when the text it owns stopped
    /// describing what is on screen.
    private let roomID: String
    private let chance: InterjectionChance
    private let isEnabled: Bool
    private let onChange: (InterjectionChance) -> Void

    @State private var typed: String
    @State private var issue: String?

    init(
        roomID: String,
        chance: InterjectionChance,
        isEnabled: Bool,
        onChange: @escaping (InterjectionChance) -> Void
    ) {
        self.roomID = roomID
        self.chance = chance
        self.isEnabled = isEnabled
        self.onChange = onChange
        _typed = State(initialValue: String(chance.percent))
    }

    var body: some View {
        SettingHelpRow("끼어들기 확률", help: .interjectionChance) {
            HStack(spacing: 6) {
                // The label is the row's, not the field's. Passing "100" as
                // the title drew the number a second time beside the box.
                TextField("끼어들기 확률", text: $typed)
                    .settingsNumberField(width: 56)
                    .onChange(of: typed) { _, _ in apply() }
                Text("%")
                    .foregroundStyle(.secondary)
            }
            .disabled(!isEnabled)
        }
        .onChange(of: roomID) { _, _ in reseed() }

        if let issue {
            Label(issue, systemImage: "exclamationmark.circle")
                .font(.footnote)
                .foregroundStyle(.orange)
        }
    }

    /// Typing only ever changes a room whose field is live. Reseeding for another
    /// room writes here too, and without the guard opening a room would save it.
    private func apply() {
        guard isEnabled else { return }
        let trimmed = typed.trimmingCharacters(in: .whitespaces)
        guard let percent = Int(trimmed) else {
            issue = "0에서 100 사이의 숫자로 적어 주세요."
            return
        }
        guard (0...100).contains(percent) else {
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
