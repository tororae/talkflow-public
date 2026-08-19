import Foundation

/// One room's name, in a form two sources can be compared on.
///
/// A group room nobody named is titled with its members, and the sources that
/// report it do not agree on the order. Measured 2026-08-10 on the same room at
/// the same moment. The names below are invented; the disagreement is not:
///
/// ```
/// 창 제목   김하늘, 박서준, 이도윤, 정민재, 최은우, 한지호, 서예린, 한결
/// 아카이브  이도윤, 최은우, 한결, 한지호, 정민재, 박서준, 서예린, 김하늘
/// ```
///
/// Compared as strings those are two different rooms, which is how a room with
/// its window plainly open was marked 닫힘 on screen.
///
/// Names are all there is to compare on — KakaoTalk's window list and its chat
/// list both report names and no ids — so the comparison has to be the part that
/// gives.
public enum RoomNameKey {
    /// A member list is matched as a set; every other name is matched as itself.
    ///
    /// The split is on a comma, which is what KakaoTalk joins members with. A
    /// room deliberately named with a comma in it is folded the same way, and
    /// comes out equal to itself — the ordering is applied to both sides, so a
    /// name that is not a member list is unharmed by being treated as one.
    public static func of(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard parts.count > 1 else { return trimmed }
        return parts.sorted().joined(separator: ", ")
    }

    public static func set(_ names: some Sequence<String>) -> Set<String> {
        Set(names.map(of))
    }
}
