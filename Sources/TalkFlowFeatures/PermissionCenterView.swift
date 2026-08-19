import SwiftUI

public struct PermissionCenterView: View {
    public init() {}

    public var body: some View {
        GroupBox("macOS 권한") {
            VStack(alignment: .leading, spacing: 10) {
                permissionRow(
                    title: "전체 디스크 접근",
                    detail: "카카오톡의 로컬 대화를 읽을 때 필요합니다.",
                    destination: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
                )
                Divider()
                permissionRow(
                    title: "접근성",
                    detail: "자동 전송을 켤 때만 필요합니다. 초안 생성만 사용할 경우에는 필요하지 않습니다.",
                    destination: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func permissionRow(title: String, detail: String, destination: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).fontWeight(.medium)
                Text(detail).foregroundStyle(.secondary)
            }
            Spacer()
            Link("설정 열기", destination: URL(string: destination)!)
        }
    }
}
