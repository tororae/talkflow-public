import SwiftUI

/// The keywords that apply to every room, on top of the account's own name.
///
/// The name is not in this list and never was meant to be: the app reads it from
/// KakaoTalk. The copy says so, because as long as this section was called
/// "키워드 반응" and described `@이름`, it read as the place where being mentioned
/// is configured — and a room set to `멘션에만 응답` stayed silent until somebody
/// guessed the account's KakaoTalk name and typed it here.
struct SettingsKeywordSection: View {
    private let keywords: [String]
    private let issue: String?
    private let onAdd: (String) -> Bool
    private let onRemove: (String) -> Void

    init(
        keywords: [String],
        issue: String?,
        onAdd: @escaping (String) -> Bool,
        onRemove: @escaping (String) -> Void
    ) {
        self.keywords = keywords
        self.issue = issue
        self.onAdd = onAdd
        self.onRemove = onRemove
    }

    var body: some View {
        Section {
            KeywordListEditor(
                keywords: keywords,
                emptyMessage: "등록된 키워드가 없습니다. 내 이름으로 부르는 것만 반응합니다.",
                issue: issue,
                onAdd: onAdd,
                onRemove: onRemove
            )

            Text("내 카카오톡 계정 이름은 앱이 직접 읽습니다. 등록하지 않아도 그 이름으로 부르면 반응합니다.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            // Said here because this is where somebody comes when the app did not
            // answer to their name. It reads as a limitation the app chose until it
            // says whose limitation it is: KakaoTalk stamps the account name on
            // outgoing messages and never the per-room one, so there is no row
            // anywhere that holds it.
            Text("방마다 이름을 따로 바꿔 두었다면 그 이름은 앱이 알 수 없습니다. 카카오톡이 내가 보낸 메시지에 계정 이름만 적기 때문입니다. 그 방 설정의 키워드에 직접 넣어 주세요.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text("여기에는 이름 말고 더 반응하고 싶은 말을 넣습니다. 봇 별명이나 예전에 쓰던 이름 같은 것들입니다. @를 붙여 부르든 그냥 부르든 똑같이 반응하고, 대소문자는 가리지 않습니다.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text("이 목록은 모든 채팅방에 적용됩니다. 한 방에서만 쓰는 말은 그 방의 설정에서 따로 등록합니다.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } header: {
            SettingHelpLabel("이름 외 추가 키워드", help: .globalKeywords)
        }
    }
}
