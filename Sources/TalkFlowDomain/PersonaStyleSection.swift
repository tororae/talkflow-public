import Foundation

/// The 말투 block shared by every prompt that speaks in the account's voice — the
/// reply, the opener, and the state announcement.
///
/// One renderer rather than three copies. The four lines describe the same voice
/// in all three paths, and the laughter rule below carries a measured argument
/// that must live in one place: kept in triplicate it drifts, and the opener and
/// the announcement had already drifted by omitting it entirely — an auto-sent
/// message in the account's voice leaking the same ㅋㅋ habit into a room whose
/// 이모지 setting says otherwise.
enum PersonaStyleSection {
    static func rendered(_ style: ResponseStyle) -> String {
        """
        응답 스타일:
        - 말투: \(style.tone)
        - 길이: \(style.length.title)
        - 이모지: \(style.emojiUse.title)
        - 적극성: \(style.assertiveness.title)
        \(laughterRule(style.emojiUse))
        """
    }

    /// The four settings above describe a voice. None of them describes a tic, and
    /// the reply came back with one anyway.
    ///
    /// Measured over 1,504 drafts: 81% contained ㅋㅋ. The people in those rooms
    /// use it in 7–13% of their messages, so this was not the room's register
    /// being matched — it was six to ten times it, in every room.
    ///
    /// Not the 말투 setting, which was the first suspect and is innocent: the room
    /// set to 「유머러스한 사극 말투」 wore the persona properly and still came back
    /// 100%, 「지수는 아직 오는 중이오 ㅋㅋㅋ」 — the persona kept, the tic kept with it.
    /// (원문 대신 같은 모양으로 옮겨 적었다. 카카오톡 원문은 저장소에 두지 않는다.) Not a feedback loop off 「내가 방금 한
    /// 말」 either — that would start low and climb, and the very first hundred
    /// drafts were already at 77%.
    ///
    /// What was true is that no line of this prompt had ever mentioned laughter, so
    /// 「자연스러운」 was answered with whatever the model takes casual KakaoTalk to
    /// be. Removing that word instead was tried and is the wrong trade: it only
    /// reached 4 in 6 and stiffened the replies into 습니다체, which is the one
    /// thing a draft written as the user must not do.
    ///
    /// Both markers are named, and named together, because forbidding one alone
    /// moves the habit rather than ending it: told only about ㅋㅋ, six drafts came
    /// back with none of it and four with 😅 in the same place. The habit is not a
    /// spelling, it is the reflex to close every line with something, so the
    /// sentence has to reach the reflex.
    ///
    /// The 이모지 setting picks which sentence, rather than the sentence deferring
    /// to the setting. Pointing at it — 「위 이모지 설정과 같은 빈도로」 — was tried
    /// first and is too polite to land: it came back 2 in 6 with laughter and 3 in
    /// 6 with an emoji, because 「가끔」 reads as permission where 「대부분의 답장에는
    /// 넣지 마세요」 reads as a bound. Saying the bound outright is what measured 1
    /// in 6.
    ///
    /// So each level says its own number, and 자주 keeps what it asked for. A flat
    /// prohibition would have been the one line of this section that overrules the
    /// user, which is not a thing a style section may do.
    static func laughterRule(_ emojiUse: ResponseStyle.EmojiUse) -> String {
        switch emojiUse {
        case .none:
            "- ㅋㅋ·ㅎㅎ 같은 웃음 표현도 이모지와 함께 쓰지 마세요."
        case .sparing:
            """
            - ㅋㅋ·ㅎㅎ 같은 웃음 표현과 이모지는 방 사람들이 쓰는 만큼만 쓰세요. \
            대부분의 답장에는 둘 다 넣지 말고, 어느 하나를 다른 하나로 대신하지도 마세요.
            """
        case .frequent:
            "- ㅋㅋ·ㅎㅎ 같은 웃음 표현도 이모지만큼 자주 써도 됩니다."
        }
    }
}
