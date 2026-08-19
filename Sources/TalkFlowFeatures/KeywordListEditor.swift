import SwiftUI

/// One row per keyword, added and removed one at a time.
///
/// It replaces a single comma-separated field. That field rebuilt its own text
/// from the parsed list on every keystroke, so the comma vanished on the very
/// keystroke that typed it and a second keyword was impossible to register.
///
/// Shared by the global list and a room's own, because the two lists differ only
/// in what they mean, not in how they are edited.
struct KeywordListEditor: View {
    private let keywords: [String]
    private let emptyMessage: String
    private let issue: String?
    private let onAdd: (String) -> Bool
    private let onRemove: (String) -> Void

    @State private var entry = ""

    init(
        keywords: [String],
        emptyMessage: String,
        issue: String?,
        onAdd: @escaping (String) -> Bool,
        onRemove: @escaping (String) -> Void
    ) {
        self.keywords = keywords
        self.emptyMessage = emptyMessage
        self.issue = issue
        self.onAdd = onAdd
        self.onRemove = onRemove
    }

    var body: some View {
        if keywords.isEmpty {
            Text(emptyMessage)
                .foregroundStyle(.secondary)
        } else {
            ForEach(keywords, id: \.self) { keyword in
                row(keyword)
            }
        }

        HStack {
            // Bordered so it reads as somewhere to type. Unstyled it looked
            // like one more line of text on a form full of them, and the one
            // control on the section that takes input was the one nobody found.
            TextField("추가할 키워드", text: $entry, prompt: Text("추가할 키워드"))
                .multilineTextAlignment(.leading)
                .settingsField()
                .onSubmit(add)
            Button("추가", action: add)
                .disabled(entry.trimmingCharacters(in: .whitespaces).isEmpty)
        }

        if let issue {
            Label(issue, systemImage: "exclamationmark.circle")
                .font(.footnote)
                .foregroundStyle(.orange)
        }
    }

    private func row(_ keyword: String) -> some View {
        HStack {
            Text(keyword)
            Spacer()
            Button {
                onRemove(keyword)
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("키워드 \(keyword) 지우기")
            .help("이 키워드를 지웁니다")
        }
    }

    /// A rejected keyword stays in the field so the user can fix it rather than
    /// retype it.
    private func add() {
        guard onAdd(entry) else { return }
        entry = ""
    }
}
