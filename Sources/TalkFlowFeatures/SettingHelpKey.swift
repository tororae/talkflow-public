import Foundation

/// Which setting a `?` belongs to.
///
/// A screen names the key and never holds the words, so the button and its
/// explanation cannot drift apart. `allCases` is what lets a test walk every `?`
/// the app shows and check that something is behind it.
enum SettingHelpKey: String, CaseIterable, Sendable {
    case responseMode
    case interjectionChance
    case answeringCondition
    case deliveryMode
    case judgementInterval
    case minimumInterval
    case answersReplies
    case readsPhotos
    case webSearch
    case readsLinks
    case activeHours
    case conversationOpener
    case conversationSummary
    case remembersPeople
    case personNote
    case personLinks
    case roomCallSigns
    case roomKeywords
    case globalKeywords
    case assertiveness
    case roomResponseStyle
    case sendUsePolicy
    case wakesDisplay
    case burningMode
    case burningChance
    case burningDuration
    case burningCooldown
    case burningValues
    case burningAnnouncement
    case aiModel
}

extension SettingHelp {
    /// A `switch` rather than a dictionary lookup: the compiler, not a test run,
    /// is what should notice a key with no words behind it.
    init(_ key: SettingHelpKey) {
        switch key {
        case .responseMode: self = .responseMode
        case .interjectionChance: self = .interjectionChance
        case .answeringCondition: self = .answeringCondition
        case .deliveryMode: self = .deliveryMode
        case .judgementInterval: self = .judgementInterval
        case .minimumInterval: self = .minimumInterval
        case .answersReplies: self = .answersReplies
        case .readsPhotos: self = .readsPhotos
        case .webSearch: self = .webSearch
        case .readsLinks: self = .readsLinks
        case .activeHours: self = .activeHours
        case .conversationOpener: self = .conversationOpener
        case .conversationSummary: self = .conversationSummary
        case .remembersPeople: self = .remembersPeople
        case .personNote: self = .personNote
        case .personLinks: self = .personLinks
        case .roomCallSigns: self = .roomCallSigns
        case .roomKeywords: self = .roomKeywords
        case .globalKeywords: self = .globalKeywords
        case .assertiveness: self = .assertiveness
        case .roomResponseStyle: self = .roomResponseStyle
        case .sendUsePolicy: self = .sendUsePolicy
        case .wakesDisplay: self = .wakesDisplay
        case .burningMode: self = .burningMode
        case .burningChance: self = .burningChance
        case .burningDuration: self = .burningDuration
        case .burningCooldown: self = .burningCooldown
        case .burningValues: self = .burningValues
        case .burningAnnouncement: self = .burningAnnouncement
        case .aiModel: self = .aiModel
        }
    }
}
