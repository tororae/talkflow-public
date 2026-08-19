import Foundation

/// Keyword lists as one text column.
///
/// Both the global list and a room's own live in a single column rather than a
/// side table: they are read whole, written whole, and never joined against. A
/// row that fails to decode reads as no keywords instead of failing the load,
/// because losing a policy over a malformed list would silence a room the user
/// configured.
enum KeywordColumn {
    static func decode(_ raw: String?) -> [String] {
        guard let raw, let data = raw.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    static func encode(_ keywords: [String]) -> String {
        String(
            decoding: (try? JSONEncoder().encode(keywords)) ?? Data("[]".utf8),
            as: UTF8.self
        )
    }
}
