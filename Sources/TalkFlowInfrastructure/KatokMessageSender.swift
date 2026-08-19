import Foundation
import TalkFlowDomain

/// Sends through katok's UI automation, the only write path KakaoTalk exposes.
///
/// `--accept-use-policy` is passed only because the user accepted the policy in
/// TalkFlow's own settings; the flag is never hard-coded on. Rooms are addressed
/// by `chat_id` rather than name, because names are not unique and a name-based
/// send can land in the wrong conversation.
public struct KatokMessageSender: MessageSender {
    private let executableURL: URL?
    private let environment: KatokEnvironment
    private let usePolicyAccepted: @Sendable () async -> Bool

    public init(
        fileManager: FileManager = .default,
        usePolicyAccepted: @escaping @Sendable () async -> Bool
    ) {
        self.init(
            executableURL: KatokConnection.findExecutable(using: fileManager),
            environment: KatokEnvironment(),
            usePolicyAccepted: usePolicyAccepted
        )
    }

    init(
        executableURL: URL?,
        environment: KatokEnvironment,
        usePolicyAccepted: @escaping @Sendable () async -> Bool
    ) {
        self.executableURL = executableURL
        self.environment = environment
        self.usePolicyAccepted = usePolicyAccepted
    }

    /// Focus is always taken at once, including with somebody in front of a
    /// screen.
    ///
    /// Waiting for a gap in typing was tried and was worse. katok refuses when
    /// the wait runs out, that refusal is retryable, and each retry brings
    /// KakaoTalk forward again — so being polite about one interruption produced
    /// three of them, spread over ten seconds. Measured on a clamshell desktop:
    /// the window came and went three times before a reply landed.
    ///
    /// One deliberate switch is less disruptive than three apologetic ones, and
    /// it is also faster, which is the point of a reply. Nobody is left without
    /// recourse: the stop hotkey is global and halts everything at once.
    ///
    /// This does not weaken the interlock that matters. Typing *into* somebody's
    /// keystream is refused before this path is ever reached — that refusal is
    /// `.keyboardInUse`, and it never hands the message on.
    ///
    /// **`--no-open` on anything the app decided by itself.**
    ///
    /// Opening a closed room is not a quiet operation. There is no known way to
    /// do it without taking the screen: the row is selected and then a **global**
    /// Return is posted, and on failure a global double-click — see
    /// `PLATFORM-FINDINGS.md` §3.6. Global events land wherever the focus happens
    /// to be, and when it is not where katok expected, the keystrokes meant to
    /// open a room are typed as text into whatever is in front. Observed: the
    /// room's own name appearing in a chat window, nothing sent, and KakaoTalk
    /// left showing a dialog.
    ///
    /// So automatic delivery refuses instead. A room whose window is closed keeps
    /// its draft queued rather than gambling with somebody's conversation, and
    /// the reply goes out when the window is open.
    ///
    /// A person pressing 보내기 gets the other answer. They are watching, they
    /// asked for this message now, and a window moving is what they expect.
    static func arguments(chatRoomID: String, origin: SendOrigin) -> [String] {
        var arguments = ["send", "--chat", chatRoomID, "--take-focus-now", "--accept-use-policy"]
        if origin == .automatic { arguments.append("--no-open") }
        return arguments
    }

    public func send(
        text: String,
        toChatRoomID chatRoomID: String,
        named chatRoomName: String,
        origin: SendOrigin
    ) async throws -> SendReceipt {
        guard let executableURL else {
            throw MessageSendFailure(message: "katok 실행 파일을 찾을 수 없습니다.", isRetryable: false)
        }
        guard await usePolicyAccepted() else {
            throw MessageSendFailure(message: "전송 이용 정책에 동의해야 전송할 수 있습니다.", isRetryable: false)
        }

        // The connector derives its database from a cached account id, so the
        // same override the reads use has to travel with the write. Without it a
        // send would leave from the account that was signed out.
        let katokEnvironment = environment.katokProcessEnvironment()

        // The same every time round now that the screen no longer changes the
        // answer, so it is built once rather than per attempt.
        let arguments = Self.arguments(chatRoomID: chatRoomID, origin: origin)

        var lastFailure: MessageSendFailure?
        for attempt in 0..<Self.attemptLimit {
            if attempt > 0 {
                try? await Task.sleep(for: Self.retryDelay)
            }

            let result = await Task.detached {
                // The message body goes over stdin, which katok reads when
                // `--text` is omitted, so it never appears in process arguments.
                CommandLineTool(executableURL: executableURL).run(
                    arguments: arguments,
                    input: text,
                    environment: katokEnvironment
                )
            }.value

            if let result, result.exitCode == 0 {
                return SendReceipt(route: .katok, attempts: attempt + 1)
            }

            let failure = Self.failure(from: result?.output)
            guard failure.isRetryable else { throw failure }
            lastFailure = failure
        }

        throw lastFailure ?? MessageSendFailure(message: "전송에 실패했습니다.", isRetryable: true)
    }

    /// Driving another app's UI fails at random: the window list comes back
    /// empty, or Return lands somewhere that ignores it. Running the same command
    /// again a moment later almost always works, and only failures katok reports
    /// as having delivered nothing are repeated, so a retry cannot double-send.
    ///
    /// Retrying here rather than leaving it to the queue is what makes the
    /// difference visible: the queue's next pass is ten seconds away and there is
    /// no next pass at all behind the 보내기 button.
    private static let attemptLimit = 3
    private static let retryDelay: Duration = .milliseconds(700)

    /// katok says so itself when nothing was delivered and the attempt can be
    /// repeated. Marking that terminal would drop a message the user asked to
    /// send. The whole output is searched rather than the shown summary, so a
    /// tool that prints its diagnosis above its last line is still understood.
    static func failure(from output: String?) -> MessageSendFailure {
        guard let output else {
            return MessageSendFailure(message: "전송을 실행하지 못했습니다.", isRetryable: true)
        }

        let lines = output
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let detail = lines.suffix(2).joined(separator: " ")

        return MessageSendFailure(
            message: "전송에 실패했습니다. \(detail)",
            isRetryable: retryableMarkers.contains { output.contains($0) },
            cause: roomClosedMarkers.contains { output.contains($0) } ? .roomWindowClosed : .unspecified
        )
    }

    /// katok reaches a room through KakaoTalk's own conversation list, which only
    /// exposes the rows it is drawing. A room whose window is closed is reported
    /// as missing from that list, and no number of retries changes it — the user
    /// has to open the conversation. Named here rather than left inside the
    /// retryable set because the two answers differ: this one still deserves a
    /// retry, and also deserves telling somebody about.
    private static let roomClosedMarkers = ["chat list", "is not open"]

    /// Every one of these describes the state of the screen at one moment, not
    /// anything wrong with the message: the lock screen holding the front, the
    /// window list coming back empty while KakaoTalk sits on another Space, or
    /// another window holding the keyboard so Return never reaches the room.
    ///
    /// `focus` used to cover katok giving up on a wait this no longer asks for.
    /// It stays because the word also appears when focus was taken and lost.
    private static let retryableMarkers = [
        "retry",
        "not frontmost",
        "is not open",
        "chat list",
        "did not accept",
        "input box",
        "focus"
    ]
}
