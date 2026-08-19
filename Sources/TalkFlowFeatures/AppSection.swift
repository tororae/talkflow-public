import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case overview
    case chatRooms
    /// Under 채팅방 rather than at the end, because it is read against it: a room
    /// is where a conversation happens and a person is who TalkFlow met there, and
    /// the notes on this screen are written out of those rooms.
    case people
    case activity
    case settings

    var id: Self { self }

    var title: String {
        switch self {
        case .overview: "개요"
        case .chatRooms: "채팅방"
        case .people: "사람"
        case .activity: "활동"
        case .settings: "설정"
        }
    }

    var symbolName: String {
        switch self {
        case .overview: "house"
        case .chatRooms: "bubble.left.and.bubble.right"
        case .people: "person.2"
        case .activity: "clock"
        case .settings: "gearshape"
        }
    }
}
