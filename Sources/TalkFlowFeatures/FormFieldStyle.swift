import SwiftUI

/// How every editable field on a settings form is drawn.
///
/// Two problems, one cause. A `TextField`'s first argument is its *label*, not a
/// placeholder, and macOS forms render that label — so `TextField("100", …)`
/// inside a row already titled 「끼어들기 확률」 drew the number twice, once as
/// the field's own label and once as its contents. 「100 옆에 또 100」 with
/// nothing to say which was which.
///
/// And an unstyled field on macOS has no border, so a value sitting in one looks
/// exactly like a value printed on the row. A form where the editable things are
/// indistinguishable from the read-only things is a form nobody tries to edit.
///
/// Applied through one modifier rather than remembered at each call site, because
/// the last several fields added here each forgot a different half of it.
extension View {
    /// For a field whose row already carries the name. Hides the field's own
    /// label and gives it a border so it reads as somewhere to type.
    func settingsField(width: CGFloat? = nil, alignment: TextAlignment = .leading) -> some View {
        labelsHidden()
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(alignment)
            .frame(width: width)
    }

    /// For a number with a unit beside it. Right-aligned, because a column of
    /// numbers is read from the digits and the unit sits immediately after.
    func settingsNumberField(width: CGFloat = 64) -> some View {
        settingsField(width: width, alignment: .trailing)
    }
}
