import Foundation
import TalkFlowDomain

/// The run a reply answered, as one text column on the action.
///
/// A column rather than the side table the design draft called `action_contexts`:
/// the run is written once with the action, read whole with it, and never joined
/// against or updated — the timeline is append-only. A table keyed back to the
/// action would add a join to every read and a second place for one fact.
///
/// A row that fails to decode reads as no run at all, which is exactly how the
/// rows written before this existed read. The screen already falls back to the
/// trigger line for those, so a format that drifts loses detail rather than the
/// record.
enum AnsweredRunColumn {
    static func decode(_ raw: String?) -> AnsweredRun? {
        guard let raw, let data = raw.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(AnsweredRun.self, from: data)
    }

    /// Null for the rows that answer nothing — a hold, a dismissal — so the
    /// column means the same thing there as it does on the older rows.
    static func encode(_ run: AnsweredRun?) -> String? {
        guard let run, !run.lines.isEmpty, let data = try? JSONEncoder().encode(run) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
