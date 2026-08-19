import Foundation
import TalkFlowDomain

/// 사람 기억 — the first thing in this app that writes a description of a named
/// person and keeps it.
///
/// 대화 기억 already had to say, in 무엇을 하나 rather than 하지 않는 것, that a
/// paragraph about the user's friends goes to a model on every reply. This is that
/// rule at its sharpest: a room summary describes a room, and these describe
/// people, one note per person per room, filed under a name the user would
/// recognise. So the first line of the first card is the whole of it — TalkFlow
/// writes about real people and sends what it wrote away — and everything after it
/// on that card is a qualification of a sentence the user has already read.
///
/// Two of these cards used to promise the opposite of what the code now does:
/// 「메모는 사람마다 하나」 and 「방을 옮겨도 같은 글」. A card that states last
/// version's bargain is worse than no card, because the user acts on it — so both
/// were rewritten with the schema rather than after it.
///
/// The 비용 section reads backwards from every other card in this app. Nothing
/// else here costs nothing and still widens what leaves the Mac: 사람 기억 spends
/// no call of its own, riding the 채팅방 요약 refresh, so a user counting calls
/// against messages would conclude it was free and stop reading. The section says
/// both halves in the order they matter — no new calls, and a person's note out of
/// this Mac every time they speak.
///
/// The 하지 않는 것 line about 건강·종교·정치 성향·성적 지향·재정 상태 carries a
/// clause the 대화 기억 version does not: not even when the person said it
/// outright. A conversation is read once and falls out of the window; the note is
/// the artifact that lasts. Something mentioned once in a room should not become a
/// standing fact about somebody that ships with every reply from then on, and the
/// difference between those two is exactly what this setting changes.
extension SettingHelp {
    /// The switch. It leads with what gets written and where it goes, then spends
    /// the rest of the card narrowing — only people this account has actually
    /// answered, only the one who just spoke, never an open chat. Every one of
    /// those is a user's reasonable first guess about how wide this is, and every
    /// guess is wider than the truth, so each is stated rather than left safe by
    /// accident.
    ///
    /// The two limits are read off `PersonNote`. The reply threshold is typed out,
    /// against the rule the rest of this catalog follows, because the constant
    /// behind it — `ConversationSummaryRefresher.replyThreshold` — is internal to
    /// TalkFlowApplication and cannot be seen from here. It should be read off the
    /// moment that changes: a card that repeats a number by hand goes on saying
    /// the old one long after the code has moved.
    static let remembersPeople = SettingHelp(
        title: "사람 기억",
        summary: "이 방 사람들에 대한 메모를 적어 두고, 말할 때 함께 보냅니다.",
        topics: [
            .does(
                "실제 사람 한 명 한 명에 대한 메모를 이 Mac에 글로 적어 두고, 그 사람이 이 방에서 말할 때 답장 요청에 실어 AI 제공자로 보냅니다.",
                .init("내용", "다음에 만나도 여전히 맞을 것만 적습니다. 하는 일, 만든 것, 서로 어떻게 부르는지 정도입니다. 그날의 상황은 적지 않습니다."),
                .init("방마다 하나", "사람이 아니라 방이 기준입니다. 같은 사람이 여러 방에 있으면 방마다 따로 메모가 생기고, 서로 섞이지 않습니다."),
                .init("사용", "방금 말한 그 사람의 메모 하나만 붙습니다."),
                .init("길이", "\(PersonNote.characterLimit)자까지입니다. 매번 실려 나가는 글이라 상한을 둡니다."),
                .init("링크", "주소는 문장에 섞지 않고 따로 담습니다. 답장에는 최근 \(PersonNote.linksPerReply)개가 실립니다."),
                .init("확인", "사람 탭에서 무엇이 적혔는지 그대로 읽고, 고치고, 지울 수 있습니다.")
            ),
            .applies(
                "방마다 따로 켜고 끕니다. 기본값은 끔입니다.",
                .init("대상", "이 방에서 내가 실제로 답한 적이 있는 사람만입니다. 답이 3번 나간 사람부터 메모를 만듭니다."),
                .init("갱신", "채팅방 요약을 다시 만들 때 함께 씁니다. 새 메시지 \(ConversationSummaryRefresh.messageThreshold)개가 쌓이거나 마지막 갱신에서 하루가 지나면 돌아갑니다."),
                .init("정리", "갱신할 때 이미 끝난 이야기는 빼냅니다. 남을 것이 없어지면 그 메모는 사라집니다."),
                "오픈채팅방을 알아서 걸러 주지는 않습니다. 방마다 켜는 설정이고 기본이 꺼짐이라, 켜지 않으면 그 방에서는 아무 일도 일어나지 않습니다.",
                "응답 모드가 \"끔\"이나 \"감지 전용\"이면 만들지 않습니다.",
                "개요 화면의 \"자동 응답\"이 꺼져 있으면 갱신하지 않습니다."
            ),
            .costs(
                "AI 호출이 늘지 않습니다. 메모는 채팅방 요약을 갱신하는 그 호출이 함께 씁니다. 이 설정만을 위해 나가는 호출은 없습니다.",
                "그 대신 메모가 있는 사람이 이 방에서 말할 때마다 그 사람에 대해 적어 둔 글이 이 Mac 밖으로, AI 제공자로 나갑니다.",
                "메모가 붙은 답장 요청은 그 길이만큼 길어집니다.",
                "메모는 이 Mac에 글로 저장됩니다. 실제 사람들에 대한 기록이므로 사람 탭에서 그대로 읽고 지울 수 있습니다."
            ),
            .doesNot(
                "건강, 종교, 정치 성향, 성적 지향, 재정 상태는 적지 않습니다. 추측하지 않는 것은 물론이고, 본인이 그대로 말했더라도 적지 않습니다.",
                "대화는 흘러가지만 메모는 남고, 그 뒤로 계속 실려 나갑니다.",
                "방에 있는 사람 전부의 메모를 붙이지 않습니다. 방금 말한 한 사람의 메모만 나갑니다.",
                "다른 방에서 알게 된 것을 이 방에 가져오지 않습니다. 이 방의 메모는 이 방 대화만으로 씁니다.",
                "그때뿐인 일은 적지 않습니다. 「퇴근 준비 중」처럼 다음 주에는 틀릴 한 줄은 남기지 않습니다.",
                "이름으로 사람을 가리지 않습니다. 카카오톡의 발신자 아이디로만 구분하므로, 같은 이름을 쓰는 두 사람이 한 메모를 나눠 갖지 않습니다.",
                "대화 기억을 켠다고 함께 켜지지 않습니다. 방이 어떤 방인지 적는 것과 사람이 어떤 사람인지 적는 것은 다른 허락입니다.",
                "이 방에서 끈다고 이미 적힌 메모가 지워지지 않습니다. 끄면 더 쓰지 않을 뿐이고, 지우는 것은 사람 탭에서 합니다."
            )
        ]
    )

    /// The note as the 사람 tab shows it, which is where the user finds out what
    /// was written about somebody they know.
    ///
    /// The card's job is to make the note editable in the user's mind before it is
    /// editable under their hands. A user who assumes the model will just write
    /// over them will not bother fixing a wrong sentence about their friend, and
    /// the wrong sentence keeps going out — so the card has to say both that
    /// correcting is possible and what 고정 does, because a correction left
    /// unpinned genuinely will be rewritten. The length is set beside 채팅방 요약's
    /// rather than stated alone, because 300 only means something next to the 600
    /// it is half of.
    static let personNote = SettingHelp(
        title: "사람 메모",
        summary: "한 사람에 대해 적어 둔 글입니다. 그 사람이 말할 때 답장 요청에 함께 나갑니다.",
        topics: [
            .does(
                .init("내용", "그 사람이 하는 일, 만든 것, 서로 어떻게 부르고 어떤 말투를 쓰는지처럼 다음에 만나도 여전히 맞을 것을 적습니다."),
                .init("길이", "\(PersonNote.characterLimit)자까지입니다. 방 하나를 설명하는 채팅방 요약 \(ConversationSummary.characterLimit)자보다 짧습니다."),
                .init("수정", "직접 고쳐 쓸 수 있습니다. \"대학 동기, 서로 반말\"처럼 대화만 봐서는 알 수 없는 것을 적는 자리입니다."),
                .init("고정", "고정해 두면 자동 갱신이 이 메모를 건드리지 않습니다. 고정하지 않으면 직접 고친 문장도 다음 갱신에 다시 쓰입니다."),
                .init("삭제", "지우면 이 방의 메모와 링크가 함께 사라집니다. 다른 방의 메모는 그대로 남습니다."),
                .init("이름", "목록에 그리려고 함께 저장할 뿐입니다. 사람을 가리는 것은 카카오톡의 발신자 아이디입니다.")
            ),
            .applies(
                "방마다 하나입니다. 같은 사람이라도 방이 다르면 다른 메모이고, 서로 다른 내용일 수 있습니다.",
                "사람 기억을 켠 방의 대화만 들어갑니다. 꺼 둔 방에서 한 이야기는 메모에 남지 않습니다.",
                "채팅방 요약을 갱신할 때 함께 다시 씁니다. 따로 도는 일정은 없습니다.",
                "갱신할 때 끝난 이야기는 빠집니다. 다 빠지고 남을 것이 없으면 메모가 사라집니다."
            ),
            .costs(
                "이 메모 때문에 늘어나는 AI 호출은 없습니다.",
                "메모가 있는 사람이 말하면 그 답장 요청이 최대 \(PersonNote.characterLimit)자만큼 길어집니다.",
                "갱신은 전체 대화를 다시 읽지 않습니다. 어디까지 읽었는지 적어 두고 그 뒤에 온 것만 읽습니다."
            ),
            .doesNot(
                "직접 고친 메모를 자동으로 덮어쓰지 않습니다. 그 사람에 대해 사용자가 아는 것이 AI가 대화에서 읽어 낸 것보다 낫기 때문입니다. 직접 고친 메모는 저절로 사라지지도 않습니다.",
                "메모에 적힌 말을 지시로 읽지 않습니다. 답장 프롬프트에서 배경 설명으로만 다룹니다.",
                "방을 넘어 합쳐지지 않습니다. 여기서 고친 내용은 다른 방의 같은 사람에게 옮겨가지 않습니다.",
                "그날의 일을 적어 두지 않습니다. 대화 요약이 아니라 사람에 대한 기록입니다.",
                "이름이 바뀌었다고 새 메모를 만들지 않습니다. 같은 방에서 발신자 아이디가 같으면 같은 사람입니다."
            )
        ]
    )

    /// Links are kept out of the prose, and this card says why in the user's terms.
    ///
    /// A separate list for five URLs looks like needless structure until the reason
    /// is given: a model rewrites a URL with total confidence — one character
    /// changed, a plausible path invented — and a note that quietly corrupts
    /// somebody's address is worse than one that never carried it. Said plainly,
    /// the list stops looking like a form to fill in and starts looking like the
    /// reason the address is still right.
    static let personLinks = SettingHelp(
        title: "메모 속 링크",
        summary: "그 사람의 주소는 문장 안에 적지 않고 따로 담습니다.",
        topics: [
            .does(
                "대화에 나온 그 사람의 주소를 이름표와 함께 담습니다. 블로그, 저장소, 만든 것 정도입니다.",
                .init("개수", "저장은 제한이 없고, 답장에는 최근 \(PersonNote.linksPerReply)개만 실립니다."),
                .init("수정", "주소 하나만 따로 고치거나 지울 수 있습니다. 문장을 건드리지 않아도 됩니다."),
                "답장 요청에는 이 주소들이 정확한 값이니 바꾸지 말라는 지시와 함께 나갑니다."
            ),
            .applies(
                "메모와 같이 움직입니다. 그 사람이 말할 때 메모와 함께 나가고, 메모를 지우면 함께 지워집니다.",
                "\(PersonNote.linksPerReply)개가 넘어도 버리지 않습니다. 답장에 실리는 것만 최근 순으로 추려집니다."
            ),
            .costs("따로 드는 AI 호출은 없습니다. 답장 요청이 주소 줄 수만큼만 길어집니다."),
            .doesNot(
                "문장 안에 섞어 넣지 않습니다. AI는 주소를 자신 있게 고쳐 쓰고, 한 글자 바뀐 주소가 조용히 남는 편이 주소가 아예 없는 것보다 나쁩니다.",
                "대화에 오간 링크를 모으는 곳이 아닙니다. 그 사람을 가리키는 주소만 담습니다.",
                "주소를 열어 보지 않습니다. 살아 있는지 확인하지도, 내용을 받아 오지도 않습니다."
            )
        ]
    )
}
