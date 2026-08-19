import Foundation
import TalkFlowDomain

/// The settings that shape the answer rather than deciding whether there is one.
///
/// They sit next to settings that look similar and are not. `적극성` reads like
/// `자발 개입` and changes nothing about when a room speaks. `사진 함께 읽기` is
/// the odd one out here: it is the only switch in the app that widens what leaves
/// the Mac, so its card leads with that.
extension SettingHelp {
    static let readsPhotos = SettingHelp(
        title: "사진 함께 읽기",
        summary: "이 방의 사진을 답장 요청에 첨부합니다. 사진 파일 자체가 나가는 유일한 설정입니다.",
        topics: [
            .does(
                "이 방의 최근 사진을 최대 \(MessagePhotoSelection.limit)장까지 AI 호출에 첨부하고, 누가 언제 보낸 사진인지 함께 적습니다.",
                "끄면 사진 메시지는 \"(사진)\"이라는 글자로만 전달되어, 무엇이 찍혔는지 모른 채 답합니다."
            ),
            .applies("이 방에만 적용됩니다. 방마다 사진의 성격이 다르므로 따로 켭니다."),
            .costs(
                "대화 글에 더해 사진 파일이 AI 제공자로 나갑니다. 사진에 우연히 함께 찍힌 것도 같이 갑니다.",
                "이미지가 붙는 만큼 답장 한 번의 값이 올라갑니다."
            ),
            .doesNot(
                "이 Mac에 이미 받아 둔 사진만 씁니다. 사진을 받으려고 카카오 서버에 요청하지 않습니다.",
                "꺼낸 파일을 남기지 않습니다. 호출이 끝나면 지우고, 호출이 실패해도 지웁니다."
            )
        ]
    )

    static let webSearch = SettingHelp(
        title: "웹 검색",
        summary: "답에 필요할 때 AI가 실시간 웹 검색을 씁니다. 이 방의 대화가 검색어가 되어 나갑니다.",
        topics: [
            .does(
                "최신 사실 확인이 답에 꼭 필요할 때만 AI가 스스로 웹을 검색해 반영합니다.",
                "끄면 검색 없이, 대화와 이미 아는 것만으로 답합니다."
            ),
            .applies("이 방에만 적용됩니다. 방마다 검색이 필요한 정도가 다르므로 따로 켭니다."),
            .costs(
                "대화에서 뽑은 검색어가 제공자의 웹 검색을 거쳐 나갑니다. 대화 글에 더해 검색 질의가 밖으로 더 나가는 셈입니다.",
                "검색이 붙는 답장은 시간이 더 걸리고 값도 올라갑니다."
            ),
            .doesNot(
                "이 Mac에서 명령을 실행하거나 파일을 건드리지 않습니다. read-only 잠금은 그대로이고, 검색은 제공자 쪽에서 도는 도구입니다.",
                "매 메시지마다 검색하지 않습니다. 답할 필요가 있고 사실 확인이 필요할 때만 씁니다."
            )
        ]
    )

    static let readsLinks = SettingHelp(
        title: "링크 읽기",
        summary: "대화에 올라온 링크를 앱이 직접 열어 페이지 내용을 답장 요청에 넣습니다.",
        topics: [
            .does(
                "메시지에 있는 최근 링크를 최대 \(MessageLinkSelection.limit)개까지 앱이 열어, 페이지의 글을 뽑아 답에 씁니다.",
                "끄면 링크는 주소 글자로만 전달되어, 그 안에 무엇이 있는지 모른 채 답합니다."
            ),
            .applies("이 방에만 적용됩니다. 방마다 오가는 링크의 성격이 다르므로 따로 켭니다."),
            .costs(
                "페이지를 열려고 그 주소로 요청이 나갑니다. 대화 글에 더해 링크 안의 내용도 답을 만드는 데 쓰입니다.",
                "페이지를 실제로 렌더해 읽으므로 그 답장은 몇 초 더 걸립니다."
            ),
            .doesNot(
                "모델이 브라우징하는 게 아닙니다. 앱이 열어 텍스트만 넘기고, 모델은 read-only 그대로입니다.",
                "사설·로컬 주소(localhost·내부 IP)는 열지 않습니다. 매 메시지마다 열지도 않고, 최근 링크 몇 개만 봅니다."
            )
        ]
    )

    static let assertiveness = SettingHelp(
        title: "적극성",
        summary: "AI가 답을 쓸 때의 태도입니다. 얼마나 자주 답하는지와는 상관이 없습니다.",
        topics: [
            .does("\"신중하게 / 보통 / 적극적으로\" 중 고른 것을 AI 지시문에 적어 보냅니다. 답의 문장이 달라집니다."),
            .applies("설정의 값이 모든 방에 적용되고, 방에서 \"이 방만 다른 응답 스타일\"을 켜면 그 방은 방의 값을 씁니다."),
            .costs("없습니다. 호출 수도 판단 대상도 달라지지 않습니다."),
            .doesNot(
                "끼어드는 빈도를 바꾸지 않습니다. 그것은 방마다 정하는 끼어들기 확률입니다.",
                "\"적극적으로\"로 두어도 부르지 않은 메시지에 답하게 되지는 않습니다."
            )
        ]
    )

    static let roomResponseStyle = SettingHelp(
        title: "이 방만 다른 응답 스타일",
        summary: "이 방에서만 쓸 말투·길이·이모지·적극성을 따로 둡니다.",
        topics: [
            .does(
                .init("끔", "설정의 전역 응답 스타일을 그대로 따릅니다. 기본값입니다."),
                .init("켬", "이 방의 값만 씁니다. 켜는 순간 전역 값이 그대로 복사되어 들어오므로 고칠 곳부터 고치면 됩니다.")
            ),
            .applies(
                "이 방의 답장과 먼저 걸 말에 적용됩니다.",
                "켜 둔 방은 설정의 전역 스타일을 바꿔도 따라가지 않습니다."
            ),
            .costs("없습니다. 호출 수도 판단 대상도 달라지지 않습니다."),
            .doesNot(
                "무엇에 답할지를 바꾸지 않습니다. 그것은 답변 조건과 끼어들기 확률입니다.",
                "\"이름 외 추가 키워드\"는 가져오지 않습니다. 그 말들은 스타일이 아니라 부름이라 전역 그대로 남습니다.",
                "끄면 방에 적어 둔 값은 남지 않습니다. 다시 켜면 그때의 전역 값에서 시작합니다."
            )
        ]
    )
}
