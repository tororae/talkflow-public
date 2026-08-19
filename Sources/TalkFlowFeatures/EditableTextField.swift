import SwiftUI

/// A text field that owns its text while it is being edited.
///
/// A macOS `TextField` bound straight to observable state has its value written
/// back from outside on every keystroke. That ends the input method's
/// composition, so Hangul commits jamo by jamo (ㅊㅏ instead of 차), and any
/// character the state does not keep disappears as it is typed. Holding the text
/// locally and reporting changes outward leaves composition alone.
///
/// The outside value still wins when it changes on its own, which is how 취소 and
/// the first load reach the field.
struct EditableTextField: View {
    private let title: String
    private let value: String
    /// Vertical for the fields that hold more than a line — 채팅방 요약 is a short
    /// paragraph, and a single-line box makes correcting the middle of it a
    /// scrolling exercise.
    private let axis: Axis
    /// How tall the vertical field is allowed to grow. A paragraph like 채팅방 요약
    /// starts at three lines, while a short instruction like 말투 starts at one and
    /// grows only to three — enough to see the whole of it without a box that dwarfs
    /// what it usually holds. Ignored for the single-line horizontal field.
    private let lineLimit: ClosedRange<Int>
    private let onChange: (String) -> Void

    @State private var text: String

    init(
        _ title: String,
        value: String,
        axis: Axis = .horizontal,
        lineLimit: ClosedRange<Int> = 3...10,
        onChange: @escaping (String) -> Void
    ) {
        self.title = title
        self.value = value
        self.axis = axis
        self.lineLimit = lineLimit
        self.onChange = onChange
        _text = State(initialValue: value)
    }

    var body: some View {
        field
            .onChange(of: text) { _, typed in
                guard typed != value else { return }
                onChange(typed)
            }
            .onChange(of: value) { _, restored in
                guard restored != text else { return }
                text = restored
            }
    }

    /// Two branches rather than one field with an optional line limit, so the
    /// single-line case stays exactly the field it was before the paragraph case
    /// existed.
    @ViewBuilder
    private var field: some View {
        switch axis {
        case .vertical:
            TextField(title, text: $text, axis: .vertical)
                .lineLimit(lineLimit)
                .multilineTextAlignment(.leading)
                .textFieldStyle(.roundedBorder)
        case .horizontal:
            TextField(title, text: $text)
                .multilineTextAlignment(.leading)
                .textFieldStyle(.roundedBorder)
        }
    }
}
