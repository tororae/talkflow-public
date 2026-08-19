import SwiftUI
import TalkFlowDomain

/// Which model answers, which nothing in this app used to say.
///
/// Before this section existed the model was whatever `~/.codex/config.toml`
/// happened to hold, TalkFlow passed no `-m` at all, and no screen mentioned any
/// of it. So editing Codex CLI's config for an unrelated project silently changed
/// how well KakaoTalk got answered, and there was nowhere to notice. The footnote
/// under 선택 안 함 says that out loud rather than leaving the default looking like
/// an absence of a setting.
///
/// Written the moment it is picked, like the switches below it and unlike the
/// style fields above it. It is read when a call goes out, so a value waiting for
/// 저장 would have this section name one model while another kept answering.
struct SettingsAIModelSection: View {
    private let choice: AIModelChoice
    private let options: [AIModel]
    private let onChange: (AIModelChoice) -> Void

    init(
        choice: AIModelChoice,
        options: [AIModel],
        onChange: @escaping (AIModelChoice) -> Void
    ) {
        self.choice = choice
        self.options = options
        self.onChange = onChange
    }

    var body: some View {
        Section {
            SettingHelpRow("모델", help: .aiModel) {
                Picker("모델", selection: selection) {
                    Text(Self.defaultTitle).tag(AIModelChoice.codexDefault)
                    ForEach(options) { Text($0.name).tag(AIModelChoice.pinned($0)) }
                }
                .labelsHidden()
            }

            // The picker shows a name; this line says what that name means. Sol
            // and Luna are not words anybody can rank by looking at them.
            Text(detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text("답장과 채팅방 요약이 모두 이 모델을 씁니다. 바꾸면 다음 호출부터 적용됩니다.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } header: {
            SettingHelpLabel("AI 모델", help: .aiModel)
        }
    }

    private static let defaultTitle = "선택 안 함 (Codex 설정 그대로)"

    private var selection: Binding<AIModelChoice> {
        Binding(get: { choice }, set: { onChange($0) })
    }

    private var detail: String {
        switch choice {
        case .codexDefault:
            // Deliberately does not claim to know which model that is. TalkFlow
            // does not read that file, and a screen guessing at its contents
            // would be wrong the first time somebody edited it.
            return """
            지금은 TalkFlow가 모델을 지정하지 않고, Codex CLI가 설정된 모델을 씁니다. \
            터미널에서 다른 작업 때문에 Codex 설정을 바꾸면 답장 품질도 함께 바뀝니다.
            """
        case let .pinned(model):
            return "\(model.summary) (\(model.id))"
        }
    }
}
