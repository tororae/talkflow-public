import Foundation

/// What counts as being called, and where each kind of call word is registered.
///
/// The name and the keywords were one list for a long time, and that is what made
/// `멘션에만 응답` unusable: the room only answered once somebody had typed the
/// account's KakaoTalk name into settings, spelled the way other people spell it.
/// They are separate concepts now, and this is where that lands in front of the
/// user — including the sentence that explains a room which is set up correctly
/// and still says nothing all day.
extension SettingHelp {
    static let roomCallSigns = SettingHelp(
        title: "이 방이 답하는 말",
        summary: "\"나를 불렀다\"가 무엇인지 정하는 곳입니다. 이름과 키워드는 서로 다른 것입니다.",
        topics: [
            .does(
                .init("내 계정 이름", "카카오톡에서 앱이 직접 읽어 옵니다. 등록할 것이 없습니다."),
                .init("이 방에서 바꾼 내 이름", "앱이 읽을 수 없습니다. 카카오톡은 내가 보낸 메시지에 계정 이름만 적어서, 방마다 바꾼 이름은 어디에도 남지 않습니다. 그 이름으로 부르는 것에 답하려면 아래 \"이 방 키워드\"에 직접 넣으세요."),
                .init("전역 키워드", "설정에 등록한 말이고 모든 방에 적용됩니다."),
                .init("이 방 키워드", "이 방에서만 적용됩니다. 위의 둘을 대체하지 않고 거기에 더합니다.")
            ),
            .applies(
                "멘션에만 응답인 방은 이 말들로 부른 메시지에만 답합니다.",
                "자동응답인 방에서도 부름이 먼저입니다. 끼어들기 확률은 부름이 없을 때만 봅니다."
            ),
            .costs("부른 메시지 하나마다 AI 호출 1회입니다. 흔한 말을 키워드로 넣으면 그만큼 호출이 늘어납니다."),
            .doesNot(
                "이름은 낱말이 시작하는 자리에서만 걸립니다. 더 긴 낱말 안에 묻힌 것은 부름으로 보지 않고, 뒤에 붙는 한글 조사는 그대로 통과시킵니다.",
                "키워드는 그런 제한이 없습니다. 메시지 어디에 있든 걸리므로 짧은 말은 자주 걸립니다.",
                "이 말들을 아무도 쓰지 않으면 멘션에만 응답인 방은 설정이 멀쩡해도 하루 종일 조용합니다. 아래의 최근 대화 확인이 그 경우를 알려 줍니다."
            )
        ]
    )

    static let roomKeywords = SettingHelp(
        title: "이 방에서만 쓸 키워드",
        summary: "이 방 안에서만 나를 뜻하는 말을 등록합니다.",
        topics: [
            .does(
                "여기 등록한 말로 부르면 이 방에서 부름으로 인정합니다.",
                "내 이름과 전역 키워드는 그대로 두고 거기에 더합니다."
            ),
            .applies(
                "이 방에서만 적용됩니다. 다른 방은 영향을 받지 않습니다.",
                "대소문자를 가리지 않고, 앞에 붙인 @는 무시합니다."
            ),
            .costs("걸릴 때마다 AI 호출 1회입니다. 그 방에서 자주 오가는 낱말을 넣으면 호출이 크게 늘어납니다."),
            .doesNot(
                "내 계정 이름은 여기 넣지 않아도 됩니다. 앱이 직접 읽습니다.",
                "다만 이 방에서 이름을 따로 바꿔 두었다면 그 이름은 앱이 알 수 없으니 여기 넣어야 합니다.",
                "여기서 지워도 계정 이름과 전역 키워드로 부르는 것은 계속 반응합니다."
            )
        ]
    )

    static let globalKeywords = SettingHelp(
        title: "이름 외 추가 키워드",
        summary: "모든 채팅방에 함께 적용되는 호출어입니다.",
        topics: [
            .does("봇 별명이나 예전에 쓰던 이름처럼, 내 이름으로는 덮이지 않는 말을 넣습니다."),
            .applies(
                "모든 방에 적용됩니다. 한 방에서만 통하는 말은 그 방 설정에 넣습니다.",
                "대소문자를 가리지 않고, 앞에 붙인 @는 무시합니다."
            ),
            .costs("흔한 말을 넣으면 모든 방에서 걸려 AI 호출이 한꺼번에 늘어납니다."),
            .doesNot(
                "내 계정 이름은 여기 넣지 않아도 됩니다. 앱이 직접 읽어 오고, 등록하지 않아도 반응합니다.",
                "방마다 따로 바꾼 이름은 여기가 아니라 그 방 설정에 넣으세요. 모든 방에 걸리면 다른 방에서 엉뚱하게 답합니다.",
                "낱말 경계를 따지지 않습니다. 메시지 안 어디에 들어 있어도 걸립니다."
            )
        ]
    )
}
