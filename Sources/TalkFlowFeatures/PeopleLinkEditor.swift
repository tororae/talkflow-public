import SwiftUI
import TalkFlowDomain

/// The addresses a person is known by, one row each.
///
/// They are edited apart from the prose because they are stored apart from it, and
/// they are stored apart because a model rewrites a URL with complete confidence —
/// a character changed, a plausible path invented. A row of its own is what lets
/// somebody fix one address without touching a sentence around it, and what lets
/// the reply prompt say these are exact values and not to be paraphrased.
///
/// New links are typed into the fields at the bottom and added, rather than a
/// blank row appearing to be filled in. `KeywordListEditor` already works this way
/// and for the same reason: a half-filled row is something 저장 has to refuse, and
/// a screen that answers 추가 with a complaint made the user press the button to
/// find out it was not allowed.
struct PeopleLinkEditor: View {
    private let entry: PersonEntry
    private let model: PeopleModel

    @State private var label = ""
    @State private var url = ""

    init(entry: PersonEntry, model: PeopleModel) {
        self.entry = entry
        self.model = model
    }

    private var links: [PersonLink] { model.draft(for: entry).links }

    var body: some View {
        if links.isEmpty {
            Text("담아 둔 주소가 없습니다.")
                .foregroundStyle(.secondary)
        } else {
            ForEach(Array(links.enumerated()), id: \.offset) { index, link in
                row(link, at: index)
            }
        }

        // No ceiling on what is kept. The cap that remains is on how many ride
        // along on a reply, and the count says so once there are more than that.
        VStack(alignment: .leading, spacing: 6) {
                HStack {
                    TextField("이름표", text: $label, prompt: Text("이름표"))
                        .settingsField()
                    TextField("주소", text: $url, prompt: Text("https://"))
                        .settingsField()
                        .onSubmit(add)
                    Button("추가", action: add)
                        .disabled(url.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            Text(links.count > PersonNote.linksPerReply
                 ? "\(links.count)개 · 답장에는 최근 \(PersonNote.linksPerReply)개만 실립니다"
                 : "\(links.count)개")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    /// Why this link is where it is in the list, said plainly. The order is by
    /// last mention and nothing on screen would otherwise explain it — a person
    /// looking at a list they did not sort deserves to know what sorted it.
    private func mentioned(_ link: PersonLink) -> String {
        guard let at = link.lastMentionedAt else { return "대화에서 아직 안 나옴" }
        return "마지막 언급 \(Self.day.string(from: at))"
    }

    private static let day: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "M월 d일"
        return formatter
    }()

    /// The address is a field and not a link to click. Nothing in this app opens
    /// what a model wrote down, and a row that opened a browser would be the one
    /// place it did.
    /// Every edit rebuilds the whole link, so every field it does not show has to
    /// be carried across by hand. It was not, and editing a label silently reset
    /// the link's 출처 to 모름 — a field the screen did not draw could not be
    /// missed when it vanished.
    private func edited(
        _ link: PersonLink,
        label: String? = nil,
        url: String? = nil,
        relation: PersonLink.Relation? = nil
    ) -> PersonLink {
        PersonLink(
            label: label ?? link.label,
            url: url ?? link.url,
            relation: relation ?? link.relation,
            lastMentionedAt: link.lastMentionedAt
        )
    }

    private func row(_ link: PersonLink, at index: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
        HStack {
            EditableTextField("이름표", value: link.label) { text in
                model.editLink(edited(link, label: text), at: index, for: entry)
            }
            .frame(width: 120)
            EditableTextField("주소", value: link.url) { text in
                model.editLink(edited(link, url: text), at: index, for: entry)
            }
            Button {
                model.removeLink(at: index, for: entry)
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("링크 \(link.label) 지우기")
            .help("이 링크를 지웁니다")
        }

        // 출처 is on screen because a reply says it out loud. Calling a
        // forwarded link 「형이 만든 그 앱」 credits somebody with a stranger's
        // work, and the model is told to write 모름 whenever the conversation
        // does not settle it — so this is the row that settles it.
        HStack(spacing: 8) {
            Picker("출처", selection: Binding(
                get: { link.relation },
                set: { model.editLink(edited(link, relation: $0), at: index, for: entry) }
            )) {
                ForEach(PersonLink.Relation.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .labelsHidden()
            .frame(width: 120)

            Text(mentioned(link))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        }
        // Keyed on the person and the position, so the fields are re-seeded when
        // another person is opened under them or a row above is removed. Without
        // it a deleted row leaves the row below holding the deleted one's text.
        .id("\(entry.id)-link-\(index)")
    }

    /// A refused link stays in the fields so the user can fix it rather than
    /// retype it.
    private func add() {
        guard model.addLink(label: label, url: url, for: entry) else { return }
        label = ""
        url = ""
    }
}
