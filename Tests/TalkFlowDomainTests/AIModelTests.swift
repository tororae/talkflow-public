import Foundation
import Testing
import TalkFlowDomain

/// 선택 안 함 is a decision, not a missing value, and it has to survive the trip
/// through one nullable column and back.
@Test
func nothingChosenRoundTripsAsNoModelID() {
    #expect(AIModelChoice.codexDefault.modelID == nil)
    #expect(AIModelChoice(modelID: nil) == .codexDefault)
}

@Test
func aChosenModelRoundTripsThroughItsID() {
    for model in AIModel.catalog {
        let stored = AIModelChoice.pinned(model).modelID
        #expect(stored == model.id)
        #expect(AIModelChoice(modelID: stored) == .pinned(model))
    }
}

/// A column that once held an empty string — an older write, a hand-edited row —
/// would otherwise pass `--model ''` to the CLI and fail every single call.
@Test
func aBlankStoredValueReadsAsNothingChosen() {
    #expect(AIModelChoice(modelID: "") == .codexDefault)
    #expect(AIModelChoice(modelID: "   ") == .codexDefault)
}

/// An id can outlive the catalog: the provider retires a name, or the user moves
/// back to an older TalkFlow after picking something newer. Dropping it would
/// change which model answers without saying so, so it comes back naming itself
/// and the picker has something to select.
@Test
func anIDThatIsNoLongerInTheCatalogStillNamesItself() {
    let choice = AIModelChoice(modelID: "gpt-5.4")

    #expect(choice == .pinned(.named("gpt-5.4")))
    #expect(choice.modelID == "gpt-5.4")
    #expect(AIModel.named("gpt-5.4").name == "gpt-5.4")
    #expect(AIModel.named("gpt-5.4").summary.isEmpty == false)
}

/// Every entry is passed to `codex exec --model` as typed, and every one is drawn
/// in a picker. An id with whitespace would be a call that fails; a blank name
/// would be a row nobody can read.
@Test
func everyCatalogEntryIsUsableAsBothAFlagAndALabel() {
    #expect(AIModel.catalog.isEmpty == false)

    for model in AIModel.catalog {
        #expect(model.id == model.id.trimmingCharacters(in: .whitespacesAndNewlines))
        #expect(model.id.contains(" ") == false)
        #expect(model.name.isEmpty == false)
        #expect(model.summary.isEmpty == false)
        #expect(AIModel.named(model.id) == model)
    }
    #expect(Set(AIModel.catalog.map(\.id)).count == AIModel.catalog.count)
}
