import Foundation
import GRDB

/// The `room_policies` row, with its column names written down once.
///
/// The list used to exist five times in `RoomPolicyRepository.save`: the INSERT's
/// columns, the `DO UPDATE SET` list, 48 positional placeholders, the arguments
/// array, and the reader. Each had to be in the same order as the one beside it
/// and nothing checked that they were, so two lines swapped compiled, saved, and
/// silently put one setting's value in another setting's column. Here the names
/// live in `CodingKeys` and nowhere else: GRDB builds the INSERT, the
/// `ON CONFLICT DO UPDATE SET` and the decode from them, so a new room setting is
/// one property and one key instead of five coordinated edits.
///
/// Every property is the column's own type — text stays text, a flag stays a
/// number — and the enums, the JSON lists and the fallbacks are resolved in
/// `RoomPolicyRow+RoomPolicy`. A row type holding `ResponseMode` would refuse a
/// whole policy over one word it did not recognise; that judgement belongs with
/// the mapping, which has always made it per field.
///
/// Only the two genuinely nullable columns are optional. Every other column is
/// `NOT NULL`: the ones added after v1 carry a `.defaults(to:)` the migration
/// wrote into the rows already on disk, and `response_mode`, `delivery_mode` and
/// `minimum_interval` are v1 columns with no default, where the constraint alone
/// is the guarantee — a row cannot exist without them. Either way a non-optional
/// decode cannot throw over a value that is not there. The column-by-column list
/// of which migration guarantees which value is in `RoomPolicy.init(row:)`.
struct RoomPolicyRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "room_policies"

    var accountFingerprint: String
    var chatRoomID: String
    var responseMode: String
    var interjectionChance: Int
    var deliveryMode: String
    var minimumInterval: Double
    var judgementInterval: Double
    var judgementIntervalLongest: Double
    var judgementIntervalUnit: String
    var activeHoursLimited: Bool
    var activeHoursStartMinute: Int
    var activeHoursEndMinute: Int
    var readsPhotos: Bool
    var webSearch: Bool
    var readsLinks: Bool
    var conversationOpener: String
    var conversationOpenerShortest: Double
    var conversationOpenerLongest: Double
    var responseKeywords: String
    /// Null is "follow 설정"; an empty string is a room judging with no condition
    /// at all. Two different states, so this column cannot be non-optional.
    var answeringCondition: String?
    var usesOwnStyle: Bool
    var styleTone: String
    var styleLength: String
    var styleEmojiUse: String
    var styleAssertiveness: String
    var remembersConversation: Bool
    var answersReplies: Bool
    var burningEnabled: Bool
    var burningChance: Int
    var burningDurationShortest: Double
    var burningDurationLongest: Double
    var burningCooldownShortest: Double
    var burningCooldownLongest: Double
    var burningInterjectionChance: Int
    var burningMinimumInterval: Double
    var burningJudgementInterval: Double
    var burningJudgementIntervalLongest: Double
    var announcementTransitions: String
    var announcementRecentWindow: Double
    var announcementDelivery: String
    var remembersPeople: Bool
    var openerHoursLimited: Bool
    var openerHoursStartMinute: Int
    var openerHoursEndMinute: Int
    var openerRepeatLimit: Int
    var openerRepeatTopic: String
    var openerCadencePausesOutsideHours: Bool
    /// Nullable like `answeringCondition`, and for the same reason: no hint at all
    /// is not the same as a hint somebody cleared to nothing.
    var openerPromptHint: String?

    /// The only place a `room_policies` column name is written in Swift.
    ///
    /// Declaration order above is the order GRDB names the columns in, which is
    /// why it still matches the hand-written INSERT this replaced — the traced
    /// SQL can be read against the old one line for line. Nothing depends on the
    /// order any more: the compiler matches these cases to the properties by
    /// name, so a case in the wrong place is a build error rather than a room
    /// answering with another room's numbers.
    enum CodingKeys: String, CodingKey {
        case accountFingerprint = "account_fingerprint"
        case chatRoomID = "chat_id"
        case responseMode = "response_mode"
        case interjectionChance = "interjection_chance"
        case deliveryMode = "delivery_mode"
        case minimumInterval = "minimum_interval"
        case judgementInterval = "judgement_interval"
        case judgementIntervalLongest = "judgement_interval_longest"
        case judgementIntervalUnit = "judgement_interval_unit"
        case activeHoursLimited = "active_hours_limited"
        case activeHoursStartMinute = "active_hours_start_minute"
        case activeHoursEndMinute = "active_hours_end_minute"
        case readsPhotos = "reads_photos"
        case webSearch = "web_search"
        case readsLinks = "reads_links"
        case conversationOpener = "conversation_opener"
        case conversationOpenerShortest = "conversation_opener_shortest"
        case conversationOpenerLongest = "conversation_opener_longest"
        case responseKeywords = "response_keywords"
        case answeringCondition = "answering_condition"
        case usesOwnStyle = "uses_own_style"
        case styleTone = "style_tone"
        case styleLength = "style_length"
        case styleEmojiUse = "style_emoji_use"
        case styleAssertiveness = "style_assertiveness"
        case remembersConversation = "remembers_conversation"
        case answersReplies = "answers_replies"
        case burningEnabled = "burning_enabled"
        case burningChance = "burning_chance"
        case burningDurationShortest = "burning_duration_shortest"
        case burningDurationLongest = "burning_duration_longest"
        case burningCooldownShortest = "burning_cooldown_shortest"
        case burningCooldownLongest = "burning_cooldown_longest"
        case burningInterjectionChance = "burning_interjection_chance"
        case burningMinimumInterval = "burning_minimum_interval"
        case burningJudgementInterval = "burning_judgement_interval"
        case burningJudgementIntervalLongest = "burning_judgement_interval_longest"
        case announcementTransitions = "announcement_transitions"
        case announcementRecentWindow = "announcement_recent_window"
        case announcementDelivery = "announcement_delivery"
        case remembersPeople = "remembers_people"
        case openerHoursLimited = "opener_hours_limited"
        case openerHoursStartMinute = "opener_hours_start_minute"
        case openerHoursEndMinute = "opener_hours_end_minute"
        case openerRepeatLimit = "opener_repeat_limit"
        case openerRepeatTopic = "opener_repeat_topic"
        case openerCadencePausesOutsideHours = "opener_cadence_pauses_outside_hours"
        case openerPromptHint = "opener_prompt_hint"
    }
}
