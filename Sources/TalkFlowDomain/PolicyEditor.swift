import Foundation

/// Reads and writes the whitelisted fields of a room's policy for `!세팅` — the
/// write half of the admin console, kept pure and in the domain so it is exercised
/// field by field without a store.
///
/// Only the scalar, enum and toggle fields `!방 <N>` prints are settable. The two
/// free-text ones — 말투 and 답변 조건 — are named there as app-only and never reach
/// here: a sentence typed one console line at a time is how a room's voice gets
/// quietly rewritten by anyone in the room, and that is the one thing the fence
/// around this command cannot make safe. There is no entry for them in the table
/// below, which is the whole of how they stay out: nothing here takes a field name
/// it does not already hold.
///
/// Each field answers three questions in one place — what it accepts (`allowed`),
/// what it holds now (`read`), and how a value folds in (`write`) — so `apply` (set
/// it), `describe` (show the options before a value is given), and the field list
/// all read the same source and cannot drift.
///
/// It said that while answering them in three separate `switch`es keyed on the same
/// Korean string, plus a hand-kept `[String]` list: 19 fields × 4 places, and every
/// omission failed differently. Missing from the list → settable but invisible.
/// Missing from `allowed` → `apply` said 「그런 항목이 없어요」 and `describe` returned
/// nil, so the field silently did not exist. Missing from `current` → `describe`
/// returned nil for a field `allowed` had just admitted. Missing from `write` →
/// every value came back 「그런 값이 아니에요」, valid ones included. One entry per
/// field is what makes those four failures impossible rather than merely absent.
public enum PolicyEditor {
    /// A change made: the updated policy, and the field with its before/after as
    /// they read on `!방 <N>`, so the console can echo 「응답: 멘션에만 응답 → 자동응답」
    /// and a value that changed nothing shows the same word on both sides.
    public struct Applied: Equatable, Sendable {
        public let policy: RoomPolicy
        public let label: String
        public let before: String
        public let after: String

        public init(policy: RoomPolicy, label: String, before: String, after: String) {
            self.policy = policy
            self.label = label
            self.before = before
            self.after = after
        }
    }

    public enum Failure: Error, Equatable, Sendable {
        /// The 항목 keyword matched nothing settable.
        case unknownField
        /// The field is real but the value is not one it takes; `allowed` is the
        /// short list to echo so the operator can retype it.
        case badValue(label: String, allowed: String)
    }

    /// A field's value now and what it accepts — for `!세팅 <N> <항목>`, the step that
    /// shows the options before a value is given.
    public struct FieldInfo: Equatable, Sendable {
        public let label: String
        public let current: String
        public let allowed: String

        public init(label: String, current: String, allowed: String) {
            self.label = label
            self.current = current
            self.allowed = allowed
        }
    }

    /// Every settable field, in the order `!방 <N>` reads them, so `!세팅 <N>` lists
    /// them the same way.
    public static let settableFields = fields.map(\.label)

    /// Folds one value into the policy, or reports why it could not.
    public static func apply(field label: String, value: String, to policy: RoomPolicy) -> Result<Applied, Failure> {
        guard let field = byLabel[label] else { return .failure(.unknownField) }
        let value = value.trimmingCharacters(in: .whitespaces)
        var updated = policy
        guard field.write(value, &updated) else {
            return .failure(.badValue(label: field.label, allowed: field.allowed))
        }
        return .success(Applied(
            policy: updated,
            label: field.label,
            before: field.read(policy),
            after: field.read(updated)
        ))
    }

    /// A field's current value and options, or nil when the 항목 is not settable —
    /// which the console answers 「그런 항목이 없어요」 rather than inventing one.
    public static func describe(field label: String, in policy: RoomPolicy) -> FieldInfo? {
        guard let field = byLabel[label] else { return nil }
        return FieldInfo(label: field.label, current: field.read(policy), allowed: field.allowed)
    }

    // MARK: - one entry per field

    /// A settable field, whole: the label the console prints, what it accepts, how
    /// it reads now, and how a value folds in. Nothing else decides whether a field
    /// exists — a label with no entry is not settable, is not listed, and is not
    /// described.
    private struct Field: Sendable {
        let label: String
        let allowed: String
        let read: @Sendable (RoomPolicy) -> String
        let write: @Sendable (String, inout RoomPolicy) -> Bool
    }

    /// The table. Its order is the order `!방 <N>` reads the fields, and
    /// `settableFields` is this order.
    private static let fields: [Field] = [
        field("응답", "끔·감지·멘션·자동", \.responseMode, read: { $0.title }, parse: responseMode),
        field("전송", "초안·유휴·상시", \.deliveryMode, read: { $0.title }, parse: deliveryMode),
        field("끼어들기", "0~100", \.interjectionChance, read: { $0.summary }, parse: percent),
        field("최소간격", "없음·30초·5분·1시간", \.minimumInterval, read: PolicyWording.duration, parse: duration),
        field("판단주기", "즉시·10개·5분·5분~10분", \.judgementInterval, read: { $0.summary },
              parse: { judgement($0, allowMessages: true) }),
        // 「제한 없음」 here where `!방 <N>` prints 「항상」 for the same unlimited
        // window — see `AdminCommandResponder.activeHours`. Left as it reads
        // because changing it changes what `!세팅` answers, which this pass does not.
        field("활성시간", "항상·09:00-23:00", \.activeHours, read: { $0.summary }, parse: activeHours),
        toggle("답장", \.answersReplies),
        toggle("사진", \.readsPhotos),
        toggle("웹검색", \.webSearch),
        toggle("링크", \.readsLinks),
        toggle("대화기억", \.remembersConversation),
        toggle("사람기억", \.remembersPeople),
        // 켬은 isEnabled만 뒤집고 나머지 버닝 세부값(확률·길이·쿨다운)은 그대로 둔다.
        toggle("집중시간", \.burning.isEnabled),
        field("먼저말", "끔·초안·전송", \.conversationOpener, read: { $0.title }, parse: opener),
        // 먼저말 주기는 시간만 — 개(메시지 수)는 오프너가 쓰지 않아 조용히 안 걸리게 되므로 거부.
        field("먼저말주기", "3시간·2시간~6시간", \.conversationOpenerInterval, read: { $0.summary },
              parse: { judgement($0, allowMessages: false) }),
        field("먼저말시간", "항상·22:00-08:00", \.conversationOpenerHours, read: { $0.summary }, parse: activeHours),
        field("먼저말반복", "0~99", \.openerRepeatLimit, read: { "\($0)회" }, parse: repeatLimit),
        field("먼저말주제", "이어가기·새주제", \.openerRepeatTopic, read: { $0.title }, parse: repeatTopic),
        toggle("먼저말정지", \.openerCadencePausesOutsideHours),
    ]

    /// The same table by label, because `apply` and `describe` both start by asking
    /// whether the 항목 is one — and asking it of the array is how a lookup ends up
    /// written twice with different answers.
    ///
    /// Duplicates keep the first entry rather than trapping. The `switch` this table
    /// replaced was checked by the compiler — a label written twice was a 「case is
    /// already handled」 warning — and `uniqueKeysWithValues` would have turned that
    /// into a crash on the first `!세팅` after the mistake shipped. Keeping the first
    /// makes the duplicate merely dead, and `everyFieldLabelIsWrittenOnce` is what
    /// says so out loud at build time instead.
    private static let byLabel = Dictionary(fields.map { ($0.label, $0) }, uniquingKeysWith: { first, _ in first })

    /// A field holding one property: `read` is how that property reads on
    /// `!방 <N>`, `parse` is the only thing that decides whether a value is one the
    /// field takes, and a parse that refuses writes nothing at all.
    ///
    /// `& Sendable` on the key path because the table is a `static let` the whole
    /// app reads: `WritableKeyPath` is a class and not `Sendable` on its own, and
    /// the literals written below are.
    private static func field<Value>(
        _ label: String,
        _ allowed: String,
        _ path: WritableKeyPath<RoomPolicy, Value> & Sendable,
        read: @escaping @Sendable (Value) -> String,
        parse: @escaping @Sendable (String) -> Value?
    ) -> Field {
        Field(
            label: label,
            allowed: allowed,
            read: { read($0[keyPath: path]) },
            write: { value, policy in
                guard let parsed = parse(value) else { return false }
                policy[keyPath: path] = parsed
                return true
            }
        )
    }

    /// A 켬/끔 field. Eight of the nineteen are this and only this, and spelling
    /// 「켬·끔」 out per field is how one of them ends up advertising a word `bool`
    /// does not read.
    private static func toggle(_ label: String, _ path: WritableKeyPath<RoomPolicy, Bool> & Sendable) -> Field {
        field(label, "켬·끔", path, read: PolicyWording.onOff, parse: bool)
    }

    // MARK: - typed → text
    //
    // 켬/끔 and the 시간·분·초 reading are in `PolicyWording`, not here: `!방 <N>`
    // prints the same values from the app layer, and two copies of these words is
    // exactly how 집중시간 came to read 「꺼짐」 on one command and 「끔」 on the other.
    //
    // Everything else a field reads as is the value's own `title`/`summary` in the
    // domain, for the same reason.
}
