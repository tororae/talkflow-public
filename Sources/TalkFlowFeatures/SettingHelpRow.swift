import SwiftUI

/// A form row that carries its own label, a `?`, and one control.
///
/// The button goes inside the label rather than at the end of the row so it reads
/// as belonging to the setting's name. It also stays outside whatever the caller
/// disables: a greyed-out control is exactly when somebody asks what it was for,
/// and `.disabled` reaches every child of the view it is put on. So the caller
/// disables the control it passes in, not the row.
struct SettingHelpRow<Control: View>: View {
    private let title: String
    private let key: SettingHelpKey
    private let control: Control

    init(_ title: String, help key: SettingHelpKey, @ViewBuilder control: () -> Control) {
        self.title = title
        self.key = key
        self.control = control()
    }

    var body: some View {
        LabeledContent {
            control
        } label: {
            SettingHelpLabel(title, help: key)
        }
    }
}

/// A setting's name with its `?` beside it, for the places that are not a row —
/// a section covering several controls at once, where the thing needing an
/// explanation is the section rather than any one line in it.
struct SettingHelpLabel: View {
    private let title: String
    private let key: SettingHelpKey

    init(_ title: String, help key: SettingHelpKey) {
        self.title = title
        self.key = key
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
            SettingHelpButton(key)
        }
    }
}
