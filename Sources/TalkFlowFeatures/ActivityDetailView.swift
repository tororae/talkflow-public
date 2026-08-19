import SwiftUI
import TalkFlowDomain

/// The right-hand pane of the 활동 화면. A draft still waiting on a person gets
/// the editor and the send buttons; everything else is a record to read.
struct ActivityDetailView: View {
    @Bindable private var model: ActivityTimelineModel

    init(model: ActivityTimelineModel) {
        self.model = model
    }

    var body: some View {
        Group {
            if let action = model.selectedAction {
                if model.isSelectedDraftPending {
                    review(action)
                } else {
                    record(action)
                }
            } else {
                ContentUnavailableView(
                    "항목을 선택하세요",
                    systemImage: "list.bullet.rectangle",
                    description: Text("촉발 메시지, 판단 결과, 생성된 답변을 볼 수 있습니다. 검토 대기 중인 초안은 여기서 바로 보낼 수 있습니다.")
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Laid out without a scroll view so the editor keeps the height it is
    /// given: a text box inside a scroll view fights the pointer for the
    /// gesture the moment the draft is longer than a line or two.
    private func review(_ action: AgentAction) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            header(action, subtitle: action.detail)
            // Bounded here because this pane does not scroll: an interval batch
            // would otherwise push the editor off the bottom of the window.
            answered(action, voice: .answering, maxHeight: 150)

            Text("보낼 내용").font(.headline)
            TextEditor(text: $model.editedText)
                .font(.body)
                .frame(minHeight: 140)
                .padding(6)
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary))
                .accessibilityLabel("보낼 내용")

            if !model.usePolicyAccepted {
                note("설정에서 전송 이용 정책에 동의해야 보낼 수 있습니다.", symbol: "exclamationmark.shield")
            }

            HStack {
                Button("무시") { Task { await model.dismissSelected() } }
                    .disabled(model.sendingID != nil)
                Spacer()
                if model.sendingID == action.id {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("전송 중")
                }
                Button(model.isEdited ? "수정해서 보내기" : "보내기") {
                    Task { await model.sendSelected() }
                }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(!model.usePolicyAccepted || model.sendingID != nil)
            }

            if let failure = model.actionFailure {
                note(failure, symbol: "exclamationmark.triangle")
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func record(_ action: AgentAction) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header(action, subtitle: nil)
                row("결과", ActivityKindStyle.title(for: action, isPending: false))
                row("시각", action.createdAt.formatted(date: .abbreviated, time: .standard))
                if let confidence = action.confidence {
                    row("확신도", confidence.title)
                }
                row("사용한 문맥", "최근 \(action.contextMessageCount)개 메시지")
                row("설명", action.detail)

                // Above the conversation rather than below it. A run of twenty
                // messages would push this off the bottom of the pane, and it is
                // the thing somebody who came here about a slow reply opened the
                // record to find.
                if let timing = model.selectedTimelineSection {
                    ActionTimelineBlock(section: timing)
                }

                // Not "이 대화에 답합니다" here: a 보류 answered nothing, and this
                // pane shows holds as often as it shows replies.
                answered(action, voice: .recorded, maxHeight: nil)

                if let replyText = action.replyText {
                    block("생성된 답변", body: Text(replyText), tint: .quaternary)
                }

                if let failure = model.actionFailure {
                    note(failure, symbol: "exclamationmark.triangle")
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The record layout lists 설명 as one of its rows, so it takes no subtitle
    /// and the same line is not printed twice.
    private func header(_ action: AgentAction, subtitle: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(action.chatRoomName.isEmpty ? action.chatRoomID : action.chatRoomName)
                    .font(.title2.bold())
                triggerBadge(action)
            }
            if let subtitle {
                Text(subtitle).foregroundStyle(.secondary)
            }
        }
    }

    /// A badge only for the two triggers a person was named by — 답장 and 멘션. No
    /// badge means the account joined a group conversation on its own (spontaneous),
    /// which is the 일반 호출 the user wanted told apart by its absence. The trigger
    /// is gathered from the group because a 전송 record does not keep it — the draft
    /// does.
    @ViewBuilder
    private func triggerBadge(_ action: AgentAction) -> some View {
        if let trigger = model.replyTrigger(for: action), let title = Self.badgeTitle(trigger) {
            Text(title)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Self.badgeTint(trigger).opacity(0.18), in: Capsule())
                .foregroundStyle(Self.badgeTint(trigger))
                .accessibilityLabel("촉발: \(title)")
        }
    }

    private static func badgeTitle(_ trigger: ReplyTrigger) -> String? {
        switch trigger {
        case .mention: "멘션"
        case .directQuestion: "답장"
        case .spontaneous: nil
        }
    }

    private static func badgeTint(_ trigger: ReplyTrigger) -> Color {
        switch trigger {
        case .mention: .orange
        case .directQuestion: .blue
        case .spontaneous: .secondary
        }
    }

    /// A reply usually answers a run of messages rather than one, and the record
    /// carries that run. Rows written before it did fall back to their single
    /// trigger line, which is how they have always read.
    @ViewBuilder
    private func answered(
        _ action: AgentAction,
        voice: AnsweredRunSection.Voice,
        maxHeight: CGFloat?
    ) -> some View {
        if let section = model.answeredSection(for: action, voice: voice) {
            AnsweredRunBlock(section: section, maxHeight: maxHeight)
        }
    }

    private func block(_ title: String, body: Text, tint: some ShapeStyle) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            body
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(tint, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            Text(value)
        }
    }

    private func note(_ message: String, symbol: String) -> some View {
        Label(message, systemImage: symbol)
            .foregroundStyle(.orange)
            .font(.footnote)
    }
}
