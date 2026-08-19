import Foundation
import TalkFlowDomain

/// TalkFlow delegates account authentication to Codex CLI. It never reads,
/// stores, or transmits a user's Codex credentials itself.
public struct CodexCLIConnection: AIProviderConnection {
    private let executableURL: URL?

    public init(fileManager: FileManager = .default) {
        executableURL = Self.findExecutable(using: fileManager)
    }

    public func status() async -> AIConnectionStatus {
        guard let executableURL else {
            return .unavailable(reason: "Codex CLI를 찾을 수 없습니다.")
        }

        return await Task.detached {
            guard let result = CommandLineTool(executableURL: executableURL)
                .run(arguments: ["login", "status"])
            else {
                return .unavailable(reason: "Codex 연결 상태를 확인하지 못했습니다.")
            }
            return Self.status(from: result)
        }.value
    }

    public func beginLogin() async -> AIConnectionStatus {
        guard let executableURL else {
            return .unavailable(reason: "Codex CLI를 찾을 수 없습니다.")
        }

        return await Task.detached {
            _ = CommandLineTool(executableURL: executableURL)
                .run(arguments: ["login"], timeout: Self.loginTimeout)
            guard let result = CommandLineTool(executableURL: executableURL)
                .run(arguments: ["login", "status"])
            else {
                return .unavailable(reason: "Codex 로그인 결과를 확인하지 못했습니다.")
            }
            return Self.status(from: result)
        }.value
    }

    /// `codex logout` removes the stored credential and TalkFlow asks the CLI
    /// what is left rather than assuming it worked. A logout that failed and a
    /// logout that succeeded look identical from here otherwise, and the one
    /// thing the user must not be told wrongly is that their account is off this
    /// machine.
    ///
    /// The credential is `~/.codex/auth.json`, which belongs to Codex CLI and not
    /// to TalkFlow. Signing out here signs the user out of `codex` in their own
    /// terminal too. That is not a side effect worth hiding — it is what the word
    /// means — so the button that calls this says so before it does.
    public func signOut() async -> AIConnectionStatus {
        guard let executableURL else {
            return .unavailable(reason: "Codex CLI를 찾을 수 없습니다.")
        }

        return await Task.detached {
            let tool = CommandLineTool(executableURL: executableURL)
            guard tool.run(arguments: ["logout"]) != nil else {
                return .unavailable(reason: "Codex 연동을 해제하지 못했습니다.")
            }
            guard let result = tool.run(arguments: ["login", "status"]) else {
                return .unavailable(reason: "Codex 연동 해제 결과를 확인하지 못했습니다.")
            }
            return Self.status(from: result)
        }.value
    }

    /// A login is a person going to a browser, finding the account, and possibly
    /// a second factor. The shared 120초 ceiling is sized for a model call and
    /// would give up in the middle of that, leaving the CLI killed halfway
    /// through an authentication.
    private static let loginTimeout: TimeInterval = 300

    static func findExecutable(using fileManager: FileManager = .default) -> URL? {
        let home = fileManager.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(home)/.local/bin/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex"
        ]

        return candidates
            .map(URL.init(fileURLWithPath:))
            .first { fileManager.isExecutableFile(atPath: $0.path) }
    }

    private static func status(from result: CommandLineTool.Result) -> AIConnectionStatus {
        let output = result.output.lowercased()
        guard result.exitCode == 0 else { return .needsLogin }
        if output.contains("api key") { return .connected(method: .apiKey) }
        return .connected(method: .chatGPT)
    }
}
