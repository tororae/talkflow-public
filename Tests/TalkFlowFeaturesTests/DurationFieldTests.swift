import Foundation
import Testing
@testable import TalkFlowFeatures

/// A stored duration comes back as the number a person would have typed. 300초
/// is 5분, not 300 of anything, and a preset list that could not say so was the
/// reason the control had to be a fixed list in the first place.
@Test
func aDurationReadsBackInTheLargestUnitItFillsCleanly() {
    #expect(DurationField.naturalUnit(for: 3600) == .hours)
    #expect(DurationField.naturalUnit(for: 300) == .minutes)
    #expect(DurationField.naturalUnit(for: 90) == .seconds)
}

/// Zero is not "0분". It is the absence of a limit, and saying it as a number
/// invites the reader to wonder what a zero-minute gap would mean.
@Test
func noLimitIsSaidInWordsRatherThanAsZero() {
    #expect(DurationField.title(for: 0) == "제한 없음")
    #expect(DurationField.title(for: 300) == "5분")
    #expect(DurationField.title(for: 7200) == "2시간")
}

/// The case the presets could not serve: seven minutes is not on anybody's list
/// and is a perfectly ordinary thing to want.
@Test
func aTypedValueOutsideThePresetsStillReadsBackAsItself() {
    #expect(DurationField.title(for: 420) == "7분")
    #expect(DurationField.naturalUnit(for: 420) == .minutes)
}
