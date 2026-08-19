import Foundation
import Testing
@testable import TalkFlowInfrastructure

private final class FakeLid: LidStateReading, @unchecked Sendable {
    private let lock = NSLock()
    private var closed: Bool

    init(closed: Bool) {
        self.closed = closed
    }

    func isLidClosed() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return closed
    }

    func set(closed: Bool) {
        lock.lock()
        defer { lock.unlock() }
        self.closed = closed
    }
}

private final class FakeAssertions: PowerAssertionMaking, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var held: [UInt32: String] = [:]
    private var nextID: UInt32 = 1

    func hold(_ type: String, reason: String) -> UInt32? {
        lock.lock()
        defer { lock.unlock() }
        let id = nextID
        nextID += 1
        held[id] = type
        return id
    }

    func release(_ id: UInt32) {
        lock.lock()
        defer { lock.unlock() }
        held[id] = nil
    }

    var heldTypes: Set<String> {
        lock.lock()
        defer { lock.unlock() }
        return Set(held.values)
    }
}

private func makeController(lidClosed: Bool) -> (MacWakefulnessController, FakeLid, FakeAssertions) {
    let lid = FakeLid(closed: lidClosed)
    let assertions = FakeAssertions()
    return (
        MacWakefulnessController(lidState: lid, assertions: assertions, pollInterval: .seconds(3600)),
        lid,
        assertions
    )
}

@Test
func armingHoldsTheMacAwakeSoDetectionKeepsRunning() async {
    let (controller, _, assertions) = makeController(lidClosed: false)

    await controller.setArmed(true)

    #expect(await controller.holdsSystemAssertion)
    #expect(assertions.heldTypes.contains(kIOPMAssertionTypeNoIdleSleep))
}

/// The session locks about a second after the display sleeps, and a locked
/// session cannot be typed into. Behind a shut lid, holding the display awake
/// costs nothing visible and is what keeps delivery working.
@Test
func aShutLidAlsoHoldsTheDisplayAwake() async {
    let (controller, _, assertions) = makeController(lidClosed: true)

    await controller.setArmed(true)

    #expect(await controller.holdsDisplayAssertion)
    #expect(assertions.heldTypes.contains(kIOPMAssertionTypeNoDisplaySleep))
}

/// An open lid is a screen the user can see, so it must be allowed to sleep.
@Test
func anOpenLidLeavesTheDisplayAlone() async {
    let (controller, _, assertions) = makeController(lidClosed: false)

    await controller.setArmed(true)

    #expect(await controller.holdsDisplayAssertion == false)
    #expect(assertions.heldTypes.contains(kIOPMAssertionTypeNoDisplaySleep) == false)
}

@Test
func closingTheLidStartsHoldingTheDisplayAwake() async {
    let (controller, lid, _) = makeController(lidClosed: false)
    await controller.setArmed(true)

    lid.set(closed: true)
    await controller.matchDisplayHoldToLid()

    #expect(await controller.holdsDisplayAssertion)
}

@Test
func openingTheLidReleasesTheDisplayHoldImmediately() async {
    let (controller, lid, _) = makeController(lidClosed: true)
    await controller.setArmed(true)

    lid.set(closed: false)
    await controller.matchDisplayHoldToLid()

    #expect(await controller.holdsDisplayAssertion == false)
}

/// Turning auto-reply off has to let the Mac sleep again — a leaked assertion
/// would keep it running hot in a bag.
@Test
func disarmingReleasesEveryAssertion() async {
    let (controller, _, assertions) = makeController(lidClosed: true)
    await controller.setArmed(true)

    await controller.setArmed(false)

    #expect(await controller.holdsSystemAssertion == false)
    #expect(await controller.holdsDisplayAssertion == false)
    #expect(assertions.heldTypes.isEmpty)
}

@Test
func armingTwiceDoesNotStackAssertions() async {
    let (controller, _, assertions) = makeController(lidClosed: true)

    await controller.setArmed(true)
    await controller.setArmed(true)

    #expect(assertions.held.count == 2)
}
