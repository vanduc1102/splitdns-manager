import Foundation
import Testing

@testable import SplitDNSCore

struct CommandRunnerTests {
    private let runner = ProcessCommandRunner()

    @Test func capturesOutputErrorAndExitStatus() async throws {
        let result = try await runner.run("/bin/sh", arguments: ["-c", "echo out; echo err >&2; exit 3"])

        #expect(result == CommandResult(status: 3, standardOutput: "out\n", standardError: "err\n"))
    }

    @Test func passesArgumentsWithoutShellInterpretation() async throws {
        let result = try await runner.run("/usr/bin/printf", arguments: ["%s|", "$HOME", "a b", "; id"])

        #expect(result.standardOutput == "$HOME|a b|; id|")
    }

    /// Stderr is filled first, so a runner that read stdout to the end before touching stderr would deadlock.
    @Test(.timeLimit(.minutes(1)))
    func drainsLargeOutputOnBothPipes() async throws {
        let size = 1_048_576
        let script = "/usr/bin/yes e | /usr/bin/head -c \(size) >&2; /usr/bin/yes o | /usr/bin/head -c \(size)"

        let result = try await runner.run("/bin/sh", arguments: ["-c", script])

        #expect(result.status == 0)
        #expect(result.standardOutput.utf8.count == size)
        #expect(result.standardError.utf8.count == size)
    }

    @Test(.timeLimit(.minutes(1)))
    func terminatesTheProcessWhenTheTaskIsCancelled() async throws {
        let runner = runner
        let task = Task { try await runner.run("/bin/sleep", arguments: ["60"]) }
        try await Task.sleep(for: .milliseconds(300))

        let start = ContinuousClock.now
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }

        #expect(ContinuousClock.now - start < .seconds(20))
    }

    @Test func throwsWhenTheExecutableDoesNotExist() async {
        await #expect(throws: (any Error).self) {
            try await runner.run("/nonexistent/splitdns-tool", arguments: [])
        }
    }
}
