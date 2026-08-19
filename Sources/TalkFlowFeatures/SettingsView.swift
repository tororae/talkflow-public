import SwiftUI
import TalkFlowDomain

struct SettingsView: View {
    private let model: SettingsModel
    /// Nil without a database, exactly as the other stores degrade. The section is
    /// simply left off then rather than drawn empty.
    private let adminRooms: AdminRoomsModel?

    init(model: SettingsModel, adminRooms: AdminRoomsModel? = nil) {
        self.model = model
        self.adminRooms = adminRooms
    }

    var body: some View {
        Form {
            Section("응답 스타일") {
                EditableTextField(
                    "전체 말투",
                    value: model.draftStyle.tone,
                    onChange: { model.update(\.tone, to: $0) }
                )
                Picker("답변 길이", selection: binding(\.length)) {
                    ForEach(ResponseStyle.Length.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Picker("이모지 사용", selection: binding(\.emojiUse)) {
                    ForEach(ResponseStyle.EmojiUse.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                SettingHelpRow("적극성", help: .assertiveness) {
                    Picker("적극성", selection: binding(\.assertiveness)) {
                        ForEach(ResponseStyle.Assertiveness.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                }
                Text("이 설정은 모든 채팅방에 적용됩니다. 방마다 다르게 쓰려면 그 방의 \"이 방만 다른 스타일 사용\"을 켜세요.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                EditableTextField(
                    "예: 일정 잡는 얘기랑 나한테 직접 묻는 것 위주로. 잡담엔 끼지 마.",
                    value: model.draftCondition,
                    onChange: { model.updateCondition($0) }
                )
                if let issue = model.conditionIssue {
                    Label(issue, systemImage: "exclamationmark.circle")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
                // Says which of the three levers this is. The other two decide how
                // often the model is asked; this one decides what it answers, and
                // a user who reaches for the wrong one gets silence they cannot
                // explain.
                Text("여기 적은 말을 AI에게 그대로 전달해 답할지 판단하게 합니다. 호출 수는 줄지 않습니다. 그것은 방마다 정하는 끼어들기 확률과 판단 주기입니다.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                SettingHelpLabel("답변 조건", help: .answeringCondition)
            }

            SettingsKeywordSection(
                keywords: model.draftStyle.responseKeywords,
                issue: model.keywordIssue,
                onAdd: { model.addKeyword($0) },
                onRemove: { model.removeKeyword($0) }
            )

            SettingsSaveBar(
                status: model.saveStatus,
                hasUnsavedChanges: model.hasUnsavedChanges,
                canSave: model.canSave,
                onSave: { Task { await model.save() } },
                onCancel: { model.revert() }
            )

            // Below the save bar, with the switches, because it writes itself the
            // moment it is picked. Above 자동 전송, because this screen reads in the
            // order the work happens: what the answer is, then whether it goes.
            SettingsAIModelSection(
                choice: model.aiModel,
                options: model.aiModelOptions,
                onChange: { model.setAIModel($0) }
            )

            Section("자동 전송") {
                SettingHelpRow("전송 이용 정책과 면책 고지에 동의합니다", help: .sendUsePolicy) {
                    Toggle("전송 이용 정책과 면책 고지에 동의합니다", isOn: Binding(
                        get: { model.sendUsePolicyAccepted },
                        set: { model.setSendUsePolicyAccepted($0) }
                    ))
                    .labelsHidden()
                }
                Text("TalkFlow는 카카오톡 UI를 자동으로 조작해 메시지를 보냅니다. 비공식 연동이며, 보낸 메시지는 되돌릴 수 없습니다. 동의하기 전에는 어떤 메시지도 전송되지 않고 초안만 만들어집니다.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Link(
                    "katok 이용 정책과 면책 고지 읽기",
                    destination: URL(string: "https://github.com/NomaDamas/katok")!
                )
                .font(.footnote)
                // Named only 유휴 상태 자동 전송 until 상시 전송 existed, so the one
                // mode a user would pick to answer while they are at the machine
                // was missing from the sentence telling them where to look.
                Text("자동 전송을 실제로 쓰려면 채팅방별로 전송 방식을 ‘유휴 상태 자동 전송’이나 ‘상시 전송’으로 바꿔야 합니다. 기본값은 초안만입니다.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                SettingHelpRow("전송할 때 화면을 잠깐 켜기", help: .wakesDisplay) {
                    Toggle("전송할 때 화면을 잠깐 켜기", isOn: Binding(
                        get: { model.wakesDisplayToSend },
                        set: { model.setWakesDisplayToSend($0) }
                    ))
                    .labelsHidden()
                }
                // Four sentences of prose until the `?` beside it could hold the
                // conditions in a shape somebody reads. What stays is the pair a
                // person needs before deciding; the rest is one click away.
                Text("화면이 꺼지면 잠금 화면이 앞을 차지해 카카오톡에 입력할 수 없습니다. 이 설정을 끄면 화면이 꺼져 있는 동안 전송이 계속 대기합니다.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("실행") {
                Toggle("Mac 로그인 시 TalkFlow 실행", isOn: Binding(
                    get: { model.launchesAtLogin },
                    set: { model.setLaunchesAtLogin($0) }
                ))
                Text("기본값은 꺼짐입니다. 실제 등록은 TalkFlow를 앱으로 설치한 뒤 적용됩니다.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            // Last, and its own section: it is a power feature and the one place
            // the app runs what a message says, so it sits apart from the reply
            // settings rather than among them.
            if let adminRooms {
                AdminRoomsSection(model: adminRooms)
            }

            if let failure = model.failure {
                Section {
                    Label(failure, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("설정")
        .task { await model.loadIfNeeded() }
    }

    /// Pickers write into the draft; nothing reaches disk until 저장.
    private func binding<Value>(_ keyPath: WritableKeyPath<ResponseStyle, Value>) -> Binding<Value> {
        Binding(
            get: { model.draftStyle[keyPath: keyPath] },
            set: { model.update(keyPath, to: $0) }
        )
    }
}
