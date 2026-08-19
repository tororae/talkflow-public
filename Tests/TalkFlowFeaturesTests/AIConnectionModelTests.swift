import Foundation
import Testing
import TalkFlowDomain
@testable import TalkFlowFeatures

/// Records what it was asked to do, in order, so a test can say what the model
/// did rather than only what it ended up showing. The difference matters most
/// for 다른 계정으로 로그인, which is correct only if both halves happened and
/// happened the right way round.
private actor FakeConnection: AIProviderConnection {
    enum Call: Equatable {
        case status
        case login
        case signOut
    }

    private(set) var calls: [Call] = []
    private let signOutResult: AIConnectionStatus
    private let loginResult: AIConnectionStatus
    /// A login that waits, so a test can ask what happens *during* one instead
    /// of racing to get a second call in before the first returns.
    private let holdsLogin: Bool
    private var held: CheckedContinuation<Void, Never>?

    init(
        signOutResult: AIConnectionStatus = .needsLogin,
        loginResult: AIConnectionStatus = .connected(method: .chatGPT),
        holdsLogin: Bool = false
    ) {
        self.signOutResult = signOutResult
        self.loginResult = loginResult
        self.holdsLogin = holdsLogin
    }

    func releaseLogin() {
        held?.resume()
        held = nil
    }

    func status() async -> AIConnectionStatus {
        calls.append(.status)
        return .connected(method: .chatGPT)
    }

    func beginLogin() async -> AIConnectionStatus {
        calls.append(.login)
        if holdsLogin {
            await withCheckedContinuation { held = $0 }
        }
        return loginResult
    }

    func signOut() async -> AIConnectionStatus {
        calls.append(.signOut)
        return signOutResult
    }
}

@Test @MainActor
func signingOutLeavesTheScreenAskingForALogin() async {
    let connection = FakeConnection()
    let model = AIConnectionModel(connection: connection)

    await model.disconnect()

    #expect(await connection.calls == [.signOut])
    #expect(model.status == .needsLogin)
    #expect(model.activity == nil)
}

/// `codex login` on a machine that still holds a credential has nothing to ask
/// about, so switching accounts is a sign-out followed by a login and not a
/// login on its own.
@Test @MainActor
func loggingInAsSomebodyElseHandsTheOldAccountBackFirst() async {
    let connection = FakeConnection()
    let model = AIConnectionModel(connection: connection)

    await model.reconnect()

    #expect(await connection.calls == [.signOut, .login])
    #expect(model.status == .connected(method: .chatGPT))
}

/// A login started against a credential that is still there returns the account
/// the user was trying to leave, and the screen would report success for the
/// opposite of what they asked.
@Test @MainActor
func aFailedSignOutStopsTheLoginRatherThanReportingTheOldAccountBack() async {
    let connection = FakeConnection(
        signOutResult: .unavailable(reason: "Codex 연동을 해제하지 못했습니다.")
    )
    let model = AIConnectionModel(connection: connection)

    await model.reconnect()

    #expect(await connection.calls == [.signOut])
    #expect(model.status == .unavailable(reason: "Codex 연동을 해제하지 못했습니다."))
}

/// Each of these takes the account out from under the others. A 연동 해제 that
/// began while a login was still waiting on a browser would leave the screen
/// showing whichever finished last.
///
/// The login is held open rather than raced against, so this asks what happens
/// during one instead of depending on which task the scheduler runs first.
@Test @MainActor
func aSecondActionIsRefusedWhileOneIsStillRunning() async {
    let connection = FakeConnection(holdsLogin: true)
    let model = AIConnectionModel(connection: connection)

    let login = Task { await model.connect() }
    while await connection.calls.contains(.login) == false { await Task.yield() }

    await model.disconnect()

    #expect(await connection.calls.contains(.signOut) == false)
    #expect(model.activity == .connecting)

    await connection.releaseLogin()
    await login.value

    #expect(model.activity == nil)
    #expect(model.status == .connected(method: .chatGPT))
}

@Test @MainActor
func theStatusIsUnknownUntilItHasBeenAsked() async {
    let model = AIConnectionModel(connection: FakeConnection())

    #expect(model.status == .checking)
    #expect(model.isBusy == false)

    await model.refresh()

    #expect(model.status == .connected(method: .chatGPT))
}
