import Foundation

/// Turns a value into a number in `0..<1` that is the same on every run.
///
/// Shared by the two rolls this app draws — how long one batching cycle waits,
/// and whether a room bothers to ask about a message nobody addressed to it —
/// because both need the same property for the same reason. Each is asked its
/// question more than once about the same subject: the pipeline re-reads a room
/// on every sync and again after 뒷말 대기, and an answer that changed between
/// two of those looks would let a cycle fire early or a message be taken after it
/// was already skipped.
///
/// Hashed by hand rather than through `Hasher`, which is seeded per process. With
/// it, relaunching the app would re-decide subjects it had already decided: a
/// room mid-cycle would jump forward or back, and a message already passed over
/// could come back with a different answer.
enum StableFraction {
    static func of(_ value: UInt64) -> Double {
        // 53 bits is every value a `Double` can hold exactly, so the fraction is
        // spread evenly instead of landing on a coarse grid.
        Double(mix(value) >> 11) / Double(1 << 53)
    }

    static func of(_ text: String) -> Double {
        of(fnv1a(text))
    }

    /// SplitMix64's finalizer. Cheap, and it scatters neighbouring inputs —
    /// which cycle starts and consecutive message ids both are — instead of
    /// returning neighbouring values.
    private static func mix(_ value: UInt64) -> UInt64 {
        var z = value &+ 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// FNV-1a over the bytes, only to get a string down to 64 bits. The mixing
    /// above is what the spread comes from; this just has to be stable across
    /// runs, which is exactly what `String.hashValue` is not.
    private static func fnv1a(_ text: String) -> UInt64 {
        text.utf8.reduce(UInt64(0xCBF2_9CE4_8422_2325)) { hash, byte in
            (hash ^ UInt64(byte)) &* 0x100_0000_01B3
        }
    }
}
