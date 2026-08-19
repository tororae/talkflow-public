import Foundation
import Testing
import TalkFlowApplication
import TalkFlowDomain
@testable import TalkFlowFeatures

@Test @MainActor
func editsWaitForTheSaveButtonInsteadOfReachingTheStore() async throws {
    let store = FakeSettingsStore(style: ResponseStyle(tone: "친근하고 간결하게"))
    let model = SettingsModel(settings: ManageAppSettings(store: store))
    await model.loadIfNeeded()

    model.update(\.tone, to: "정중하게")

    #expect(model.hasUnsavedChanges)
    #expect(model.canSave)
    #expect(try await store.responseStyle().tone == "친근하고 간결하게")

    await model.save()

    #expect(try await store.responseStyle().tone == "정중하게")
    #expect(model.hasUnsavedChanges == false)
    #expect(model.saveStatus == .saved)
    #expect(model.canSave == false)
}

/// Only failures used to show, so a save that worked looked like nothing had
/// happened at all.
@Test @MainActor
func aFailedSaveSaysSoAndKeepsTheEditedValues() async throws {
    let store = FakeSettingsStore(saveFailures: 1)
    let model = SettingsModel(settings: ManageAppSettings(store: store))
    await model.loadIfNeeded()
    model.update(\.tone, to: "정중하게")

    await model.save()

    #expect(model.saveStatus == .failed(FakeStoreError.unavailable.localizedDescription))
    #expect(model.draftStyle.tone == "정중하게")
    #expect(model.hasUnsavedChanges)
}

@Test @MainActor
func cancellingPutsBackTheLastSavedValues() async throws {
    let store = FakeSettingsStore(style: ResponseStyle(tone: "친근하고 간결하게", responseKeywords: ["달구봇"]))
    let model = SettingsModel(settings: ManageAppSettings(store: store))
    await model.loadIfNeeded()

    model.update(\.tone, to: "정중하게")
    model.addKeyword("한결")
    model.removeKeyword("달구봇")
    model.revert()

    #expect(model.draftStyle.tone == "친근하고 간결하게")
    #expect(model.draftStyle.responseKeywords == ["달구봇"])
    #expect(model.hasUnsavedChanges == false)
    #expect(try await store.responseStyle().responseKeywords == ["달구봇"])
}

@Test @MainActor
func severalKeywordsCanBeRegisteredOneAtATime() async {
    let model = SettingsModel(settings: ManageAppSettings(store: FakeSettingsStore()))
    await model.loadIfNeeded()

    #expect(model.addKeyword("달구봇"))
    #expect(model.addKeyword("한결"))

    #expect(model.draftStyle.responseKeywords == ["달구봇", "한결"])
    #expect(model.keywordIssue == nil)
}

@Test @MainActor
func blankAndRepeatedKeywordsAreRefusedWithAReason() async {
    let model = SettingsModel(settings: ManageAppSettings(store: FakeSettingsStore()))
    await model.loadIfNeeded()
    model.addKeyword("hangyeol")

    #expect(model.addKeyword("   ") == false)
    #expect(model.keywordIssue == "키워드를 입력해 주세요.")
    #expect(model.addKeyword("HANGYEOL") == false)
    #expect(model.keywordIssue == "이미 등록된 키워드입니다.")
    #expect(model.draftStyle.responseKeywords == ["hangyeol"])
}

/// `@` is how the keyword is typed in the room, not part of the name. Keeping it
/// would stop the same keyword from matching a plain call by name.
@Test @MainActor
func aKeywordTypedWithTheAtSignIsStoredWithoutIt() async {
    let model = SettingsModel(settings: ManageAppSettings(store: FakeSettingsStore()))
    await model.loadIfNeeded()

    model.addKeyword("@달구봇")

    #expect(model.draftStyle.responseKeywords == ["달구봇"])
}

@Test @MainActor
func removingOneKeywordLeavesTheRest() async {
    let model = SettingsModel(settings: ManageAppSettings(store: FakeSettingsStore()))
    await model.loadIfNeeded()
    model.addKeyword("달구봇")
    model.addKeyword("한결")

    model.removeKeyword("달구봇")

    #expect(model.draftStyle.responseKeywords == ["한결"])
}

/// A read that failed used to leave the defaults in place for good, and the next
/// save wrote those defaults over the settings the user actually had.
@Test @MainActor
func settingsThatFailedToLoadAreNeverSavedOverAndAreRetried() async throws {
    let stored = ResponseStyle(tone: "정중하게", responseKeywords: ["달구봇"])
    let store = FakeSettingsStore(style: stored, loadFailures: 1)
    let model = SettingsModel(settings: ManageAppSettings(store: store))

    await model.loadIfNeeded()
    model.update(\.tone, to: "장난스럽게")
    await model.save()

    #expect(model.hasLoaded == false)
    #expect(model.canSave == false)
    #expect(model.failure != nil)
    #expect(try await store.responseStyle() == stored)

    await model.loadIfNeeded()

    #expect(model.hasLoaded)
    #expect(model.draftStyle == stored)
}

/// Consent and the kill switch are read at send time. Drafting them would let
/// the screen claim sending is off while it is still on.
@Test @MainActor
func consentIsWrittenImmediatelyRatherThanWaitingForSave() async throws {
    let store = FakeSettingsStore()
    let model = SettingsModel(settings: ManageAppSettings(store: store))
    await model.loadIfNeeded()

    model.setSendUsePolicyAccepted(true)

    let written = try await eventually { try await store.sendUsePolicyAccepted() }

    #expect(model.sendUsePolicyAccepted)
    #expect(model.hasUnsavedChanges == false)
    #expect(written)
}

/// The model is read when a call goes out, so a value waiting for 저장 would let
/// the screen name one model while another kept answering. Written on pick, like
/// the consent switch and unlike the style fields.
@Test @MainActor
func pickingAModelIsWrittenImmediatelyRatherThanWaitingForSave() async throws {
    let store = FakeSettingsStore()
    let model = SettingsModel(settings: ManageAppSettings(store: store))
    await model.loadIfNeeded()

    #expect(model.aiModel == .codexDefault)

    model.setAIModel(.pinned(.named("gpt-5.6-terra")))

    #expect(model.aiModel == .pinned(.named("gpt-5.6-terra")))
    #expect(model.hasUnsavedChanges == false)
    #expect(
        try await eventually { try await store.aiModel() == .pinned(.named("gpt-5.6-terra")) }
    )
}

/// The stored choice has to be on the screen when it opens. A picker that loaded
/// as 선택 안 함 while a model was pinned would report the opposite of what is
/// being called.
@Test @MainActor
func theStoredModelIsOnTheScreenAsSoonAsItLoads() async {
    let store = FakeSettingsStore(model: .pinned(.named("gpt-5.5")))
    let model = SettingsModel(settings: ManageAppSettings(store: store))

    await model.loadIfNeeded()

    #expect(model.aiModel == .pinned(.named("gpt-5.5")))
    #expect(model.aiModelOptions.contains(AIModel.named("gpt-5.5")))
}

/// A pinned id can outlive the catalog. Without the extra row the picker would
/// show nothing selected while that model went on answering every message.
@Test @MainActor
func aModelMissingFromTheCatalogIsStillOfferedSoThePickerCanShowIt() async {
    let store = FakeSettingsStore(model: .pinned(.named("gpt-4o-retired")))
    let model = SettingsModel(settings: ManageAppSettings(store: store))

    await model.loadIfNeeded()

    #expect(model.aiModelOptions.count == AIModel.catalog.count + 1)
    #expect(model.aiModelOptions.last == AIModel.named("gpt-4o-retired"))
    #expect(model.aiModelOptions.contains { AIModelChoice.pinned($0) == model.aiModel })
}

/// Nothing extra when the choice is a known one, and nothing extra for 선택 안 함:
/// the default is its own row in the picker, not a member of the catalog.
@Test @MainActor
func theCatalogIsOfferedUnchangedWhenTheChoiceIsAKnownOneOrNone() async {
    let known = SettingsModel(
        settings: ManageAppSettings(store: FakeSettingsStore(model: .pinned(AIModel.catalog[0])))
    )
    await known.loadIfNeeded()
    #expect(known.aiModelOptions == AIModel.catalog)

    let none = SettingsModel(settings: ManageAppSettings(store: FakeSettingsStore()))
    await none.loadIfNeeded()
    #expect(none.aiModelOptions == AIModel.catalog)
}

// MARK: - Fixtures

/// The switches write in a task of their own, so a test has to give that task a
/// turn before it reads the result back.
///
/// Bounded by a deadline rather than by a count of yields. A hundred yields is
/// not a wait — it is a hundred chances that the scheduler happens to run the
/// other task, and under a loaded parallel suite it regularly does not: measured
/// 2026-08-19, this failed at 0.001s while the write was simply not scheduled
/// yet. Two seconds is not a threshold anybody measured; the answer arrives on
/// the first check when the machine is idle, and two seconds is only far enough
/// out that a busy machine is not called a failure.
private func eventually(_ condition: @Sendable () async throws -> Bool) async rethrows -> Bool {
    let deadline = ContinuousClock().now + .seconds(2)
    while ContinuousClock().now < deadline {
        if try await condition() { return true }
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(1))
    }
    return try await condition()
}

/// 답변 조건 is drafted beside the style and saved by the same button. Saving one
/// and dropping the other would let the screen show a condition that never
/// reached a prompt.
@Test @MainActor
func theAnsweringConditionIsDraftedAndSavedWithTheStyle() async throws {
    let store = FakeSettingsStore()
    let model = SettingsModel(settings: ManageAppSettings(store: store))
    await model.loadIfNeeded()

    model.updateCondition("일정 잡는 얘기 위주로. 잡담엔 끼지 마.")

    #expect(model.hasUnsavedChanges)
    #expect(try await store.answeringCondition().isEmpty)

    await model.save()

    #expect(try await store.answeringCondition().text == "일정 잡는 얘기 위주로. 잡담엔 끼지 마.")
    #expect(model.hasUnsavedChanges == false)
}

/// Refused rather than shortened. A field that rewrites itself while somebody is
/// typing is the bug this screen already shipped once with the keyword box, so
/// the overlong text stays put and 저장 is what stops working.
@Test @MainActor
func aConditionOverTheLimitBlocksTheSaveInsteadOfBeingCutShort() async throws {
    let store = FakeSettingsStore()
    let model = SettingsModel(settings: ManageAppSettings(store: store))
    await model.loadIfNeeded()
    let long = String(repeating: "가", count: AnsweringCondition.characterLimit + 1)

    model.updateCondition(long)

    #expect(model.conditionIssue != nil)
    #expect(model.canSave == false)
    #expect(model.draftCondition == long)

    await model.save()
    #expect(try await store.answeringCondition().isEmpty)

    model.updateCondition("급한 것만")
    #expect(model.conditionIssue == nil)
    #expect(model.canSave)
}
