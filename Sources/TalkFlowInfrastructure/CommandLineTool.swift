import Foundation

struct CommandLineTool {
    struct Result {
        let output: String
        let exitCode: Int32
    }

    let executableURL: URL

    /// Long enough for the slowest thing this runs — a model call, which is
    /// seconds — and short enough that a tool which has stopped answering does
    /// not take the caller with it.
    ///
    /// There was no limit at all, and that is not a theoretical gap: everything
    /// on the send path goes through here, and a katok run that never returned
    /// would hold a reply until the app was restarted. A send measured at a
    /// hundred and seventy-six seconds through this call is what put the number
    /// on it.
    static let defaultTimeout: TimeInterval = 120

    /// `input` is written to the tool's stdin rather than passed as an argument.
    /// Conversation text goes through here, and process arguments are visible to
    /// every process on the machine.
    func run(
        arguments: [String],
        input: String? = nil,
        environment: [String: String] = [:],
        timeout: TimeInterval = CommandLineTool.defaultTimeout
    ) -> Result? {
        let process = Process()
        let outputPipe = Pipe()

        process.executableURL = executableURL
        process.arguments = arguments
        if !environment.isEmpty {
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        }
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        let inputPipe = input.map { _ in Pipe() }
        if let inputPipe {
            process.standardInput = inputPipe
        }

        do {
            try process.run()
        } catch {
            return nil
        }

        // Written on its own thread so a tool that starts printing before it has
        // read all of stdin cannot deadlock against this process.
        if let input, let inputPipe {
            DispatchQueue.global().async {
                inputPipe.fileHandleForWriting.write(Data(input.utf8))
                try? inputPipe.fileHandleForWriting.close()
            }
        }

        // Killed from a timer rather than polled, because the read below is the
        // thing that would otherwise never return: terminating the process is
        // what closes the pipe and lets it finish. `SIGKILL` after `SIGTERM`
        // because a tool wedged in a syscall does not run its own handlers.
        let deadline = DispatchWorkItem { [weak process] in
            guard let process, process.isRunning else { return }
            process.terminate()
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)

        // Drained before waiting: a tool that fills the pipe buffer would block
        // forever if the buffer is only read after the process exits.
        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        deadline.cancel()

        let output = String(decoding: data, as: UTF8.self)
        return Result(output: output, exitCode: process.terminationStatus)
    }
}
