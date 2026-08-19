import Foundation
import IOKit.pwr_mgt
import TalkFlowDomain

/// Reads whether the built-in lid is shut.
protocol LidStateReading: Sendable {
    func isLidClosed() -> Bool
}

/// Creates and releases macOS power assertions. Injected so the lid-following
/// logic can be tested without holding real assertions on the test machine —
/// a leaked one would keep a Mac awake indefinitely.
protocol PowerAssertionMaking: Sendable {
    func hold(_ type: String, reason: String) -> UInt32?
    func release(_ id: UInt32)
}

struct IOKitLidState: LidStateReading {
    /// `AppleClamshellState` is the only reading that means "lid". Display sleep
    /// and the active-display count both look like a closed lid and are not.
    func isLidClosed() -> Bool {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IOPMrootDomain"),
            &iterator
        ) == KERN_SUCCESS else {
            return false
        }
        defer { IOObjectRelease(iterator) }

        let service = IOIteratorNext(iterator)
        guard service != 0 else { return false }
        defer { IOObjectRelease(service) }

        let value = IORegistryEntryCreateCFProperty(
            service,
            "AppleClamshellState" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue()
        return (value as? Bool) ?? false
    }
}

struct IOKitPowerAssertions: PowerAssertionMaking {
    func hold(_ type: String, reason: String) -> UInt32? {
        var id: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(
            type as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &id
        )
        return result == kIOReturnSuccess ? id : nil
    }

    func release(_ id: UInt32) {
        IOPMAssertionRelease(id)
    }
}

public actor MacWakefulnessController: WakefulnessController {
    // Deliberately ASCII: `pmset -g assertions` drops non-ASCII names, and an
    // unnamed assertion holding a Mac awake is miserable to track down.
    static let systemReason = "TalkFlow: watching for new KakaoTalk messages"
    static let displayReason = "TalkFlow: keeping the session unlocked to deliver queued replies"

    private let lidState: any LidStateReading
    private let assertions: any PowerAssertionMaking
    private let pollInterval: Duration

    private var armed = false
    private var systemAssertion: UInt32?
    private var displayAssertion: UInt32?
    private var watcher: Task<Void, Never>?

    public init() {
        self.init(lidState: IOKitLidState(), assertions: IOKitPowerAssertions())
    }

    init(
        lidState: any LidStateReading,
        assertions: any PowerAssertionMaking,
        pollInterval: Duration = .seconds(5)
    ) {
        self.lidState = lidState
        self.assertions = assertions
        self.pollInterval = pollInterval
    }

    var holdsSystemAssertion: Bool { systemAssertion != nil }
    var holdsDisplayAssertion: Bool { displayAssertion != nil }

    public func setArmed(_ armed: Bool) async {
        guard armed != self.armed else { return }
        self.armed = armed

        guard armed else {
            watcher?.cancel()
            watcher = nil
            release(&systemAssertion)
            release(&displayAssertion)
            return
        }

        systemAssertion = assertions.hold(kIOPMAssertionTypeNoIdleSleep, reason: Self.systemReason)
        matchDisplayHoldToLid()
        startWatchingLid()
    }

    /// The lid can open or shut at any time and there is no cheap notification
    /// for it, so the state is polled and the display hold follows it.
    private func startWatchingLid() {
        watcher?.cancel()
        watcher = Task { [pollInterval] in
            while !Task.isCancelled {
                try? await Task.sleep(for: pollInterval)
                guard !Task.isCancelled else { break }
                self.matchDisplayHoldToLid()
            }
        }
    }

    func matchDisplayHoldToLid() {
        guard armed else { return }
        let closed = lidState.isLidClosed()

        if closed, displayAssertion == nil {
            displayAssertion = assertions.hold(kIOPMAssertionTypeNoDisplaySleep, reason: Self.displayReason)
        } else if !closed, displayAssertion != nil {
            release(&displayAssertion)
        }
    }

    private func release(_ assertion: inout UInt32?) {
        guard let id = assertion else { return }
        assertions.release(id)
        assertion = nil
    }
}
