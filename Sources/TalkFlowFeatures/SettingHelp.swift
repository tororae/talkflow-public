import Foundation

/// One setting explained in the order the misunderstanding actually happens.
///
/// A value rather than text inside a view body, for two reasons. A `?` that opens
/// an empty card is worse than no `?` at all, and only a value can be walked by a
/// test. And these sentences describe rules that keep moving — `낮음` and `보통`
/// were the same setting until recently, and the screen said otherwise the whole
/// time — so they are easier to keep honest sitting together than scattered one
/// per view.
struct SettingHelp: Equatable {
    /// One short line. Long enough to say a thing, short enough that the card is
    /// scanned rather than studied.
    struct Line: Equatable {
        /// The option or condition the line is about — `낮음`, `상시 전송` — shown
        /// ahead of the sentence so a picker's choices can be found by eye.
        let lead: String?
        let text: String

        init(_ lead: String, _ text: String) {
            self.lead = lead
            self.text = text
        }
    }

    /// The four questions, in the order they get asked.
    ///
    /// `doesNot` is last and never left out. Every misunderstanding these
    /// settings have caused so far was somebody expecting one to do something it
    /// does not do, and that is the line that ends the search.
    enum Question: String, CaseIterable, Sendable {
        case does
        case applies
        case costs
        case doesNot

        var heading: String {
            switch self {
            case .does: "무엇을 하나"
            case .applies: "언제 적용되나"
            case .costs: "비용"
            case .doesNot: "하지 않는 것"
            }
        }
    }

    struct Topic: Equatable, Identifiable {
        let question: Question
        let lines: [Line]

        var id: String { question.rawValue }
    }

    let title: String
    /// One sentence. If the user reads nothing else on the card, this is it.
    let summary: String
    let topics: [Topic]
}

/// A line with nothing to name in front of it is just its sentence, so writing
/// the catalog does not mean writing `Line(...)` around every string. String
/// interpolation comes along because several lines quote a number the engine
/// owns rather than repeating it.
extension SettingHelp.Line: ExpressibleByStringInterpolation {
    init(stringLiteral value: String) {
        lead = nil
        text = value
    }
}

extension SettingHelp.Topic {
    static func does(_ lines: SettingHelp.Line...) -> Self {
        Self(question: .does, lines: lines)
    }

    static func applies(_ lines: SettingHelp.Line...) -> Self {
        Self(question: .applies, lines: lines)
    }

    static func costs(_ lines: SettingHelp.Line...) -> Self {
        Self(question: .costs, lines: lines)
    }

    static func doesNot(_ lines: SettingHelp.Line...) -> Self {
        Self(question: .doesNot, lines: lines)
    }
}
