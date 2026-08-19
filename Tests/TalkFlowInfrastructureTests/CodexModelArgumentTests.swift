import Foundation
import Testing
import TalkFlowDomain
@testable import TalkFlowInfrastructure

/// The 설정 picker is only real if the id reaches the process. Four settings on
/// this project have been landed through the domain and the schema and never onto
/// the command line, so the arguments themselves get a test.
private func makeWorkspace(modelID: String?) throws -> (CodexWorkspace, () -> Void) {
    let workspace = try CodexWorkspace(schema: "{}", modelID: modelID)
    return (workspace, workspace.destroy)
}

@Test
func aChosenModelIsPassedToCodexAsAFlagAndAValue() throws {
    let (workspace, cleanup) = try makeWorkspace(modelID: "gpt-5.6-terra")
    defer { cleanup() }

    let arguments = workspace.lockedDownArguments
    let flag = try #require(arguments.firstIndex(of: "--model"))

    #expect(arguments[flag + 1] == "gpt-5.6-terra")
}

/// 선택 안 함 has to mean *no flag*, not an empty one. `codex exec` takes an id it
/// has never heard of without complaining and fails only once the request is out,
/// so a blank value would break every reply rather than falling back.
@Test
func nothingChosenLeavesTheFlagOffEntirely() throws {
    let (workspace, cleanup) = try makeWorkspace(modelID: nil)
    defer { cleanup() }

    #expect(workspace.lockedDownArguments.contains("--model") == false)
}

/// The lockdown is the reason these arguments are shared, and a model choice must
/// not be able to displace any of it.
@Test
func choosingAModelKeepsEveryLockdownFlag() throws {
    let (chosen, cleanupChosen) = try makeWorkspace(modelID: "gpt-5.6-sol")
    defer { cleanupChosen() }
    let (plain, cleanupPlain) = try makeWorkspace(modelID: nil)
    defer { cleanupPlain() }

    for flag in ["--ephemeral", "--skip-git-repo-check", "--sandbox", "--output-schema"] {
        #expect(chosen.lockedDownArguments.contains(flag), "\(flag) went missing")
    }
    #expect(plain.lockedDownArguments.contains("--sandbox"))
    #expect(chosen.lockedDownArguments.count == plain.lockedDownArguments.count + 2)
}

/// `-` means "read the prompt from stdin", and `--image` takes a *list*: anything
/// after it that does not look like a flag is eaten as another file name. So `-`
/// is last, and adding `--model` must not have pushed anything past it.
@Test
func thePromptMarkerStaysTheLastArgument() throws {
    let (workspace, cleanup) = try makeWorkspace(modelID: "gpt-5.5")
    defer { cleanup() }

    #expect(workspace.lockedDownArguments.last == "-")
}
