import Foundation
import TalkFlowDomain

/// 집중 시간 — the one feature whose settings change what the other settings mean.
///
/// Every card here has the same first job. A user who reads 집중 시간 and pictures a
/// room that answers *better* has misread it: it answers *faster*, and faster is
/// the expensive direction. The three values a burn swaps in are the two levers
/// this app sells everywhere else as the way to spend less — 끼어들기 확률 and
/// 판단 주기 — turned the other way round, so every 비용 section here says the call
/// volume goes up in as many words rather than leaving it to be inferred from
/// "확률 90%".
///
/// The second job is the arithmetic nobody does in their head. A burn is bought by
/// 발동 확률, sized by 지속 시간 and rationed by 쿨타임, and a card that explains its
/// own field without naming the other two leaves the user unable to answer the only
/// question they have — how much of the day is this room like that. Each card names
/// the two it is not.
extension SettingHelp {
    /// The switch, and the only card with room to say what the whole thing is.
    ///
    /// It leads with 꺼짐 for the same reason 먼저 말 걸기 does: this is the second
    /// setting in the app that makes a room behave unlike the settings printed on
    /// its own screen, and a user who has not turned it on should be able to stop
    /// reading after one line. What follows is the cycle in the order it happens,
    /// because the four cards after this one are each a piece of that cycle and are
    /// unreadable without it.
    static let burningMode = SettingHelp(
        title: "집중 시간",
        summary: "가끔 한동안 이 방에 붙어 있는 사람처럼 자주 답하게 합니다.",
        topics: [
            .does(
                .init("꺼짐", "기본값입니다. 이 방은 화면에 적힌 설정 그대로만 답합니다."),
                .init("켬", "답을 한 번 할 때마다 발동 확률을 뽑고, 맞으면 그 자리에서 집중이 시작됩니다."),
                .init("집중 중", "끼어들기 확률·최소 응답 간격·판단 주기가 집중 중 설정값으로 바뀝니다."),
                .init("끝", "지속 시간이 다 차면 원래 값으로 돌아가고, 쿨타임 동안은 다시 시작하지 않습니다.")
            ),
            .applies(
                "이 방에만 적용되고, 방마다 따로 켭니다.",
                "답변 활성화 시간 안에서만 집중합니다.",
                "응답 모드가 \"끔\"이나 \"감지 전용\"이면 켜도 아무 일도 하지 않습니다.",
                "개요 화면의 \"자동 응답\"이 꺼져 있으면 아무 일도 하지 않습니다."
            ),
            .costs(
                "집중 중에는 이 방의 AI 호출이 크게 늘어납니다. 끼어들기 확률을 올리고 판단 주기를 줄이는 일이 곧 호출을 늘리는 일입니다.",
                "말이 많은 방이면 기본값 \(burnLength) 동안 메시지 하나마다 호출 1회에 가까워집니다.",
                "얼마나 자주 그렇게 되는지는 발동 확률과 쿨타임이 정합니다."
            ),
            .doesNot(
                "무슨 말을 할지는 바꾸지 않습니다. 답변 조건과 응답 스타일은 집중 중에도 그대로입니다.",
                "답변 활성화 시간을 넘겨 쓰지 않습니다. 시간대가 닫히면 남은 지속 시간과 상관없이 끝납니다.",
                "먼저 말 걸기의 주기는 건드리지 않습니다. 집중 중이라고 말을 더 자주 걸지 않습니다.",
                "멘션에만 응답인 방에서는 답하는 메시지가 늘지 않습니다. 그 방은 끼어들기 확률을 쓰지 않습니다.",
                "화면에 적어 둔 설정을 고치지 않습니다. 집중이 끝나면 그 값 그대로 돌아옵니다.",
                "집중이 시작되고 끝난 것을 방에 알리지 않습니다. 그것은 자리 알림이고 따로 켭니다."
            )
        ]
    )

    /// Rolled after an answer, not on every message.
    ///
    /// That one sentence is the whole reason this card exists. Read as a per-message
    /// chance, 10% in a busy room sounds like a burn every few minutes, and the user
    /// sets 1% and then waits a week; read the same wrong way in a room nobody
    /// answers, 100% looks broken. The card also has to separate this number from
    /// 끼어들기 확률, which is the other percentage on the same screen and decides
    /// something else entirely.
    static let burningChance = SettingHelp(
        title: "발동 확률",
        summary: "답을 한 번 할 때마다 이 확률로 집중 시간이 시작됩니다.",
        topics: [
            .does(
                "이 방이 실제로 답을 하나 내놓을 때마다 한 번 뽑습니다.",
                .init("기본값", "\(burningDefaults.chance.summary)입니다. 열 번쯤 답하면 한 번 집중이 걸리는 정도입니다."),
                .init("0%", "걸리지 않습니다. 집중 시간을 켜 둔 채로 멈춰 두는 방법입니다."),
                .init("100%", "답할 때마다 걸립니다. 쿨타임이 끝나 있을 때만입니다.")
            ),
            .applies(
                "이 방에만 적용됩니다.",
                "쿨타임 안에서는 뽑지 않습니다. 확률을 아무리 올려도 그동안에는 시작되지 않습니다.",
                "이미 집중 중일 때도 뽑지 않습니다. 집중이 집중을 다시 시작하지는 않습니다."
            ),
            .costs(
                "뽑는 일 자체에는 호출이 들지 않습니다. 이 Mac 안에서 정합니다.",
                "대신 한 번 맞을 때마다 집중 한 번치 호출을 사는 셈입니다.",
                "확률을 두 배로 올리면 집중이 걸리는 횟수도 대략 두 배가 됩니다. 쿨타임이 허락하는 만큼입니다."
            ),
            .doesNot(
                "메시지마다 뽑지 않습니다. 답이 하나 나온 뒤에만 한 번 뽑습니다.",
                "답할 확률이 아닙니다. 무엇에 답할지는 응답 모드와 끼어들기 확률과 답변 조건이 정합니다.",
                "아무도 답을 끌어내지 못하는 방에서는 100%여도 아무 일도 일어나지 않습니다.",
                "집중이 얼마나 갈지는 정하지 않습니다. 그것은 지속 시간입니다."
            )
        ]
    )

    /// The length is drawn once, when the burn starts, and does not move after that.
    ///
    /// The card says so because the two things a user expects to move it are exactly
    /// the two things that happen during a burn: more answers going out, and the room
    /// falling quiet. Neither does anything. The one thing that does cut it short —
    /// 답변 활성화 시간 closing — is the one nobody expects, so it is named twice.
    static let burningDuration = SettingHelp(
        title: "지속 시간",
        summary: "한 번 걸린 집중이 얼마나 가는지 범위로 적습니다.",
        topics: [
            .does(
                "집중이 시작될 때 이 범위에서 하나를 뽑아 그만큼 유지합니다.",
                .init("기본값", "\(burnLength)입니다. 잠깐 붙어 있다 가는 정도의 길이입니다."),
                .init("범위", "최소와 최대를 다르게 적으면 집중마다 길이가 달라집니다. 같게 적으면 매번 같습니다.")
            ),
            .applies(
                "이 방에만 적용됩니다.",
                "시작할 때 뽑은 길이가 그 집중 동안 그대로입니다. 도중에 다시 뽑지 않습니다.",
                "답변 활성화 시간이 닫히면 남은 길이와 상관없이 거기서 끝납니다."
            ),
            .costs(
                "이 길이가 곧 비싼 구간의 길이입니다. 호출은 대체로 이 값에 비례해 늘어납니다.",
                "\(burnLength)짜리 집중은 말이 오가는 방이라면 그 시간 동안의 메시지 대부분에 호출이 나가는 일입니다."
            ),
            .doesNot(
                "집중 중에 답을 더 한다고 늘어나지 않습니다. 시작할 때 정해진 시각에 끝납니다.",
                "방이 조용해졌다고 일찍 끝나지도 않습니다. 시간이 다 찰 때까지는 집중 중입니다.",
                "다음 집중까지의 간격은 정하지 않습니다. 그것은 쿨타임입니다.",
                "집중 중에 무엇이 달라지는지도 정하지 않습니다. 그것은 집중 중 설정값입니다."
            )
        ]
    )

    /// The only number in this feature that spends less rather than more.
    ///
    /// Worth saying plainly, because it is also the one a user reaches for last: the
    /// interesting settings are the chance and the length, and a room left on a short
    /// cooldown can sit in one burn after another without any single field on the
    /// screen looking wrong.
    static let burningCooldown = SettingHelp(
        title: "쿨타임",
        summary: "집중이 끝난 뒤 이 시간 동안은 다시 걸리지 않습니다.",
        topics: [
            .does(
                "집중이 끝난 시각부터 잽니다. 그 사이에는 발동 확률을 뽑지 않습니다.",
                .init("기본값", "\(burnGap)입니다. 방금 한참 붙어 있던 사람이 곧바로 돌아오지는 않기 때문입니다."),
                .init("범위", "집중이 시작될 때 이 범위에서 함께 뽑습니다. 그래서 간격도 일정하지 않습니다.")
            ),
            .applies(
                "이 방에만 적용됩니다.",
                "집중 중에는 흐르지 않습니다. 집중이 끝난 다음부터 셉니다."
            ),
            .costs(
                "이 기능에서 호출을 줄이는 값은 이것 하나입니다. 길게 둘수록 비싼 구간이 드물어집니다.",
                "짧게 두면 집중이 연달아 붙어 방이 거의 늘 집중 상태가 될 수 있습니다."
            ),
            .doesNot(
                "쿨타임 중이라고 방이 조용해지지 않습니다. 화면에 적힌 원래 설정대로 답합니다.",
                "집중을 중간에 끊지 않습니다. 이 값은 끝난 뒤의 이야기입니다.",
                "이미 시작된 쿨타임은 값을 고쳐도 짧아지지 않습니다. 그 집중이 시작될 때 이미 뽑혔습니다.",
                "답변 활성화 시간이 닫혀 집중이 일찍 끝나도 줄어들지 않습니다. 짧게 탄 만큼 일찍 돌아오지는 않습니다."
            )
        ]
    )

    /// Absolute values, not bonuses.
    ///
    /// `BurningMode`'s own doc records why: an earlier reading had a 상승폭, and
    /// "raise the chance by 40 points" leaves a 10% room and an 80% room burning at
    /// wildly different rates from one setting, with neither resulting number
    /// appearing anywhere on screen. The card exists so the replacement is not read
    /// as the addition it replaced — and so the user can see that these three fields
    /// are where the whole cost of the feature is decided.
    static let burningValues = SettingHelp(
        title: "집중 중 설정값",
        summary: "집중 동안 방의 세 설정을 이 값으로 바꿔 놓습니다.",
        topics: [
            .does(
                .init("끼어들기 확률", "기본값은 \(burningDefaults.interjectionChance.summary)입니다. 부르지 않은 메시지도 대부분 AI에게 넘깁니다."),
                .init("최소 응답 간격", "기본값 \(burnMinimumInterval). 한 번 답한 직후에 온 메시지도 그대로 봅니다."),
                .init("판단 주기", "기본값 \(burningDefaults.judgementInterval.summary). 메시지가 올 때마다 판단합니다."),
                "집중이 끝나면 세 값 모두 방의 원래 값으로 돌아옵니다."
            ),
            .applies(
                "집중 중에만 적용됩니다. 집중이 아닐 때는 이 값들이 아무 일도 하지 않습니다.",
                "방에서와 같은 규칙입니다. 여기 판단 주기를 즉시가 아닌 값으로 두면 여기 최소 응답 간격도 잠깁니다.",
                "끼어들기 확률은 단체방이면서 자동응답일 때만 쓰입니다. 이것도 방에서와 같습니다."
            ),
            .costs(
                "집중의 비용은 사실상 이 세 값입니다. 확률이 높고 주기가 짧을수록 호출이 그만큼 늘어납니다.",
                "기본값대로면 대화가 오가는 동안 메시지 하나마다 호출 1회에 가깝습니다.",
                "값을 낮춰 두면 집중이 걸려도 방이 크게 바빠지지 않습니다. 집중을 끄지 않고 비용을 줄이는 방법입니다."
            ),
            .doesNot(
                "방의 값에 더하지 않습니다. 집중 동안에는 방의 값 대신 여기 적은 값만 씁니다.",
                "방에 저장된 설정을 고치지 않습니다. 집중이 끝나면 화면에 적힌 값으로 그대로 돌아옵니다.",
                "답변 조건과 응답 스타일은 여기 없습니다. 집중은 속도만 바꾸고 무슨 말을 할지는 바꾸지 않습니다.",
                "판단 주기를 즉시로 두어도 답변 활성화 시간 밖에서는 판단하지 않습니다."
            )
        ]
    )

    /// The only part of 집중 시간 that speaks.
    ///
    /// Which puts it in the same category as 먼저 말 걸기 — words appearing in a room
    /// under the user's name with nobody having asked — and the card says that rather
    /// than filing it under 알림, which in every other app means something that
    /// appears on the user's own screen.
    ///
    /// Its cost line is the one people get wrong: the call is spent when the app asks
    /// what to say, so a transition the model decides to pass on costs exactly as much
    /// as one it answers.
    static let burningAnnouncement = SettingHelp(
        title: "자리 알림",
        summary: "집중이 시작되고 끝날 때 방에 한 줄 남깁니다.",
        topics: [
            .does(
                "집중이 시작되면 \"이제 좀 붙어있는다\"쯤 되는 말을, 끝나면 \"나 가봐야 함\"쯤 되는 말을 남깁니다.",
                "답변 활성화 시간이 열릴 때도, 닫히기 전에도 같은 방식으로 알립니다.",
                "닫힐 때는 닫히기 전에 말합니다. 조용해진 뒤에 사정을 설명해 봐야 읽을 사람이 없습니다.",
                "문장은 그때마다 AI가 씁니다. 정해진 문구를 돌려 쓰지 않습니다."
            ),
            .applies(
                "이 방에만 적용되고, 방마다 따로 켭니다.",
                "최근에 대화가 오간 방에만 알립니다. 조용한 방에 혼자 상태를 남기지 않습니다.",
                "집중 시간이 꺼져 있는 방에서는 집중에 대해 알릴 것이 없습니다."
            ),
            .costs(
                "전환마다 AI 호출 1회입니다. 할 말이 없다고 나와도 그 호출은 나갑니다.",
                "나간 말은 되돌릴 수 없습니다. 답장과 달리 상대가 기다린 말도 아닙니다.",
                "집중이 자주 걸리는 방일수록 전환도 잦아 그만큼 호출이 붙습니다."
            ),
            .doesNot(
                "매번 말하지 않습니다. 할 말이 마땅치 않으면 AI가 그냥 넘깁니다.",
                "집중 자체를 바꾸지 않습니다. 꺼 두어도 집중은 그대로 시작하고 끝납니다.",
                "전환 시각에 딱 맞춰 알리지는 않습니다. 그 방을 다음에 들여다볼 때 알립니다.",
                "한 전환을 두 번 알리지 않습니다.",
                "이야깃거리를 꺼내지 않습니다. 먼저 말 걸기와 달리 상태 한 줄이지 대화를 여는 말이 아닙니다."
            )
        ]
    )

    /// A fresh room's numbers, quoted rather than retyped.
    ///
    /// `BurningMode.off` is a whole untouched setting, switch included, so the values
    /// beside the switch are the defaults every field starts on. Named here so the
    /// cards do not read as if 꺼짐 were a set of numbers of its own.
    private static var burningDefaults: BurningMode { .off }

    /// The two ends of the default burn and the default gap, read off the constants
    /// for the same reason `messageFloor` is. Both are quoted on more than one card,
    /// and a limit typed by hand goes on saying the old number after the constant has
    /// moved on.
    private static var burnLength: String {
        "\(Int(BurningMode.defaultDuration.shortest / 60))분~\(Int(BurningMode.defaultDuration.longest / 60))분"
    }

    private static var burnGap: String {
        "\(Int(BurningMode.defaultCooldown.shortest / 3600))시간~\(Int(BurningMode.defaultCooldown.longest / 3600))시간"
    }

    /// 없음 rather than 0초, because zero here is the absence of a wait and "0초 뒤에
    /// 다시 답합니다" is a sentence the reader has to translate. Still read off the
    /// constant: a default that grows a wait one day should say so.
    private static var burnMinimumInterval: String {
        let seconds = Int(burningDefaults.minimumInterval.rounded())
        return seconds > 0 ? "\(seconds)초" : "없음"
    }
}
