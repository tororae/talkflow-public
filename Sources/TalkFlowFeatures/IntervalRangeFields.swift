import SwiftUI
import TalkFlowDomain

/// The two number fields and the unit that make up a typed range, wherever one
/// is typed.
///
/// Its own view because of the fields. A field bound straight to the policy is
/// rewritten from the stored value on every keystroke, which is how the keyword
/// field became impossible to type a second word into and how the settings screen
/// ate Hangul as it was composed. So the typed text is held here, only a value
/// that parses is reported outward, and nothing on screen is rewritten while
/// somebody is in the middle of a number.
///
/// Shared rather than copied because getting that wrong is the expensive part,
/// and two settings are typed this way now. What they do not share is which
/// numbers they accept, so the bounds arrive as a value.
///
/// The unit picker is also where 판단 주기 chooses between a clock and a count of
/// messages. A second control for that would be a second thing to read on a form
/// that already has one word for it, and a range cannot be half of each anyway.
struct IntervalRangeFields: View {
    /// What the held text belongs to. The view keeps its identity while the room
    /// under it changes, so it has to be told when the text it owns stopped
    /// describing what is on screen.
    private let seedID: String
    private let interval: JudgementInterval
    private let input: JudgementIntervalInput
    private let isEnabled: Bool
    /// Called for every value that parses, whether or not it differs from the
    /// stored one. The caller decides what to do with it — one of them holds it
    /// for the moment its own switch is turned on.
    private let report: (JudgementInterval) -> Void

    @State private var unit: JudgementIntervalInput.Unit
    @State private var shortest: String
    @State private var longest: String
    @State private var issue: String?

    init(
        seedID: String,
        interval: JudgementInterval,
        input: JudgementIntervalInput,
        isEnabled: Bool,
        report: @escaping (JudgementInterval) -> Void
    ) {
        self.seedID = seedID
        self.interval = interval
        self.input = input
        self.isEnabled = isEnabled
        self.report = report

        let unit = JudgementIntervalInput.unit(for: interval)
        _unit = State(initialValue: unit)
        _shortest = State(initialValue: input.typed(interval.shortest, in: unit))
        // Blank for a fixed interval, which is what the placeholder beside it
        // promises: one number is the common case and nobody should have to type
        // it twice to get it.
        _longest = State(
            initialValue: interval.isFixed ? "" : input.typed(interval.longest, in: unit)
        )
    }

    var body: some View {
        // One field per row rather than a range on a single line. The inspector
        // is narrow enough that a label, two fields, a unit and a joining word
        // wrap into each other, and a form that cannot be read is worse than one
        // that takes two lines.
        //
        // Left visible while the setting is off, the way the active-hours pickers
        // are, so the cadence that would apply can be read before the switch is
        // flipped.
        LabeledContent(unit.measure.shortestTitle) {
            HStack(spacing: 6) {
                number(floorPrompt, text: $shortest)
                // Every unit is one Hangul syllable, so the menu keeps the same
                // width whether or not this setting offers 개, and the row below
                // stays lined up with it.
                Picker("단위", selection: $unit) {
                    ForEach(input.units, id: \.self) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
                .onChange(of: unit) { _, _ in apply() }
            }
        }
        .disabled(!isEnabled)
        // Opening another room hands this view new values while it keeps its
        // identity, so the text it owns has to be put back by hand. Without it
        // the next room opens showing the last one's numbers.
        .onChange(of: seedID) { _, _ in reseed() }
        // And the stored value can change unit without anybody touching the
        // picker: 즉시 keeps no unit, so switching the cycle off and on again
        // brings back a suggestion in seconds while the picker still reads 개.
        // It cannot fight the user, because a unit they picked themselves is
        // already the one the value came back with.
        .onChange(of: interval.measure) { _, measure in
            guard measure != unit.measure else { return }
            reseed()
        }

        LabeledContent(unit.measure.longestTitle) {
            HStack(spacing: 6) {
                number("같음", text: $longest)
                // The unit is chosen once, above. Repeating it as a second picker
                // would let the two ends disagree about what they mean.
                Text(unit.title)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 34, alignment: .leading)
            }
        }
        .disabled(!isEnabled)

        if let issue {
            Label(issue, systemImage: "exclamationmark.circle")
                .font(.footnote)
                .foregroundStyle(.orange)
        }
    }

    private func number(_ prompt: String, text: Binding<String>) -> some View {
        TextField(prompt, text: text)
            .settingsNumberField()
            .onChange(of: text.wrappedValue) { _, _ in apply() }
    }

    /// Typing only ever changes a setting that is already on. Reseeding for
    /// another room writes to these fields too, and without this guard a room
    /// left off would be switched on by the act of being opened.
    private func apply() {
        guard isEnabled else { return }
        switch input.interval(shortest: shortest, longest: longest, unit: unit) {
        case let .success(parsed):
            issue = nil
            report(parsed)
        case let .failure(refusal):
            // The refused text stays where it was typed. Restoring the last good
            // value under somebody's cursor is what makes a field impossible to
            // type a two-digit number into.
            issue = input.explanation(refusal, in: unit)
        }
    }

    private func reseed() {
        let unit = JudgementIntervalInput.unit(for: interval)
        self.unit = unit
        shortest = input.typed(interval.shortest, in: unit)
        longest = interval.isFixed ? "" : input.typed(interval.longest, in: unit)
        issue = nil
    }

    /// The floor in the unit currently shown, rounded up so the placeholder is
    /// never a number the field would refuse.
    private var floorPrompt: String {
        String(max(1, Int((input.bounds(for: unit).lowest / unit.span).rounded(.up))))
    }
}
