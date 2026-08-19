import SwiftUI
import TalkFlowApplication
import TalkFlowDomain

/// 방별 응답 스타일: follow 설정, or hold this room's own 말투·길이·이모지·적극성.
///
/// Off in every room, so nothing changes for a room configured before this
/// existed. Turning it on copies the global values in rather than starting from
/// the app's defaults — a room whose style is being adjusted is usually a room
/// that wants the global one with one thing changed, and a section that opened on
/// "친근하고 간결하게" regardless of what 설정 says would quietly undo it.
struct RoomResponseStyleSection: View {
    private let entry: ChatRoomPolicy
    private let globalStyle: ResponseStyle
    private let onChange: (ResponseStyle?) -> Void

    init(
        entry: ChatRoomPolicy,
        globalStyle: ResponseStyle,
        onChange: @escaping (ResponseStyle?) -> Void
    ) {
        self.entry = entry
        self.globalStyle = globalStyle
        self.onChange = onChange
    }

    var body: some View {
        Section {
            // The `?` sits on the section title. One card covers the switch and
            // the four controls under it, and a second button opening the same
            // card teaches the reader that the buttons are not worth pressing.
            Toggle("이 방만 다른 스타일 사용", isOn: usesOwn)

            if let own = entry.policy.responseStyleOverride {
                EditableTextField(
                    "말투",
                    value: own.tone,
                    axis: .vertical,
                    lineLimit: 1...3,
                    onChange: { tone in
                        var updated = own
                        updated.tone = tone
                        onChange(updated)
                    }
                )
                .id(entry.id)
                Picker("답변 길이", selection: binding(\.length, in: own)) {
                    ForEach(ResponseStyle.Length.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Picker("이모지 사용", selection: binding(\.emojiUse, in: own)) {
                    ForEach(ResponseStyle.EmojiUse.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                SettingHelpRow("적극성", help: .assertiveness) {
                    Picker("적극성", selection: binding(\.assertiveness, in: own)) {
                        ForEach(ResponseStyle.Assertiveness.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                }
            }

            Text(note)
                .font(.footnote)
                .foregroundStyle(.secondary)
        } header: {
            SettingHelpLabel("응답 스타일", help: .roomResponseStyle)
        }
    }

    private var usesOwn: Binding<Bool> {
        Binding(
            get: { entry.policy.usesOwnResponseStyle },
            set: { on in onChange(on ? globalStyle : nil) }
        )
    }

    private func binding<Value>(
        _ keyPath: WritableKeyPath<ResponseStyle, Value>,
        in style: ResponseStyle
    ) -> Binding<Value> {
        Binding(
            get: { style[keyPath: keyPath] },
            set: { value in
                var updated = style
                updated[keyPath: keyPath] = value
                onChange(updated)
            }
        )
    }

    /// Says which style is in force and, when it is the global one, what that is.
    /// A room following 설정 is otherwise a section with one switch and nothing to
    /// read.
    private var note: String {
        guard entry.policy.usesOwnResponseStyle else {
            return """
            설정의 전역 스타일을 따릅니다: \(globalStyle.tone) · \(globalStyle.length.title) · \
            이모지 \(globalStyle.emojiUse.title) · \(globalStyle.assertiveness.title)
            """
        }
        return "이 방은 위 값으로만 답합니다. 설정의 전역 스타일을 바꿔도 따라가지 않습니다."
    }
}
