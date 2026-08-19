import Foundation

/// A command an operator types into a room TalkFlow has been told to treat as an
/// admin console.
///
/// The whole app is built on message text being untrusted input that is never
/// executed as instructions (see `ResponsePolicyEngine`). This is the one
/// deliberate carve-out, and it is fenced by two things that live *outside* the
/// text: the room must be designated an admin room, and — for now — everyone in
/// that room is trusted. The parser grants no authority by itself.
///
/// Rooms and people are addressed by number, not name. `!방` prints the rooms
/// numbered; `!방 3` opens the third. The numbering is the room's position in one
/// fixed ordering of every room, so the number a listing showed still means the
/// same room on the next command without anything being stored between them — and
/// a reply always prints the room's name beside the number so a stale index is
/// caught by eye.
public enum AdminCommand: Equatable, Sendable {
    /// The list of commands and what each does. `!?` · `!도움`.
    case help
    /// Every room, numbered — or only those whose name contains the filter, keeping
    /// each room's number so a search is still a way to find one. `!방` · `!방 <검색>`.
    case rooms(filter: String?)
    /// One room by its number: a summary and every setting the operator can change,
    /// with current values. `!방 <N>`.
    case room(number: Int)
    /// The people in a room by its number; or, with no number, the people in the
    /// console room itself. `!유저` · `!유저 <N>`.
    case users(roomNumber: Int?)
    /// One person in one room, both by number. `!유저 <N> <M>`.
    case member(roomNumber: Int, memberNumber: Int)
    /// Sets one whitelisted field of a room's policy, the room addressed by number
    /// and the field named the way `!방 <N>` prints it. `!세팅 <N> <항목> <값>`. The
    /// field and value are carried as typed; the domain's `PolicyEditor` is what
    /// turns them into a change or a reason it cannot.
    case setting(roomNumber: Int, field: String, value: String)
    /// `!세팅 <N>` — a room but no field yet: the fields it can set and their
    /// current values, so the operator can pick one.
    case settingFields(roomNumber: Int)
    /// `!세팅 <N> <항목>` — a field but no value yet: what that field holds now and
    /// the values it takes.
    case settingField(roomNumber: Int, field: String)
    /// `!세팅` typed without even a room number — a request for how the command
    /// reads rather than a change to make.
    case settingUsage
    /// Turns a room's 응답 on or off in one word — `!켬 3` · `!끔 3`. On uses the mode
    /// that suits the room's type (group → 멘션, direct → 자동), the same one the app's
    /// list switch uses; off is 끔.
    case toggleRoom(roomNumber: Int, on: Bool)
    /// A page of recent activity, numbered — `!활동`, `!활동 <N>`, `!활동 <N> <K>쪽`
    /// (or a bare `!활동 <K>쪽` for every room). Newest first, ten a page, 관리자 명령
    /// rows left out. The numbers are global (1 = newest), so a page-2 row reads 11.
    case activity(roomNumber: Int?, page: Int)
    /// One recent action in full — `!활동 <N> <M>`, the Mth newest in room N, the
    /// same drill-down `!유저 <N> <M>` gives a person.
    case activityDetail(roomNumber: Int, itemNumber: Int)
    /// Applies a named bundle of settings to a room at once — `!프리셋 3 풀`. The name
    /// is resolved by `RoomPreset`, which is what turns it into a change or refuses.
    case presetApply(roomNumber: Int, name: String)
    /// The presets on offer — `!프리셋`, or `!프리셋 <N>` to name the room they would
    /// land on. A request to see the menu rather than pick from it.
    case presetList(roomNumber: Int?)
}

/// Turns a typed line into an `AdminCommand`, or nothing.
///
/// Pure, like `CallSigns`: it reads text and returns a value, touching nothing.
/// A line that does not start with the prefix is never a command, and neither is
/// one whose verb it does not know — an unknown line parses to nothing rather
/// than to something close.
public enum AdminCommandParser {
    /// What a command line has to start with. A single `!` is enough because the
    /// real fence is elsewhere — the room is a designated console and only exact
    /// verbs match, so an ordinary line that happens to open with `!` parses to
    /// nothing rather than doing something.
    ///
    /// `!` rather than `/`: every reply this console sends is plain text, and a
    /// reply that itself began with the prefix — the 사용법 line documents the
    /// command — was read back as a new command and answered forever. Replies are
    /// now written to never lead with `!`, and the handler ignores the account's own
    /// messages besides, so the echo cannot feed itself.
    public static let prefix = "!"

    public static func parse(_ text: String) -> AdminCommand? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(prefix) else { return nil }
        let tokens = trimmed.dropFirst(prefix.count)
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        guard let verb = tokens.first?.lowercased() else { return nil }
        let args = Array(tokens.dropFirst())

        switch verb {
        case "?", "help", "도움", "도움말", "명령", "명령어":
            return .help
        case "방", "방목록", "rooms", "room":
            return rooms(args)
        case "유저", "유저들", "멤버", "사람", "users", "members":
            return people(args)
        case "세팅", "설정", "set":
            return setting(args)
        case "켬", "켜기", "on":
            return toggle(args, on: true)
        case "끔", "끄기", "off":
            return toggle(args, on: false)
        case "활동", "기록", "로그":
            return activity(args)
        case "프리셋", "preset":
            return preset(args)
        default:
            return nil
        }
    }

    /// `!방` lists; `!방 3` opens room 3; `!방 <말>` searches by name. A number is a
    /// room number, so anything that is not one is a search — and the search keeps
    /// every word, so a name with spaces still finds its room.
    ///
    /// A settable field after the number drills into it — `!방 3 전송` reads 전송 up
    /// close, the same view `!세팅 3 전송` gives — because reaching for the field you
    /// just saw on the card is the obvious next thing to type. A trailing word that
    /// names no field is still ignored, so `!방 3 세팅` just opens the room.
    private static func rooms(_ args: [String]) -> AdminCommand {
        guard let first = args.first else { return .rooms(filter: nil) }
        if let number = Int(first) {
            if let field = args.dropFirst().first, PolicyEditor.settableFields.contains(field) {
                return .settingField(roomNumber: number, field: field)
            }
            return .room(number: number)
        }
        return .rooms(filter: args.joined(separator: " "))
    }

    /// `!유저` is the console room's own people; `!유저 3` is room 3's; `!유저 3 2` is
    /// one person in room 3. Both positions are numbers — a room's number is found
    /// with `!방` first — so a non-number here is not a command.
    private static func people(_ args: [String]) -> AdminCommand? {
        guard let first = args.first else { return .users(roomNumber: nil) }
        guard let roomNumber = Int(first) else { return nil }
        guard let second = args.dropFirst().first else {
            return .users(roomNumber: roomNumber)
        }
        guard let memberNumber = Int(second) else { return nil }
        return .member(roomNumber: roomNumber, memberNumber: memberNumber)
    }

    /// `!세팅` reveals itself a step at a time. A bare verb, or a first token that
    /// is not a room number, prints the usage; a room number the fields it can set;
    /// a field the values it takes; and only a full `<N> <항목> <값>` writes. So a
    /// half-typed `!세팅 3 응답` answers 「what does 응답 take」 rather than falling
    /// through to the usage line — the operator learns the next step from the reply.
    /// The value keeps every remaining word, so `활성시간 09:00 - 23:00` survives
    /// being typed with spaces.
    private static func setting(_ args: [String]) -> AdminCommand {
        guard let first = args.first, let roomNumber = Int(first) else { return .settingUsage }
        // A room but nothing after it: the fields it can set.
        guard args.count >= 2 else { return .settingFields(roomNumber: roomNumber) }
        let field = args[1]
        // A field but no value: the values that field takes.
        guard args.count >= 3 else { return .settingField(roomNumber: roomNumber, field: field) }
        return .setting(
            roomNumber: roomNumber,
            field: field,
            value: args[2...].joined(separator: " ")
        )
    }

    /// `!켬 3` · `!끔 3` — a room number is required; without one there is nothing to
    /// turn on or off, so it is not a command.
    private static func toggle(_ args: [String], on: Bool) -> AdminCommand? {
        guard let first = args.first, let number = Int(first) else { return nil }
        return .toggleRoom(roomNumber: number, on: on)
    }

    /// `!활동` is every room; `!활동 3` is room 3. A non-number is read as "every
    /// room" rather than refused, so a stray word does not turn a read into an error.
    /// `!활동` every room; `!활동 3` room 3; `!활동 3 5` the 5th newest there (detail);
    /// `!활동 3 2쪽` room 3 page 2; `!활동 2쪽` every room page 2. A bare number is the
    /// room, a `<K>쪽`/`<K>페` token is a page, and a bare number *after* a room is an
    /// item to open — the same shapes `!유저` and the paged screens already use.
    private static func activity(_ args: [String]) -> AdminCommand {
        guard let first = args.first else { return .activity(roomNumber: nil, page: 1) }
        guard let room = Int(first) else {
            // No room number: the only thing that can follow is a page for every room.
            return .activity(roomNumber: nil, page: page(first) ?? 1)
        }
        guard let second = args.dropFirst().first else { return .activity(roomNumber: room, page: 1) }
        if let page = page(second) { return .activity(roomNumber: room, page: page) }
        if let item = Int(second) { return .activityDetail(roomNumber: room, itemNumber: item) }
        return .activity(roomNumber: room, page: 1)
    }

    /// A page token: `2쪽`·`2페`·`2페이지` → 2. Nil when it is not one.
    private static func page(_ s: String) -> Int? {
        for suffix in ["페이지", "쪽", "페"] {
            if s.hasSuffix(suffix), let n = Int(s.dropLast(suffix.count)), n >= 1 { return n }
        }
        return nil
    }

    /// `!프리셋 3 풀` applies; `!프리셋 3` and a bare `!프리셋` show the menu — a preset
    /// changes several settings at once, so seeing the list before picking is the
    /// safer default.
    private static func preset(_ args: [String]) -> AdminCommand {
        guard let first = args.first, let number = Int(first) else { return .presetList(roomNumber: nil) }
        guard let name = args.dropFirst().first else { return .presetList(roomNumber: number) }
        return .presetApply(roomNumber: number, name: name)
    }
}
