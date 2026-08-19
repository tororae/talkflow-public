import Foundation
import TalkFlowDomain

/// The settings between a finished draft and a message somebody can read.
///
/// Sending is the one thing this app does that cannot be undone, and it works by
/// driving KakaoTalk's own window, so every card here names what it takes from
/// the user: the screen, the front app, or the ability to change their mind.
extension SettingHelp {
    static let deliveryMode = SettingHelp(
        title: "전송 방식",
        summary: "만든 답을 사람이 확인하고 보낼지, 앱이 직접 카카오톡에 입력할지 정합니다.",
        topics: [
            .does(
                .init("초안만", "만들기만 하고 보내지 않습니다. 활동 화면에서 사람이 눌러야 나갑니다."),
                .init("유휴 상태 자동 전송", "키보드·마우스 입력이 \(Int(SendGate.defaultRequiredIdleSeconds))초 넘게 없을 때만 스스로 보냅니다."),
                .init("상시 전송", "자리에 있어도 보냅니다. 카카오톡이 앞으로 나오면서 하던 일이 끊길 수 있습니다.")
            ),
            .applies(
                "답이 만들어진 뒤의 이야기입니다. 답을 만들지 말지는 응답 모드가 정합니다.",
                "설정의 \"전송 이용 정책 동의\"가 켜져 있어야 어느 방식이든 실제로 나갑니다."
            ),
            .costs(
                "자동 전송은 카카오톡 창을 직접 조작합니다. 다른 데스크탑에 있는 창이면 앱을 앞으로 가져옵니다.",
                "보낸 메시지는 되돌릴 수 없습니다. 개요 화면에 적힌 긴급 중지 단축키로 어디서든 즉시 멈출 수 있습니다."
            ),
            .doesNot(
                "상시 전송이라도 화면이 잠겨 있으면 보내지 않고 기다립니다.",
                "기다리는 사이 다른 사람이 답하거나 대화가 넘어가면 초안을 취소합니다. 상시 전송도 마찬가지입니다.",
                "닫힌 대화창을 대신 열어 주지 않습니다. 그 방의 대화창이 열려 있어야 전송이 성공합니다."
            )
        ]
    )

    static let sendUsePolicy = SettingHelp(
        title: "전송 이용 정책 동의",
        summary: "이 동의가 없으면 어떤 메시지도 카카오톡으로 나가지 않습니다.",
        topics: [
            .does(
                "동의해야 대기열의 초안이 실제로 전송됩니다.",
                "동의 전에 쌓인 초안은 취소되지 않고 기다립니다. 동의하는 순간 조건이 맞는 것부터 나갑니다.",
                "전송 직전에 다시 읽습니다. 동의를 끄면 다음 전송부터 즉시 막힙니다."
            ),
            .applies("모든 채팅방과 모든 전송 방식에 적용됩니다."),
            .costs("TalkFlow는 카카오톡 UI를 자동으로 조작해 보냅니다. 비공식 연동이고, 보낸 메시지는 되돌릴 수 없습니다."),
            .doesNot(
                "초안 만들기를 막지 않습니다. 동의 전에도 AI 호출은 일어나고 초안은 쌓입니다.",
                "동의만으로 자동 전송이 시작되지 않습니다. 방마다 전송 방식을 바꿔야 하고, 기본값은 초안만입니다."
            )
        ]
    )

    static let wakesDisplay = SettingHelp(
        title: "전송할 때 화면을 잠깐 켜기",
        summary: "화면이 꺼져 잠긴 동안에도 보낼 것이 있으면 화면을 깨워 전송합니다.",
        topics: [
            .does(
                "지금 나갈 수 있는 초안이 대기열에 있을 때만 화면을 깨웁니다.",
                "깨어난 뒤 전송합니다. 화면은 평소의 절전 시간이 지나면 알아서 다시 꺼집니다."
            ),
            .applies(
                "화면이 꺼져 잠긴 상태에서만 의미가 있습니다.",
                "전송 이용 정책에 동의했고 자동 응답이 켜져 있어야 합니다."
            ),
            .costs("화면이 켜집니다. 옆에 사람이 있으면 그대로 보입니다."),
            .doesNot(
                "macOS가 암호를 요구하기 시작한 뒤에는 깨워도 잠금이 풀리지 않아 계속 기다립니다.",
                "끄면 화면이 꺼져 있는 동안 전송이 계속 기다립니다. 다만 초안은 만들어진 지 \(Int(SendGate.defaultMaximumAge / 60))분이 지나면 취소됩니다."
            )
        ]
    )
}
