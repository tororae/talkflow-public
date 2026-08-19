import Foundation
import SwiftUI
import TalkFlowApplication
import TalkFlowDomain

/// 채팅방 요약 for one room: what TalkFlow currently believes about it, when it
/// decided that, and the four things the user may do about it.
///
/// The screen exists before the convenience does. This note is a written
/// description of the user's friends that rides in every reply; one they cannot
/// read is a claim they never agreed to, one they cannot correct is the app
/// insisting on its own reading of people it has never met, and one they cannot
/// delete outlives the reason it was written.
struct RoomConversationSummarySection: View {
    private let entry: ChatRoomPolicy
    private let model: RoomSummaryModel
    private let onChange: (RoomPolicy) -> Void

    init(
        entry: ChatRoomPolicy,
        model: RoomSummaryModel,
        onChange: @escaping (RoomPolicy) -> Void
    ) {
        self.entry = entry
        self.model = model
        self.onChange = onChange
    }

    var body: some View {
        Section {
            // The `?` sits on the section title. One card explains the whole
            // section, and a second button opening it would only teach the reader
            // that the first one was enough.
            Toggle("이 방의 대화 기억", isOn: remembers)

            if entry.policy.remembersConversation {
                editor
                controls
            }

            Text(note)
                .font(.footnote)
                .foregroundStyle(.secondary)
        } header: {
            SettingHelpLabel("대화 기억", help: .conversationSummary)
        }
    }

    @ViewBuilder
    private var editor: some View {
        if let summary = model.summary {
            // Keyed on the room so the text this field holds is put back when
            // another room is opened under it.
            EditableTextField(
                "이 방에 대해 기억해 둘 내용",
                value: summary.text,
                axis: .vertical
            ) { text in
                model.edit(text, in: entry.room)
            }
            .id(entry.id)
            // Beside the text it protects rather than among the buttons. It is a
            // statement about this note, and the sentence under it explains what
            // the two positions mean — a checkbox whose off state is unexplained
            // reads as "not done yet".
            Toggle("이 요약 고정", isOn: pinned(summary))
            Text(provenance(summary))
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else {
            Text(emptyNote)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }

        if let issue = model.issue {
            Label(issue, systemImage: "exclamationmark.circle")
                .font(.footnote)
                .foregroundStyle(.orange)
        }
    }

    private var controls: some View {
        HStack {
            // Off for a room that answers nobody, because the note below says the
            // room is not refreshed — a working button beside that sentence would
            // contradict it, and would spend a call on a room the user switched
            // off. 지우기 stays live either way: deleting a description of people
            // must never depend on a setting.
            Button("지금 갱신") {
                Task { await model.refresh(entry.room) }
            }
            .disabled(model.isRefreshing || !entry.policy.answersMessages)

            Button("지우기") {
                Task { await model.clear(entry.room) }
            }
            .disabled(model.summary == nil || model.isRefreshing)

            if model.isRefreshing {
                ProgressView().controlSize(.small)
            }
        }
    }

    /// A room with no note yet, which is where every room starts. It says what
    /// will produce one rather than only that there is none, because a room that
    /// never gets there — one switched off — looks identical from here.
    private var emptyNote: String {
        entry.policy.answersMessages
            ? "아직 이 방의 요약이 없습니다. 대화가 쌓이면 만들고, 지금 만들려면 \"지금 갱신\"을 누르세요."
            : "아직 이 방의 요약이 없습니다. 응답 모드가 \"\(entry.policy.responseMode.title)\"이라 만들지 않습니다."
    }

    /// When it was written and how much conversation is behind it — `DESIGN.md`
    /// §5.4 asks for both, and without them a sentence about somebody's friend
    /// reads as a standing fact rather than as one reading of one stretch of
    /// conversation.
    ///
    /// Both positions of 고정 are said out loud. The off state is the one that
    /// needs saying: a note that is quietly going to be rewritten looks exactly
    /// like one that is not, until the sentence somebody typed is gone.
    private func provenance(_ summary: ConversationSummary) -> String {
        let made = Self.stamp.string(from: summary.updatedAt)
        let base = "\(made) 기준 · 메시지 \(summary.coveredMessageCount)개를 반영했습니다."
        return summary.isPinned
            ? "\(base) 고정해 두었으니 자동으로 갱신하지 않습니다. \"지금 갱신\"도 이 요약은 건드리지 않습니다."
            : "\(base) 고정하지 않았으니 대화가 쌓이면 자동으로 다시 씁니다. 직접 고친 문장도 함께 바뀝니다."
    }

    /// The switch that stops the refresh, and the only one.
    ///
    /// Nothing else infers it. Saving an edit used to set the old `isUserEdited`
    /// flag and that flag stopped the sweep, so correcting one word froze the note
    /// — and a person note could never be unfrozen, because nothing cleared it.
    private func pinned(_ summary: ConversationSummary) -> Binding<Bool> {
        Binding(
            get: { summary.isPinned },
            set: { on in Task { await model.setPinned(on, in: entry.room) } }
        )
    }

    /// Turning it off deletes what is stored as well as stopping the refreshes. A
    /// room the user just told TalkFlow to forget should not keep a file about the
    /// people in it.
    private var remembers: Binding<Bool> {
        Binding(
            get: { entry.policy.remembersConversation },
            set: { on in
                var updated = entry.policy
                updated.remembersConversation = on
                onChange(updated)
                guard !on else { return }
                Task { await model.clear(entry.room) }
            }
        )
    }

    private var note: String {
        guard entry.policy.remembersConversation else {
            return "이 방의 요약을 만들지 않고, 저장해 둔 요약도 지웠습니다. 답장은 최근 대화만 보고 만듭니다."
        }
        guard entry.policy.answersMessages else {
            return "응답 모드가 \"\(entry.policy.responseMode.title)\"이라 요약을 갱신하지 않습니다."
        }
        return """
        이 요약은 이 방의 답장 요청마다 함께 나갑니다. \
        새 메시지 \(ConversationSummaryRefresh.messageThreshold)개가 쌓이거나 마지막 갱신에서 하루가 지나면 다시 만들고, \
        만들 때는 전체 대화가 아니라 지난 요약과 그 뒤의 대화만 읽습니다.
        """
    }

    private static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter
    }()
}
