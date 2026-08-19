import Foundation
import SwiftUI
import TalkFlowApplication
import TalkFlowDomain

/// What this room answers to, and whether anybody has used it lately.
///
/// A room that is never called holds every message for `notAddressed`, and that
/// hold stays out of the timeline on purpose — it would fire on every message in
/// every quiet room. So the question it leaves open is answered here, where the
/// setting is: these are the words, this is how often they were said. Silence
/// that a person can read is a setting; silence they cannot is a bug report.
struct RoomCallSignSection: View {
    private let signs: CallSigns
    private let recentCalls: RecentCallReport?
    private let issue: String?
    private let onAdd: (String) -> Bool
    private let onRemove: (String) -> Void
    /// Whether the name was read from this room's own history rather than from the
    /// account-wide lookup. Not whether it is this room's name — KakaoTalk stamps
    /// the account name on outgoing messages and never the per-room one, so both
    /// reads return the same string and only their dating differs.
    private let readFromThisRoom: Bool
    private let answersReplies: Binding<Bool>
    private let onRereadNickname: () async -> Void
    @State private var isRereading = false

    init(
        signs: CallSigns,
        recentCalls: RecentCallReport?,
        issue: String?,
        readFromThisRoom: Bool,
        answersReplies: Binding<Bool>,
        onAdd: @escaping (String) -> Bool,
        onRemove: @escaping (String) -> Void,
        onRereadNickname: @escaping () async -> Void
    ) {
        self.signs = signs
        self.recentCalls = recentCalls
        self.issue = issue
        self.readFromThisRoom = readFromThisRoom
        self.answersReplies = answersReplies
        self.onAdd = onAdd
        self.onRemove = onRemove
        self.onRereadNickname = onRereadNickname
    }

    var body: some View {
        Section {
            // 계정 이름 either way. The label used to read 「내 이름 (이 방)」 whenever
            // the name had been read room-scoped, which had the screen claiming to
            // know a per-room name that appears in no row anywhere.
            LabeledContent("내 이름 (카카오톡 계정)") {
                HStack(spacing: 8) {
                    Text(signs.nickname ?? "아직 읽지 못했습니다")
                        .foregroundStyle(signs.nickname == nil ? .secondary : .primary)
                    Button("다시 읽기") {
                        isRereading = true
                        Task {
                            await onRereadNickname()
                            isRereading = false
                        }
                    }
                    .controlSize(.small)
                    .disabled(isRereading)
                    if isRereading {
                        ProgressView().controlSize(.small)
                    }
                }
            }
            SettingHelpRow("답장으로 부른 것도 인식", help: .answersReplies) {
                Toggle("답장으로 부른 것도 인식", isOn: answersReplies)
                    .labelsHidden()
            }
            LabeledContent("전역 키워드") {
                Text(signs.globalKeywords.isEmpty ? "없음" : signs.globalKeywords.joined(separator: ", "))
                    .foregroundStyle(signs.globalKeywords.isEmpty ? .secondary : .primary)
            }

            Text(nicknameExplanation)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Label(recentCallSummary, systemImage: recentCallIcon)
                .font(.footnote)
                .foregroundStyle(recentCallsFound ? Color.secondary : Color.orange)
        } header: {
            SettingHelpLabel("이 방이 답하는 말", help: .roomCallSigns)
        }

        Section {
            KeywordListEditor(
                keywords: signs.roomKeywords,
                emptyMessage: "이 방만의 키워드는 없습니다. 위의 말들로만 반응합니다.",
                issue: issue,
                onAdd: onAdd,
                onRemove: onRemove
            )

            Text("이 방에서만 쓰는 별명이나 팀 안에서만 통하는 말을 넣습니다. 내 이름과 전역 키워드는 그대로 두고 여기에 더합니다.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } header: {
            SettingHelpLabel("이 방에서만 쓸 키워드", help: .roomKeywords)
        }
    }

    /// Says where the name came from, and what to do when it is missing. An
    /// account that has not written yet leaves nothing to read the name off, and
    /// without this line that room looks broken rather than new.
    private var nicknameExplanation: String {
        guard let nickname = signs.nickname else {
            return "카카오톡에서 내 이름을 아직 읽지 못했습니다. 이 계정으로 아무 방에나 메시지를 한 번 보내고 동기화하면 이름을 인식합니다. 그전까지는 키워드로만 반응합니다."
        }
        let source = readFromThisRoom
            ? "이 방에서 내가 마지막으로 보낸 메시지"
            : "내가 마지막으로 보낸 메시지"
        return """
        \(source)에 적힌 이름이 "\(nickname)"입니다. "@"를 붙이든 안 붙이든, 뒤에 조사가 붙어도 반응합니다.

        이 방에서 내 이름을 따로 바꿔 두었다면 그 이름은 여기 나오지 않습니다. 카카오톡이 내가 보낸 메시지에는 계정 이름만 적기 때문입니다. 그 이름으로 부르는 것에도 답하려면 아래 "이 방에서만 쓸 키워드"에 넣으세요.

        계정 이름을 바꾸셨는데 위에 옛 이름이 보이면 "다시 읽기"를 누르세요. 바꾼 뒤 아직 아무 말도 하지 않았다면 새 이름이 어디에도 기록되지 않았으므로, 한 번 보내야 나타납니다.
        """
    }

    private var recentCallsFound: Bool {
        (recentCalls?.matchedMessages ?? 0) > 0
    }

    private var recentCallIcon: String {
        recentCallsFound ? "checkmark.circle" : "questionmark.circle"
    }

    /// The measurement the user could not make for themselves: of the messages
    /// this room would have judged, how many actually called.
    private var recentCallSummary: String {
        guard let recentCalls else { return "최근 대화를 확인하는 중입니다." }
        guard recentCalls.examinedMessages > 0 else {
            return "최근 메시지를 읽지 못했습니다. 동기화가 끝난 뒤 다시 확인해 주세요."
        }
        guard let latest = recentCalls.latest else {
            return "최근 메시지 \(recentCalls.examinedMessages)개 중 이 말들로 부른 메시지가 없습니다. \(signs.isEmpty ? "답할 말이 하나도 없어 " : "")멘션에만 응답인 방이면 계속 조용합니다."
        }
        return """
        최근 메시지 \(recentCalls.examinedMessages)개 중 \(recentCalls.matchedMessages)개가 불렀습니다. \
        마지막은 \(latest.senderName)님이 \"\(latest.sign)\"으로, \(Self.elapsed.localizedString(for: latest.at, relativeTo: Date()))입니다.
        """
    }

    private static let elapsed: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.unitsStyle = .full
        return formatter
    }()
}
