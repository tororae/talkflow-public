import Foundation
import TalkFlowDomain

/// Turns the result of an admin command into the plain text TalkFlow types back
/// into the console room.
///
/// Pure, like `AdminCommandParser`: every method is a function of data the use
/// case already fetched, touching no port. The use case reads the rooms, the
/// policies and the people; this only decides how they read on screen — which is
/// why it can be exercised through the use case's one send without a formatter
/// test of its own.
///
/// Everything here is for KakaoTalk's proportional font, so there are no aligned
/// columns or monospace tables: a `·` separates fields on a line and a number
/// leads every row. And every room and person is printed with its name beside
/// its number, so a listing that shifted under the operator is caught by eye
/// rather than acted on.
enum AdminCommandResponder {
    /// One room as a numbered row: the number is its position in the account's
    /// whole sorted room list, so it means the same room on the next command.
    struct NumberedRoom {
        let number: Int
        let room: ChatRoom
        let policy: RoomPolicy
    }

    /// One person the room has collected 사람 기억 on, numbered by name.
    struct NumberedMember {
        let number: Int
        let displayName: String
        let replyCount: Int
        /// The first line of their note, shortened — enough to tell people apart in
        /// the list without printing the whole note on every row.
        let noteSummary: String
    }

    /// One recent thing the bot did, as `!활동` lists it: its number (global, newest
    /// = 1), which room, what kind of action, and a short line of what it said.
    struct ActivityLine {
        let number: Int
        let roomName: String
        let kind: String
        let snippet: String
    }

    /// One recent action in full, for `!활동 <N> <M>`.
    struct ActivityDetail {
        let number: Int
        let roomName: String
        let kind: String
        let time: String
        let reply: String
        let answered: String
    }

    /// How many rooms a bare `!방` prints before it stops and points at search.
    /// One account here carries 234 rooms; a listing of all of them is not a
    /// listing anybody reads, and the number nobody wants is buried in it.
    static let roomsDisplayCap = 40

    static let unknownCommand = "모르는 명령입니다. !? 로 목록"
    static let unknownActivity = "그런 번호의 활동이 없어요. !활동 <N> 으로 확인"
    static let unknownRoom = "그런 번호의 방이 없어요. !방 으로 확인"
    static let unknownMember = "그런 번호의 사람이 없어요. !유저 <N> 으로 확인"

    // MARK: - !?

    static func help() -> String {
        """
        관리자 명령

        !방 — 방 목록 (번호)
        !방 <검색> — 이름으로 찾기
        !방 <N> — N번 방 설정 보기
        !유저 <N> — N번 방 사람
        !유저 <N> <M> — 그 방 M번 사람
        !세팅 <N> <항목> <값> — 값 바꾸기
        !켬 <N> · !끔 <N> — 방 응답 켜기·끄기
        !활동 [<N>] — 최근 활동
        !프리셋 <N> <이름> — 설정 묶음
        !? — 이 목록
        """
    }

    // MARK: - !방 · !방 <검색>

    /// `total` is the whole account and `matched` how many the filter admitted
    /// before the cap; `shown` is what survived both. The three differ so the
    /// header can count the matches and the "…N개 더" line the rows left out.
    static func rooms(shown: [NumberedRoom], matched: Int, total: Int, filter: String?) -> String {
        var blocks: [String] = [roomsHeader(matched: matched, total: total, filter: filter)]
        blocks.append(contentsOf: shown.map(roomRow))
        // Only when rows were dropped, and only how many. A bare `!방` points at
        // search; a search that still overflows points back at a narrower one,
        // because there is nothing else it can offer.
        let hidden = matched - shown.count
        if hidden > 0 { blocks.append("…\(hidden)개 더 · !방 <검색>") }
        // Header, every room row and the overflow note each stand apart: a row can
        // wrap in KakaoTalk's proportional font, and single-spaced they run together.
        return blocks.joined(separator: "\n\n")
    }

    private static func roomsHeader(matched: Int, total: Int, filter: String?) -> String {
        guard let filter, !filter.isEmpty else { return "방 \(total)개" }
        return "\"\(filter)\" 포함 \(matched)개 · 전체 \(total)개"
    }

    private static func roomRow(_ entry: NumberedRoom) -> String {
        "\(entry.number). \(entry.room.displayName) · \(responseMode(entry.policy.responseMode)) · \(delivery(entry.policy.deliveryMode))"
    }

    // MARK: - !방 <N>

    /// The settable settings with their current values — the vocabulary a future
    /// `!세팅` will write to. Only scalars, enums and toggles; the two free-text
    /// fields are named once at the bottom as app-only rather than dumped here.
    static func room(_ entry: NumberedRoom, windowOpen: Bool?) -> String {
        let policy = entry.policy
        // Title / settings / app-only note as three blocks. The `·` settings lines
        // stay tight inside their block — they are one card, not separate entries —
        // so only the boundaries around that card get a blank line.
        var settings: [String] = []
        settings.append("· 응답: \(responseMode(policy.responseMode)) (끔·감지·멘션·자동)")
        settings.append("· 전송: \(delivery(policy.deliveryMode)) (초안·유휴자동·상시)")
        settings.append(pacingLine(entry.room, policy))
        settings.append("· 활성시간: \(activeHours(policy.activeHours))")
        settings.append("· 사진: \(PolicyWording.onOff(policy.readsPhotos)) · 웹검색: \(PolicyWording.onOff(policy.webSearch)) · 링크: \(PolicyWording.onOff(policy.readsLinks))")
        settings.append("· 대화기억: \(PolicyWording.onOff(policy.remembersConversation)) · 사람기억: \(PolicyWording.onOff(policy.remembersPeople))")
        settings.append("· 먼저말: \(policy.conversationOpener.title) · 집중시간: \(PolicyWording.onOff(policy.burning.isEnabled))")
        return [
            roomTitle(entry, windowOpen: windowOpen),
            settings.joined(separator: "\n"),
            "말투·답변조건은 앱에서만.\n항목 자세히·바꾸기: !세팅 \(entry.number) <항목> <값>",
        ].joined(separator: "\n\n")
    }

    private static func roomTitle(_ entry: NumberedRoom, windowOpen: Bool?) -> String {
        let kind = entry.room.kind == .direct ? "개인" : "단체"
        var title = "\(entry.number). \(entry.room.displayName) (\(kind))"
        // Live window state, not a setting — printed only when it is actually
        // known. A window on another Space reads as closed and an unread list
        // reads as nothing, so nil simply leaves the clause off.
        if let windowOpen {
            title += windowOpen ? " · 대화창 열림" : " · 대화창 닫힘"
        }
        return title
    }

    /// 끼어들기 is a group-automatic dial and means nothing in a direct room, so
    /// a direct room's line drops it rather than printing a percent that never
    /// applies. The other two pacing values are shown either way.
    private static func pacingLine(_ room: ChatRoom, _ policy: RoomPolicy) -> String {
        // 판단주기 reads back through the domain's own `summary`, so the console and
        // the room screen call the same range the same thing.
        let tail = "최소간격: \(PolicyWording.duration(policy.minimumInterval)) · 판단주기: \(policy.judgementInterval.summary)"
        guard room.kind == .group else { return "· \(tail)" }
        return "· 끼어들기: \(policy.interjectionChance.percent)% · \(tail)"
    }

    // MARK: - !유저 <N>

    /// The people the room has collected 사람 기억 on — not who spoke recently, but
    /// who TalkFlow has actually written a note about here.
    static func people(roomNumber: Int, roomName: String, remembersPeople: Bool, members: [NumberedMember]) -> String {
        let header = "\(roomNumber). \(roomName) · 수집한 사람 \(members.count)명"
        let body: [String]
        if members.isEmpty {
            body = [remembersPeople
                ? "아직 수집한 사람 정보가 없어요. 대화가 쌓이면 만들어져요."
                : "사람 기억이 꺼져 있어 수집한 정보가 없어요."]
        } else {
            body = members.map(peopleRow)
        }
        // A blank line between every entry. A person's row runs name · 답장 · 메모요약
        // long enough to wrap in KakaoTalk's proportional font, and single-spaced the
        // wrapped rows run into each other — so each entry, and the header, stands apart.
        return ([header] + body).joined(separator: "\n\n")
    }

    private static func peopleRow(_ member: NumberedMember) -> String {
        var row = "\(member.number). \(member.displayName) · 답장 \(member.replyCount)회"
        if !member.noteSummary.isEmpty { row += " · \(member.noteSummary)" }
        return row
    }

    // MARK: - !유저 <N> <M>

    static func person(roomName: String, displayName: String, replyCount: Int, note: String, links: [PersonLink]) -> String {
        // 이름·방 heading, then the 답장/메모 facts, then the links — each its own
        // block. Facts stay tight together, and the link list rides with its 링크:
        // header, so only the section boundaries carry a blank line.
        var blocks = ["\(displayName) · \(roomName)"]
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        blocks.append("답장 \(replyCount)회\n메모: \(trimmed.isEmpty ? "없음" : trimmed)")
        if !links.isEmpty {
            blocks.append((["링크:"] + links.map { "· \($0.label): \($0.url)" }).joined(separator: "\n"))
        }
        return blocks.joined(separator: "\n\n")
    }

    // MARK: - !세팅 <N> <항목> <값>

    /// Shown when a save fails at the store, not at the value — the operator typed
    /// something valid and it did not land, so retyping is the honest next move.
    static let settingSaveFailed = "설정을 저장하지 못했어요. 다시 시도해 주세요."

    /// `!세팅` with too little to act on: the shape, an example, and — because the
    /// command reveals itself a step at a time — how each next step narrows it.
    ///
    /// The first line leads with 「값 바꾸기」, not the `!세팅` form, on purpose: a
    /// reply that begins with the command prefix is read back as a new command and
    /// answered forever. Every reply here is written to never lead with `!`.
    static func settingUsage() -> String {
        """
        값 바꾸기 — !세팅 <방번호> <항목> <값>
        예: !세팅 2 응답 자동

        !세팅 <방번호> — 그 방에서 바꿀 항목과 지금 값
        !세팅 <방번호> <항목> — 그 항목에 넣을 수 있는 값
        방 번호는 !방 에서.
        """
    }

    /// The change, echoed as the room heading then 「항목: 이전 → 이후」, so a value
    /// that changed nothing shows the same word on both sides rather than a bare ✓.
    static func settingApplied(roomNumber: Int, roomName: String, label: String, before: String, after: String) -> String {
        """
        \(roomNumber). \(roomName)

        \(label): \(before) → \(after)
        """
    }

    /// Why a change did not happen — an item that is not settable, or a value the
    /// item cannot take, echoing back the short list the operator can retype.
    static func settingFailed(_ failure: PolicyEditor.Failure) -> String {
        switch failure {
        case .unknownField:
            return "그런 항목이 없어요. !세팅 <방번호> 로 바꿀 항목을 보세요."
        case let .badValue(label, allowed):
            return "\(label): \(allowed) 중 하나로 적어주세요."
        }
    }

    /// `!세팅 <N>`: the fields this room can set, each with its value now and the
    /// values it takes, so the operator can pick one. The `·` list stays tight like
    /// `!방 <N>`'s card; only the heading and the example are split off.
    static func settingFields(roomNumber: Int, roomName: String, infos: [PolicyEditor.FieldInfo]) -> String {
        let rows = infos.map { "· \($0.label): \($0.current) (\($0.allowed))" }.joined(separator: "\n")
        return """
        \(roomNumber). \(roomName) · 바꿀 항목

        \(rows)

        예: !세팅 \(roomNumber) 응답 멘션
        """
    }

    /// `!세팅 <N> <항목>`: what that one field holds now and the values it takes —
    /// the step the operator lands on after naming a field but before a value.
    static func settingField(roomNumber: Int, roomName: String, info: PolicyEditor.FieldInfo) -> String {
        """
        \(roomNumber). \(roomName) · \(info.label)

        지금: \(info.current)
        값: \(info.allowed)
        바꾸기: !세팅 \(roomNumber) \(info.label) <값>
        """
    }

    // MARK: - !활동

    /// Recent bot activity. All rooms print the room on each line; a room-scoped
    /// `!활동 <N>` names the room once in the header and drops it from the rows.
    static func activity(roomNumber: Int?, roomName: String?, page: Int, lines: [ActivityLine], hasMore: Bool) -> String {
        let scope = (roomNumber != nil && roomName != nil) ? "\(roomNumber!). \(roomName!) · 최근 활동" : "최근 활동"
        guard let first = lines.first, let last = lines.last else {
            let empty = page > 1 ? "그 쪽에는 활동이 없어요." : "아직 볼 만한 활동이 없어요."
            return [scope, empty].joined(separator: "\n\n")
        }
        let scoped = roomNumber != nil
        let header = "\(scope) · \(first.number)~\(last.number)"
        let body = lines.map { line -> String in
            var parts = scoped ? [line.kind] : [line.roomName, line.kind]
            if !line.snippet.isEmpty { parts.append(line.snippet) }
            return "\(line.number). " + parts.joined(separator: " · ")
        }
        // Room-scoped, each row opens with `!활동 N <번호>`; both views page on with 쪽.
        var footer: [String] = []
        if scoped { footer.append("자세히: !활동 \(roomNumber!) <번호>") }
        if hasMore { footer.append("다음: " + (scoped ? "!활동 \(roomNumber!) \(page + 1)쪽" : "!활동 \(page + 1)쪽")) }
        var blocks = [header] + body
        if !footer.isEmpty { blocks.append(footer.joined(separator: " · ")) }
        return blocks.joined(separator: "\n\n")
    }

    /// One action in full — `!활동 <N> <M>`. The heading numbers it as the list did;
    /// then the kind and time, what it said, and what it answered.
    static func activityDetail(roomNumber: Int, detail: ActivityDetail) -> String {
        var facts = [detail.time.isEmpty ? detail.kind : "\(detail.kind) · \(detail.time)"]
        if !detail.reply.isEmpty { facts.append("한 말: \(detail.reply)") }
        if !detail.answered.isEmpty { facts.append("답한 말: \(detail.answered)") }
        return [
            "\(roomNumber). \(detail.roomName) · \(detail.number)번째 활동",
            facts.joined(separator: "\n"),
        ].joined(separator: "\n\n")
    }

    // MARK: - !프리셋

    static var presetUnknown: String {
        "그런 프리셋이 없어요. " + RoomPreset.all.map(\.name).joined(separator: "·")
    }

    /// The presets on offer, each with what it sets. `!프리셋 <N>` names the room so
    /// the example points at it; a bare `!프리셋` just lists them.
    static func presetList(roomNumber: Int?, roomName: String?) -> String {
        let header: String
        if let roomNumber, let roomName {
            header = "\(roomNumber). \(roomName) · 프리셋"
        } else {
            header = "프리셋"
        }
        let menu = RoomPreset.all.map { "\($0.name) — \($0.summary)" }.joined(separator: "\n")
        let example = "예: !프리셋 \(roomNumber ?? 3) 풀"
        return [header, menu, example].joined(separator: "\n\n")
    }

    /// The bundle applied, echoed as the room heading then what the preset sets, so
    /// the operator sees the effect without reading every field back.
    static func presetApplied(roomNumber: Int, roomName: String, name: String, summary: String) -> String {
        """
        \(roomNumber). \(roomName) · 프리셋 '\(name)'

        \(summary)
        """
    }

    // MARK: - value → text
    //
    // Only the readings this console says differently live here. 켬/끔 and the
    // 시간·분·초 span are `PolicyWording`'s, shared with `PolicyEditor`, because
    // `!방 <N>` and `!세팅 <N> <항목>` print the same stored values and a second copy
    // is how 집중시간 came to read 「꺼짐」 on one and 「끔」 on the other.

    /// Shorter than `ResponseMode.title` on purpose: the app screen has a whole
    /// row for 「멘션에만 응답」, this has one `·`-separated segment of a room row that
    /// also carries the name and the delivery mode, and a wrapped row in
    /// KakaoTalk's proportional font is a row nobody scans. `!세팅` still answers the
    /// full `title` — it prints one field on its own line, where the long form fits.
    private static func responseMode(_ mode: ResponseMode) -> String {
        switch mode {
        case .off: "끔"
        case .detectOnly: "감지전용"
        case .mentionOnly: "멘션"
        case .automatic: "자동응답"
        }
    }

    /// Shortened for the same reason, against `DeliveryMode.title`'s
    /// 「유휴 상태 자동 전송」.
    private static func delivery(_ mode: DeliveryMode) -> String {
        switch mode {
        case .draftOnly: "초안만"
        case .autoSendWhenIdle: "유휴자동"
        case .always: "상시전송"
        }
    }

    /// 「항상」 where `ReplyActiveHours.summary` says 「제한 없음」 — measured, not
    /// assumed: `summary` returns 「제한 없음」 for an unlimited window. 항상 is the
    /// right word of the two, because `PolicyEditor.allowed` advertises 「항상·09:00-23:00」
    /// as what 활성시간 takes, so this echoes back the word it asked for. `!세팅` still
    /// prints the raw `summary`; that side is left alone here rather than changed
    /// blind, and is the remaining half of this inconsistency.
    private static func activeHours(_ hours: ReplyActiveHours) -> String {
        hours.isLimited ? hours.summary : "항상"
    }
}
