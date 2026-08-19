import Foundation
import TalkFlowDomain

/// Where the time went, as one text column on the action.
///
/// The same shape as `AnsweredRunColumn` and for the same reasons: written once
/// with the action, read whole with it, never joined against or updated. A
/// per-stage table would add a join to every timeline read and give one fact two
/// homes.
///
/// A row that fails to decode reads as no timeline at all, which is how every
/// row written before this existed reads. The screen leaves the section out
/// rather than showing an empty one, so a format that drifts costs the durations
/// and nothing else on the record.
enum ActionTimelineColumn {
    static func decode(_ raw: String?) -> ActionTimeline {
        guard let raw, let data = raw.data(using: .utf8) else { return ActionTimeline() }
        return (try? decoder.decode(ActionTimeline.self, from: data)) ?? ActionTimeline()
    }

    /// Null for the rows nothing waited for, so the column means the same thing
    /// there as it does on the older rows.
    static func encode(_ timeline: ActionTimeline) -> String? {
        guard !timeline.isEmpty, let data = try? encoder.encode(timeline) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    /// ISO-8601 both ways rather than the JSON default of seconds-since-2001.
    /// These rows are read out of the database by hand when a delay needs
    /// explaining, and a bare float is unreadable there — the last investigation
    /// misread nine hours off a timestamp it could not see the shape of.
    ///
    /// **With fractional seconds.** Swift's `.iso8601` strategy writes whole
    /// seconds, which rounded every stamp in a stage to the same instant: a draft
    /// answered and queued in the same second recorded both at `:06.000`, and the
    /// pane then had nothing to order them by. Milliseconds are the resolution
    /// this record is about.
    private nonisolated(unsafe) static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    /// `nonisolated(unsafe)` for both: `ISO8601DateFormatter` is not `Sendable`,
    /// but these are configured once and only ever read. Formatting is the one
    /// thing `DateFormatter` documents as safe from several threads at once.
    private nonisolated(unsafe) static let whole = ISO8601DateFormatter()

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(fractional.string(from: date))
        }
        return encoder
    }()

    /// Reads both shapes. The rows written before this change carry whole
    /// seconds, and they have to keep reading as the times they are rather than
    /// as a decode failure that takes the whole timeline with it.
    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            guard let date = fractional.date(from: text) ?? whole.date(from: text) else {
                throw DecodingError.dataCorrupted(
                    .init(codingPath: decoder.codingPath, debugDescription: "시각을 읽지 못했습니다: \(text)")
                )
            }
            return date
        }
        return decoder
    }()
}
