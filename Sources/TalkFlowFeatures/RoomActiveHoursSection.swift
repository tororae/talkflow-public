import SwiftUI
import TalkFlowDomain

/// The 답변 활성화 시간 rows of a room's settings.
///
/// Its own file because of the conversion: the policy keeps a time of day as
/// minutes from midnight, while `DatePicker` will only work in `Date`.
struct RoomActiveHoursSection: View {
    private let title: String
    private let rowLabel: String
    private let hours: ReplyActiveHours
    private let onChange: (ReplyActiveHours) -> Void

    init(
        title: String = "답변 활성화 시간",
        rowLabel: String = "답변 시간",
        hours: ReplyActiveHours,
        onChange: @escaping (ReplyActiveHours) -> Void
    ) {
        self.title = title
        self.rowLabel = rowLabel
        self.hours = hours
        self.onChange = onChange
    }

    var body: some View {
        Section(title) {
            SettingHelpRow(rowLabel, help: .activeHours) {
                Picker(rowLabel, selection: limited) {
                    Text("항상").tag(false)
                    Text("정한 시간대에만").tag(true)
                }
                .labelsHidden()
            }
            // Left visible while off so the hours that would apply are readable
            // before the switch is flipped.
            DatePicker("시작", selection: time(\.startMinute), displayedComponents: .hourAndMinute)
                .disabled(!hours.isLimited)
            DatePicker("종료", selection: time(\.endMinute), displayedComponents: .hourAndMinute)
                .disabled(!hours.isLimited)
        }
    }

    private var limited: Binding<Bool> {
        Binding(
            get: { hours.isLimited },
            set: { newValue in
                var updated = hours
                updated.isLimited = newValue
                onChange(updated)
            }
        )
    }

    private func time(_ keyPath: WritableKeyPath<ReplyActiveHours, Int>) -> Binding<Date> {
        Binding(
            get: { Self.time(atMinute: hours[keyPath: keyPath]) },
            set: { newValue in
                var updated = hours
                updated[keyPath: keyPath] = Self.minute(of: newValue)
                onChange(updated)
            }
        )
    }

    /// The pickers show only an hour and a minute, so they need some day to hang
    /// off. Which day it is never reaches the policy.
    private static let referenceDay = Calendar.current.startOfDay(for: Date())

    private static func time(atMinute minute: Int) -> Date {
        Calendar.current.date(
            bySettingHour: minute / 60,
            minute: minute % 60,
            second: 0,
            of: referenceDay
        ) ?? referenceDay
    }

    private static func minute(of date: Date) -> Int {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}
