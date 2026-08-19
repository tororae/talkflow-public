import Foundation
import Testing
@testable import TalkFlowInfrastructure

/// Everything TalkFlow runs — the sync, the model call, every send — goes
/// through this one function, and it used to wait forever. A katok run that
/// stopped answering held the reply behind it until somebody restarted the app.
@Test
func aToolThatStopsAnsweringIsKilledRatherThanWaitedFor() async throws {
    let tool = CommandLineTool(executableURL: URL(fileURLWithPath: "/bin/sleep"))

    let started = Date()
    let result = await Task.detached { tool.run(arguments: ["30"], timeout: 1) }.value
    let elapsed = Date().timeIntervalSince(started)

    #expect(elapsed < 10)
    #expect(result?.exitCode != 0)
}

/// And a tool that answers inside its limit is untouched by any of it — the
/// timeout is a backstop, not a budget the normal path spends.
@Test
func aToolThatAnswersInTimeIsLeftAlone() async throws {
    let tool = CommandLineTool(executableURL: URL(fileURLWithPath: "/bin/echo"))

    let result = await Task.detached { tool.run(arguments: ["안녕"], timeout: 30) }.value

    #expect(result?.exitCode == 0)
    #expect(result?.output.trimmingCharacters(in: .whitespacesAndNewlines) == "안녕")
}

/// Output written to stdin comes back the same way it always did. The timer sits
/// beside the read rather than in front of it, so nothing about a normal run
/// changed.
@Test
func aToolStillReadsItsInputFromStandardInput() async throws {
    let tool = CommandLineTool(executableURL: URL(fileURLWithPath: "/bin/cat"))

    let result = await Task.detached { tool.run(arguments: [], input: "본문", timeout: 30) }.value

    #expect(result?.output == "본문")
}
