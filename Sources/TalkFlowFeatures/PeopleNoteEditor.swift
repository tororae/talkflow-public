import Foundation
import SwiftUI
import TalkFlowDomain

/// One person's note: what TalkFlow has written about them, where they are known
/// from, and the four things the user may do about it.
///
/// The screen exists before the convenience does. This note is a written
/// description of a real person that rides out to a model every time they speak;
/// one they cannot read is a claim the user never agreed to, one they cannot
/// correct is the app insisting on its own reading of somebody it has never met,
/// and one they cannot delete outlives the reason it was written.
///
/// 함께 있는 방 leads, above the note itself. The screen it sits on has a room
/// picker at the top, and a picker teaches people that what is below it belongs to
/// what is in it. This line is the correction: one note, N rooms, and changing the
/// picker changes which rows are easy to find and nothing else.
struct PeopleNoteEditor: View {
    private let entry: PersonEntry
    private let model: PeopleModel

    @State private var isConfirmingDelete = false

    init(entry: PersonEntry, model: PeopleModel) {
        self.entry = entry
        self.model = model
    }

    private var draft: PersonNoteDraft { model.draft(for: entry) }

    var body: some View {
        VStack(spacing: 0) {
            // Outside the scroll view, exactly as the room screen has it. A save
            // bar that scrolls away is one nobody finds when they need it, and this
            // one also carries the only report that a change took.
            PeopleSaveBar(
                status: model.saveStatus,
                issue: model.issue,
                hasUnsavedChanges: model.hasUnsavedChanges(entry),
                onSave: { Task { await model.save(for: entry) } },
                onCancel: { model.revert(entry) }
            )
            Divider()

            Form {
                Section("이 사람") {
                    identity
                }

                Section {
                    noteField
                    pinControl
                } header: {
                    SettingHelpLabel("사람 메모", help: .personNote)
                } footer: {
                    Text(provenance)
                }

                Section {
                    // Keyed on the person like the note field above, so the two
                    // fields that hold a link being typed are emptied when
                    // somebody else is opened under them. Half an address left
                    // over from the last person is the kind of thing that gets
                    // added to the wrong one.
                    PeopleLinkEditor(entry: entry, model: model)
                        .id(entry.id)
                } header: {
                    SettingHelpLabel("링크", help: .personLinks)
                }

                Section {
                    deleteControl
                } footer: {
                    Text("지우면 \(entry.room.displayName)에서 이 사람에 대해 적어 둔 글과 링크가 함께 사라집니다. 다른 방의 메모는 그대로 남고, 되돌릴 수 없습니다.")
                }
            }
            .formStyle(.grouped)
        }
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(entry.note.displayName)
                    .font(.title3.bold())
                // The same mark the list row carries, in the same place it means
                // the same thing: this name belongs to more than one person here.
                if let idTail = entry.idTail {
                    Text("…\(idTail)")
                        .font(.callout.monospaced())
                        .foregroundStyle(.secondary)
                        .help("같은 이름을 쓰는 사람이 또 있어 발신자 아이디 뒷자리를 함께 보여 줍니다")
                }
            }

            Label(entry.roomScopeLabel, systemImage: "bubble.left.and.bubble.right")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("메모는 방마다 따로입니다. 이 사람이 다른 방에도 있다면 그 방의 메모는 따로 있고, 여기서 고친 내용은 그 방에 옮겨가지 않습니다.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            // The key itself, and the only thing on this pane that identifies the
            // person without ambiguity. Selectable because the one time somebody
            // needs it — two people, one name, and a question about which is which
            // — they need to be able to copy it.
            Text(entry.note.senderID)
                .font(.footnote.monospaced())
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
                .help("카카오톡 발신자 아이디입니다. 이름이 아니라 이 값으로 사람을 가립니다.")
        }
    }

    private var noteField: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Keyed on the person so the text this field holds is put back when
            // somebody else is opened under it.
            EditableTextField(
                "이 사람에 대해 기억해 둘 내용",
                value: draft.note,
                axis: .vertical
            ) { text in
                model.editNote(text, for: entry)
            }
            .id(entry.id)

            // Counted as it is typed rather than only complained about at 저장.
            // The limit is a real one — this text rides out on every reply — and a
            // person writing a paragraph should see it coming.
            Text("\(draft.note.count)/\(PersonNote.characterLimit)자")
                .font(.footnote)
                .foregroundStyle(draft.note.count > PersonNote.characterLimit ? .orange : .secondary)
        }
    }

    /// When it was written, and both positions of 고정 out loud. The off state is
    /// the one that needs saying: a note about to be rewritten looks exactly like
    /// one that is not, until the sentence somebody typed is gone.
    private var provenance: String {
        let stamp = Self.stamp.string(from: entry.note.updatedAt)
        return entry.note.isPinned
            ? "\(stamp)에 마지막으로 저장했습니다. 고정해 두었으니 자동으로 덮어쓰지 않습니다."
            : "\(stamp)에 마지막으로 갱신했습니다. 고정하지 않았으니 이 사람이 다시 말하면 자동으로 다시 씁니다 — 직접 고친 문장도 함께 바뀝니다."
    }

    /// The switch that stops the refresh, and the only one.
    ///
    /// Correcting a sentence used to set the old `isUserEdited` flag, which made
    /// `savePeople` skip this person for good: nothing in the app cleared it, so
    /// fixing one name meant never learning another fact about them. Written
    /// immediately rather than on 저장, because the sweep may read it before
    /// anybody would have got around to pressing that.
    private var pinControl: some View {
        Toggle("이 메모 고정", isOn: Binding(
            get: { entry.note.isPinned },
            set: { on in Task { await model.setPinned(on, for: entry) } }
        ))
    }

    /// Asked before, not undone after. Nothing here can put the note back — the
    /// links go with it and the prose is not kept anywhere else — and the same
    /// dialog guards the one other irreversible thing in this app.
    private var deleteControl: some View {
        Button("이 사람 기억 지우기", role: .destructive) {
            isConfirmingDelete = true
        }
        .confirmationDialog(
            // The room is in the title because it is what is being deleted. Naming
            // the person alone would read as forgetting them everywhere, and this
            // dialog cannot be taken back after it is answered.
            "\(entry.room.displayName)에서의 \(entry.note.displayName) 님 메모를 지울까요?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("지우기", role: .destructive) {
                Task { await model.delete(entry) }
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text(
                """
                적어 둔 글과 링크 \(entry.note.links.count)개가 함께 사라집니다. 되돌릴 수 없습니다.
                다른 방의 이 사람 메모는 그대로 남습니다.
                이 방에서 사람 기억을 켜 두었다면, 대화가 다시 쌓인 뒤 새 메모가 만들어질 수 있습니다.
                """
            )
        }
    }

    private static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()
}
