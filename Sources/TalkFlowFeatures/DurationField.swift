import SwiftUI

/// A duration chosen from the usual answers, or typed when none of them is the
/// answer.
///
/// The presets alone were the whole control, and a list of five numbers is a
/// guess at what everybody wants. The one who wants seven minutes had no way to
/// say so, and picking 5분 instead is the kind of compromise a person stops
/// trusting the screen over.
///
/// The typed text is held here rather than bound to the stored value, for the
/// reason `IntervalRangeFields` documents at length: a field rewritten from the
/// model on every keystroke cannot be typed into, and eats Hangul mid-composition.
/// Only a number that parses is reported outward.
struct DurationField: View {
    /// What the held text belongs to. This view keeps its identity while the room
    /// under it changes, so it has to be told when its text stopped describing
    /// what is on screen.
    private let seedID: String
    private let seconds: TimeInterval
    private let presets: [TimeInterval]
    private let isEnabled: Bool
    private let report: (TimeInterval) -> Void

    @State private var isTyping: Bool
    @State private var typed: String
    @State private var unit: Unit

    enum Unit: String, CaseIterable, Identifiable {
        case seconds
        case minutes
        case hours

        var id: String { rawValue }
        var title: String {
            switch self {
            case .seconds: "초"
            case .minutes: "분"
            case .hours: "시간"
            }
        }

        var span: TimeInterval {
            switch self {
            case .seconds: 1
            case .minutes: 60
            case .hours: 3600
            }
        }
    }

    init(
        seedID: String,
        seconds: TimeInterval,
        presets: [TimeInterval],
        isEnabled: Bool = true,
        report: @escaping (TimeInterval) -> Void
    ) {
        self.seedID = seedID
        self.seconds = seconds
        self.presets = presets
        self.isEnabled = isEnabled
        self.report = report

        let unit = Self.naturalUnit(for: seconds)
        _isTyping = State(initialValue: !presets.contains(seconds))
        _unit = State(initialValue: unit)
        _typed = State(initialValue: seconds > 0 ? Self.trimmed(seconds / unit.span) : "")
    }

    var body: some View {
        HStack(spacing: 8) {
            Picker("", selection: choice) {
                ForEach(presets, id: \.self) { Text(Self.title(for: $0)).tag(Choice.preset($0)) }
                Divider()
                Text("직접 입력").tag(Choice.typed)
            }
            .labelsHidden()
            .fixedSize()

            if isTyping {
                TextField("직접 입력한 시간", text: $typed)
                    .settingsNumberField(width: 60)
                    .onChange(of: typed) { _, _ in reportTyped() }
                Picker("", selection: $unit) {
                    ForEach(Unit.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
                .onChange(of: unit) { _, _ in reportTyped() }
            }
        }
        .disabled(!isEnabled)
        // The room under this view can change while the view stays alive, and
        // the text it is holding belonged to the previous one.
        .onChange(of: seedID) { _, _ in reseed() }
    }

    private enum Choice: Hashable {
        case preset(TimeInterval)
        case typed
    }

    private var choice: Binding<Choice> {
        Binding(
            get: { isTyping ? .typed : .preset(seconds) },
            set: { selection in
                switch selection {
                case let .preset(value):
                    isTyping = false
                    report(value)
                case .typed:
                    // Seeded from whatever is in force, so switching to 직접 입력
                    // starts from the current answer rather than from nothing.
                    isTyping = true
                    unit = Self.naturalUnit(for: seconds)
                    typed = seconds > 0 ? Self.trimmed(seconds / unit.span) : ""
                }
            }
        )
    }

    /// Silent on text that does not parse. A half-typed number is not a value,
    /// and refusing it out loud on every keystroke is how a field becomes
    /// unusable — the same lesson `IntervalRangeFields` records.
    private func reportTyped() {
        let text = typed.trimmingCharacters(in: .whitespaces)
        guard let value = Double(text), value >= 0 else { return }
        report(value * unit.span)
    }

    private func reseed() {
        let natural = Self.naturalUnit(for: seconds)
        isTyping = !presets.contains(seconds)
        unit = natural
        typed = seconds > 0 ? Self.trimmed(seconds / natural.span) : ""
    }

    /// The largest unit the value divides into cleanly, so 300초 comes back as
    /// 5분 rather than as a number nobody would have typed.
    static func naturalUnit(for seconds: TimeInterval) -> Unit {
        guard seconds > 0 else { return .minutes }
        if seconds.truncatingRemainder(dividingBy: 3600) == 0 { return .hours }
        if seconds.truncatingRemainder(dividingBy: 60) == 0 { return .minutes }
        return .seconds
    }

    static func title(for seconds: TimeInterval) -> String {
        guard seconds > 0 else { return "제한 없음" }
        let unit = naturalUnit(for: seconds)
        return "\(trimmed(seconds / unit.span))\(unit.title)"
    }

    private static func trimmed(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }
}
