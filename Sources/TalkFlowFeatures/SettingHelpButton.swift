import SwiftUI

/// The `?` that sits beside a setting's name.
///
/// Quiet on purpose. The room editor alone has nine of these, and a badge that
/// announces itself nine times in one form is its own kind of unreadable — the
/// button only has to be findable at the moment somebody stops and wonders.
struct SettingHelpButton: View {
    private let help: SettingHelp

    @State private var isShowing = false

    init(_ key: SettingHelpKey) {
        help = SettingHelp(key)
    }

    var body: some View {
        Button {
            isShowing = true
        } label: {
            Image(systemName: "questionmark.circle")
                .imageScale(.medium)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("\(help.title) 설명")
        .help("이 설정이 무엇을 하는지 봅니다")
        .popover(isPresented: $isShowing) {
            SettingHelpCard(help: help)
        }
    }
}
