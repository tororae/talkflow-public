import Foundation
import Observation
import TalkFlowApplication
import TalkFlowDomain

/// State for the settings screen.
///
/// The style is edited as a draft and only written when the user presses 저장.
/// Saving on every keystroke was the old behaviour and it made the fields
/// unusable: the model rewrote the text under the cursor, which erased
/// separators as they were typed and cut Hangul apart mid-composition.
///
/// The switches are deliberately not drafted. Consent and the wake permission
/// are read at send time, so a staged switch would let the screen claim sending
/// is off while it is still on.
@MainActor
@Observable
public final class SettingsModel {
    /// What the save bar reports. Kept apart from `failure`, which belongs to
    /// loading and to the switches that write themselves.
    public enum SaveStatus: Equatable, Sendable {
        case idle
        case saving
        case saved
        case failed(String)
    }

    public private(set) var savedStyle = ResponseStyle()
    public private(set) var draftStyle = ResponseStyle()
    /// Drafted as raw text rather than as a condition, so a value too long to
    /// keep can sit in the field with the reason beside it. A drafted
    /// `AnsweringCondition` would already have been trimmed to the limit and
    /// there would be nothing left to refuse.
    public private(set) var savedCondition = ""
    public private(set) var draftCondition = ""
    public private(set) var saveStatus: SaveStatus = .idle
    public private(set) var keywordIssue: String?
    public private(set) var conditionIssue: String?
    public private(set) var hasLoaded = false
    public private(set) var launchesAtLogin = false
    public private(set) var sendUsePolicyAccepted = false
    public private(set) var wakesDisplayToSend = true
    /// Not drafted, for the reason the switches are not: it is read at call time,
    /// so a staged value would have the screen name one model while another kept
    /// answering until 저장 was pressed.
    public private(set) var aiModel: AIModelChoice = .codexDefault
    public private(set) var failure: String?

    private let settings: ManageAppSettings
    private var isLoading = false

    public init(settings: ManageAppSettings) {
        self.settings = settings
    }

    public var hasUnsavedChanges: Bool {
        draftStyle != savedStyle || draftCondition != savedCondition
    }

    /// Saving before a load has succeeded would write defaults over whatever is
    /// on disk, so the button stays off until the stored values are in hand. A
    /// condition too long to keep blocks the save rather than being shortened on
    /// the way through, so what the user reads in the field is what is stored.
    public var canSave: Bool {
        hasLoaded && hasUnsavedChanges && saveStatus != .saving && conditionIssue == nil
    }

    /// The loaded flag is set only after every read succeeds. Setting it on
    /// entry meant one failed read left the defaults in place for good, and the
    /// next save wrote those defaults over the user's real settings.
    public func loadIfNeeded() async {
        guard !hasLoaded, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let style = try await settings.responseStyle()
            let condition = try await settings.answeringCondition()
            let launches = try await settings.launchesAtLogin()
            let accepted = try await settings.sendUsePolicyAccepted()
            let wakes = try await settings.wakesDisplayToSend()
            let model = try await settings.aiModel()

            savedStyle = style
            draftStyle = style
            savedCondition = condition.text
            draftCondition = condition.text
            launchesAtLogin = launches
            sendUsePolicyAccepted = accepted
            wakesDisplayToSend = wakes
            aiModel = model
            failure = nil
            hasLoaded = true
        } catch {
            failure = error.localizedDescription
        }
    }

    public func update<Value>(_ keyPath: WritableKeyPath<ResponseStyle, Value>, to value: Value) {
        draftStyle[keyPath: keyPath] = value
        markEdited()
    }

    /// Keeps whatever was typed and complains beside it. Shortening the text in
    /// place would rewrite the field under the cursor, which is the bug this
    /// screen already shipped once with the keyword box.
    public func updateCondition(_ text: String) {
        draftCondition = text
        conditionIssue = AnsweringCondition.exceedsLimit(text)
            ? "\(AnsweringCondition.characterLimit)자까지 적을 수 있습니다."
            : nil
        markEdited()
    }

    /// Keywords are a list, not one comma-separated field. The old field rebuilt
    /// its own text from the parsed list on every keystroke, so the separator
    /// disappeared as it was typed and a second keyword could never be entered.
    ///
    /// Returns false when the entry was rejected, so the field keeps what the
    /// user typed instead of silently dropping it.
    @discardableResult
    public func addKeyword(_ text: String) -> Bool {
        let keyword = CallSigns.normalized(text)
        guard !keyword.isEmpty else {
            keywordIssue = "키워드를 입력해 주세요."
            return false
        }
        guard !draftStyle.responseKeywords.contains(where: {
            $0.caseInsensitiveCompare(keyword) == .orderedSame
        }) else {
            keywordIssue = "이미 등록된 키워드입니다."
            return false
        }

        draftStyle.responseKeywords.append(keyword)
        keywordIssue = nil
        markEdited()
        return true
    }

    public func removeKeyword(_ keyword: String) {
        guard draftStyle.responseKeywords.contains(keyword) else { return }
        draftStyle.responseKeywords.removeAll { $0 == keyword }
        keywordIssue = nil
        markEdited()
    }

    public func save() async {
        guard canSave else { return }
        let style = draftStyle
        let condition = AnsweringCondition(draftCondition)
        saveStatus = .saving

        do {
            try await settings.save(style)
            try await settings.save(condition)
            savedStyle = style
            savedCondition = condition.text
            saveStatus = .saved
        } catch {
            saveStatus = .failed(error.localizedDescription)
        }
    }

    public func revert() {
        draftStyle = savedStyle
        draftCondition = savedCondition
        keywordIssue = nil
        conditionIssue = nil
        saveStatus = .idle
    }

    public func setLaunchesAtLogin(_ enabled: Bool) {
        launchesAtLogin = enabled
        Task {
            do {
                try await settings.setLaunchesAtLogin(enabled)
            } catch {
                failure = error.localizedDescription
            }
        }
    }

    /// Only the user can set this, and nothing is ever sent until they do.
    public func setSendUsePolicyAccepted(_ accepted: Bool) {
        sendUsePolicyAccepted = accepted
        Task {
            do {
                try await settings.setSendUsePolicyAccepted(accepted)
            } catch {
                failure = error.localizedDescription
            }
        }
    }

    public func setWakesDisplayToSend(_ enabled: Bool) {
        wakesDisplayToSend = enabled
        Task {
            do {
                try await settings.setWakesDisplayToSend(enabled)
            } catch {
                failure = error.localizedDescription
            }
        }
    }

    /// The options the picker draws: the catalog, plus whatever is stored if the
    /// stored id is not in it.
    ///
    /// The extra row is not decoration. A pinned id can outlive the list — the
    /// provider retires a name, or the user moves back to an older TalkFlow — and
    /// without it the picker would show nothing selected while that model went on
    /// answering every message.
    public var aiModelOptions: [AIModel] {
        guard case let .pinned(model) = aiModel,
              !AIModel.catalog.contains(where: { $0.id == model.id })
        else {
            return AIModel.catalog
        }
        return AIModel.catalog + [model]
    }

    public func setAIModel(_ choice: AIModelChoice) {
        aiModel = choice
        Task {
            do {
                try await settings.setAIModel(choice)
            } catch {
                failure = error.localizedDescription
            }
        }
    }

    /// A finished save stops being news the moment the draft moves again.
    private func markEdited() {
        if saveStatus != .saving { saveStatus = .idle }
    }
}
