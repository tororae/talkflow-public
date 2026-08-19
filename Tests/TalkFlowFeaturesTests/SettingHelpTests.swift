import Foundation
import Testing
@testable import TalkFlowFeatures

/// A `?` that opens an empty card is worse than no `?` at all: it costs a click
/// to learn nothing, and it teaches the user that the buttons are not worth
/// pressing. These walk every key a screen can ask for.
@Test
func everySettingWithAQuestionMarkHasSomethingBehindIt() {
    for key in SettingHelpKey.allCases {
        let help = SettingHelp(key)

        #expect(!help.title.isEmpty, "\(key.rawValue) has no title")
        #expect(!help.summary.isEmpty, "\(key.rawValue) has no summary")
        #expect(!help.topics.isEmpty, "\(key.rawValue) has no topics")

        for topic in help.topics {
            #expect(!topic.lines.isEmpty, "\(key.rawValue)/\(topic.question.rawValue) has no lines")
            for line in topic.lines {
                #expect(!line.text.isEmpty, "\(key.rawValue)/\(topic.question.rawValue) has an empty line")
                #expect(line.lead?.isEmpty != true, "\(key.rawValue) has a line led by nothing")
            }
        }
    }
}

/// The one that would have saved the most time. Every misunderstanding these
/// settings caused was somebody expecting one to do something it does not do —
/// 자발 개입 in a 1:1 room, 적극성 changing how often a room speaks — so a card
/// without that section is a card that stops one line short.
@Test
func everyExplanationSaysWhatTheSettingDoesAndWhatItDoesNotDo() {
    for key in SettingHelpKey.allCases {
        let questions = SettingHelp(key).topics.map(\.question)

        #expect(questions.contains(.does), "\(key.rawValue) never says what it does")
        #expect(questions.contains(.doesNot), "\(key.rawValue) never says what it does not do")
    }
}

/// The order is the order somebody reads in when they are confused: what is
/// this, when does it bite, what does it cost, and what am I wrong about.
@Test
func topicsReadInTheOrderTheQuestionsGetAsked() {
    for key in SettingHelpKey.allCases {
        let questions = SettingHelp(key).topics.map(\.question)
        let expected = SettingHelp.Question.allCases.filter(questions.contains)

        #expect(questions == expected, "\(key.rawValue) answers its questions out of order")
        #expect(Set(questions).count == questions.count, "\(key.rawValue) answers a question twice")
    }
}

/// A card is read at a glance or not at all. The user asked for line breaks
/// instead of prose in as many words, and a paragraph smuggled into one `Line`
/// is the same wall of text with a bullet in front of it.
@Test
func noSingleLineGrowsIntoAParagraph() {
    for key in SettingHelpKey.allCases {
        let help = SettingHelp(key)
        #expect(help.summary.count <= 60, "\(key.rawValue) summary is too long to be a summary")

        for line in help.topics.flatMap(\.lines) {
            #expect(line.text.count <= 120, "\(key.rawValue) has a line that reads as a paragraph")
        }
    }
}

/// Costs are the reason the user asked for these cards. A setting that spends
/// money on every message, or sends photos off the machine, has to say so where
/// it is switched on.
@Test
func theSettingsThatSpendSomethingSayWhatTheySpend() {
    let spenders: [SettingHelpKey] = [
        .responseMode,
        .interjectionChance,
        .judgementInterval,
        .readsPhotos,
        .deliveryMode
    ]

    for key in spenders {
        let costs = SettingHelp(key).topics.first { $0.question == .costs }
        #expect(costs != nil, "\(key.rawValue) never says what it costs")
    }
}

/// What the identity `switch` behind `SettingHelp(_:)` cannot notice.
///
/// A missing key is a compile error there, which is the point of writing it as a
/// switch. A *mis-wired* one is not: `case .roomKeywords: self = .globalKeywords`
/// compiles, and it reads right in a column of thirty near-identical lines. The
/// `?` beside one setting would then open another setting's card, and every other
/// test here would still pass, because each of them walks the keys one at a time
/// and asks only whether the words are any good. Distinct keys, distinct cards.
@Test
func noTwoSettingsOpenTheSameCard() {
    let keys = SettingHelpKey.allCases

    for (offset, key) in keys.enumerated() {
        for other in keys.dropFirst(offset + 1) {
            #expect(
                SettingHelp(key) != SettingHelp(other),
                "\(key.rawValue) and \(other.rawValue) open the same card"
            )
        }
    }
}
