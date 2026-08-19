import Foundation
import TalkFlowDomain

/// The settings that decide whether a message gets an answer at all.
///
/// Three of them now, on three different axes, and a user who cannot tell them
/// apart will reach for the wrong one: 답변 조건 decides *what* is answered,
/// 끼어들기 확률 decides how often the model is asked, 판단 주기 decides when. The
/// two that cost money live in `SettingHelpPacing`; each card here names the
/// others rather than leaving the difference to be guessed.
///
/// Every one of these has already cost the user a day. A room left on
/// `멘션에만 응답` stayed silent because nobody had ever typed the registered word,
/// and `자발 개입 낮음` was indistinguishable from `보통` in code while the picker
/// offered both. Neither silence was visible from outside, so the cards say
/// plainly which messages never reach the model.
extension SettingHelp {
    static let responseMode = SettingHelp(
        title: "응답 모드",
        summary: "이 방에서 답을 만들지, 어떤 메시지에 만들지 정하는 첫 관문입니다.",
        topics: [
            .does(
                .init("끔", "판단도 답도 하지 않습니다."),
                .init("감지 전용", "지금은 끔과 같습니다. 대화 수집은 방 설정과 상관없이 계정 단위로 돌아가서, 이 둘이 실제로 하는 일에는 차이가 없습니다."),
                .init("멘션에만 응답", "\"이 방이 답하는 말\"로 부른 메시지에만 답합니다."),
                .init("자동응답", "1:1은 상대의 새 메시지마다, 단체방은 부른 메시지에 답하고 나머지는 끼어들기 확률이 정합니다.")
            ),
            .applies(
                "이 방에만 적용됩니다.",
                "개요 화면의 \"자동 응답\"이 꺼져 있으면 어느 모드든 아무 일도 하지 않습니다."
            ),
            .costs(
                .init("멘션에만 응답", "부른 메시지 하나마다 AI 호출 1회입니다. 아무도 부르지 않으면 호출도 0입니다."),
                .init("자동응답", "1:1에서는 상대 메시지 하나마다 호출 1회입니다. 이 값을 줄이는 것은 끼어들기 확률과 판단 주기입니다.")
            ),
            .doesNot(
                "멘션에만 응답은 끼어들기 확률을 보지 않습니다. 확률을 올려도 부르지 않은 메시지에는 답하지 않습니다.",
                "어느 모드도 메시지를 내보내지 않습니다. 실제 전송은 전송 방식이 정합니다.",
                "끔으로 두어도 카카오톡 대화를 읽어 오는 일 자체는 멈추지 않습니다."
            )
        ]
    )

    static let interjectionChance = SettingHelp(
        title: "끼어들기 확률",
        summary: "아무도 나를 부르지 않은 메시지를 AI에게 물어볼 확률입니다.",
        topics: [
            .does(
                .init("100%", "부르지 않은 메시지도 전부 AI에게 넘깁니다. 기본값입니다."),
                .init("0%", "하나도 넘기지 않습니다. 이름이나 키워드로 부른 메시지만 답합니다."),
                .init("40%", "열 개 중 넷쯤만 넘깁니다. 어느 것을 넘길지는 이 Mac에서 정합니다."),
                .init("물어보기만", "확률은 물어볼지만 정합니다. 답할지는 넘긴 뒤에 AI가 정하므로, 100%여도 답하지 않을 수 있습니다.")
            ),
            .applies(
                "단체방이면서 응답 모드가 자동응답일 때만 씁니다.",
                "나를 부른 메시지는 이 설정과 무관합니다. 0%여도 부름에는 답합니다.",
                "같은 방의 같은 메시지는 몇 번을 다시 봐도 결과가 같습니다. 뒷말 대기 뒤에 다시 뽑지 않습니다."
            ),
            .costs(
                .init("0%", "부르지 않은 메시지에는 호출이 나가지 않습니다."),
                .init("40%", "호출이 대략 그 비율로 줄어듭니다. 대신 넘기지 않은 메시지는 다시 보지 않습니다."),
                .init("판단 주기", "그쪽도 호출을 줄이지만 방식이 다릅니다. 확률은 버리고, 주기는 모아 두었다가 한 번에 묻습니다.")
            ),
            .doesNot(
                "AI를 부르지 않습니다. 넘길지 말지는 이 Mac 안에서만 정합니다.",
                "무엇에 답할지는 정하지 않습니다. 그것은 답변 조건입니다.",
                "1:1 대화에서는 아무 일도 하지 않습니다. 상대의 말은 전부 나에게 한 말입니다.",
                "멘션에만 응답인 방에서도 아무 일도 하지 않습니다.",
                "넘기지 않은 메시지를 모아 두지 않습니다. 활동 기록에도 남기지 않습니다."
            )
        ]
    )

    static let answeringCondition = SettingHelp(
        title: "답변 조건",
        summary: "어떤 말에 답할지 직접 문장으로 적습니다.",
        topics: [
            .does(
                "적은 문장을 AI 지시문에 그대로 넣고, 그 조건으로 답할지 판단하게 합니다.",
                "예: \"일정 잡는 얘기랑 나한테 직접 묻는 것 위주로. 잡담엔 끼지 마.\"",
                .init("입력", "\(AnsweringCondition.characterLimit)자까지 적습니다. 비워 두면 조건 없이 AI가 알아서 판단합니다.")
            ),
            .applies(
                "설정에 적은 조건이 모든 방에 적용됩니다.",
                "방에서 \"이 방만 다른 조건\"을 켜면 그 방은 방의 조건만 씁니다. 전역 조건과 합쳐지지 않습니다.",
                "나를 부른 메시지에도 적용됩니다. 사용자가 직접 적은 문장이므로 이름으로 불러도 조건이 우선합니다."
            ),
            .costs(
                "호출 수는 그대로입니다. 조건은 호출한 뒤에 AI가 읽는 문장이라 호출을 줄이지 않습니다.",
                "조건에 걸러진 판단도 호출 1회를 씁니다. 호출을 줄이려면 끼어들기 확률이나 판단 주기를 씁니다."
            ),
            .doesNot(
                "얼마나 자주 물어볼지는 정하지 않습니다. 그것은 끼어들기 확률과 판단 주기입니다.",
                "말투나 길이를 정하지 않습니다. 그것은 응답 스타일입니다.",
                "먼저 말 걸기에는 적용되지 않습니다. 그쪽은 답하는 일이 아니라 말을 꺼내는 일입니다.",
                "이 Mac에서 미리 걸러 내지 않습니다. 조건에 맞는지는 AI가 읽고 판단합니다."
            )
        ]
    )

    static let activeHours = SettingHelp(
        title: "답변 활성화 시간",
        summary: "이 방이 답해도 되는 시간대를 정합니다.",
        topics: [
            .does(
                "정한 시간대 안에서만 판단하고 답합니다. 시작 시각은 포함하고 종료 시각은 포함하지 않습니다.",
                "종료가 시작보다 이르면 자정을 넘는 하나의 시간대로 읽습니다. 22:00–02:00은 밤에 열려 다음 날 새벽에 닫힙니다."
            ),
            .applies(
                "이 방에만 적용됩니다.",
                "시작과 종료가 같으면 하루 종일로 봅니다. 아무 때도 답하지 않는 설정은 없습니다."
            ),
            .costs("시간대 밖에서는 AI를 아예 부르지 않습니다. 그래서 이 설정으로 줄어드는 호출이 가장 예측하기 쉽습니다."),
            .doesNot(
                "메시지 수집을 멈추지 않습니다. 대화는 계속 쌓입니다.",
                "시간대 밖의 메시지를 모아 두었다가 열리는 시각에 몰아서 답하지 않습니다. 그냥 지나갑니다.",
                "시간대 밖의 보류는 활동 기록에 남기지 않습니다. 조용한 것이 정상 동작입니다."
            )
        ]
    )
}
