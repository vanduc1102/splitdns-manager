import Foundation
import Testing

@testable import SplitDNSCore

struct PrivilegedScriptRunnerTests {
    // MARK: Arguments

    @Test func passesTheScriptAndPromptAsArgumentsInsteadOfAppleScriptSource() {
        let script = #"echo "quoted"; rm -rf / # 'tricky'"#

        let arguments = OsascriptPrivilegedRunner.arguments(script: script, prompt: "Why?", elevated: true)

        #expect(
            arguments == [
                "-e", "on run argv",
                "-e", "do shell script (item 1 of argv) with prompt (item 2 of argv) with administrator privileges",
                "-e", "end run",
                "--", script, "Why?",
            ]
        )
    }

    @Test func onlyAsksForAdministratorPrivilegesWhenElevated() {
        let elevated = OsascriptPrivilegedRunner.arguments(script: "true", prompt: "p", elevated: true)
        let plain = OsascriptPrivilegedRunner.arguments(script: "true", prompt: "p", elevated: false)

        #expect(elevated.contains { $0.contains("with administrator privileges") })
        #expect(!plain.contains { $0.contains("administrator") })
    }

    /// The elevated variant is never run in tests (it would show a password dialog), so at least compile it.
    @Test func theElevatedAppleScriptCompiles() async throws {
        try await withTemporaryDirectory { directory in
            let arguments = OsascriptPrivilegedRunner.arguments(script: "true", prompt: "p", elevated: true)
            let sourceArguments = Array(arguments.prefix { $0 != "--" })
            let output = directory.appendingPathComponent("elevated.scpt").path

            let result = try await ProcessCommandRunner().run(
                "/usr/bin/osacompile",
                arguments: ["-o", output] + sourceArguments
            )

            #expect(result.status == 0, "\(result.standardError)")
        }
    }

    // MARK: Error mapping

    @Test(arguments: [
        ("7:45: execution error: User canceled. (-128)\n", PrivilegedExecutionError.cancelled),
        ("7:45: execution error: oops (2)\n", .failed("oops")),
        (
            "7:45: execution error: The command exited with a non-zero status. (3)\n",
            .failed("The command exited with a non-zero status.")
        ),
        ("7:45: execution error: line one\rline two (4)\n", .failed("line one\nline two")),
        ("execution error: no position (1)", .failed("no position")),
        ("something unexpected", .failed("something unexpected")),
        ("  \n", .failed("The administrator command failed.")),
    ])
    func mapsOsascriptErrors(standardError: String, expected: PrivilegedExecutionError) {
        #expect(OsascriptPrivilegedRunner.failure(fromStandardError: standardError) == expected)
    }

    // MARK: Running

    @Test func runsOsascriptWithTheBuiltArguments() async throws {
        let commands = FakeCommandRunner()
        let runner = OsascriptPrivilegedRunner(commandRunner: commands)

        try await runner.run(script: "true", prompt: "Because")

        let expected = FakeCommandRunner.Call(
            executable: "/usr/bin/osascript",
            arguments: OsascriptPrivilegedRunner.arguments(script: "true", prompt: "Because", elevated: true)
        )
        #expect(await commands.calls == [expected])
    }

    @Test func reportsACancelledPasswordDialogAsCancellation() async {
        let commands = FakeCommandRunner(status: 1, standardError: "0:17: execution error: User canceled. (-128)\n")
        let runner = OsascriptPrivilegedRunner(commandRunner: commands)

        await #expect(throws: PrivilegedExecutionError.cancelled) {
            try await runner.run(script: "true", prompt: "Because")
        }
    }

    @Test func reportsAFailedCommandWithItsMessage() async {
        let commands = FakeCommandRunner(status: 1, standardError: "0:17: execution error: Permission denied (1)\n")
        let runner = OsascriptPrivilegedRunner(commandRunner: commands)

        await #expect(throws: PrivilegedExecutionError.failed("Permission denied")) {
            try await runner.run(script: "true", prompt: "Because")
        }
    }

    @Test func propagatesFailuresToLaunchOsascript() async {
        let runner = OsascriptPrivilegedRunner(commandRunner: FakeCommandRunner(failure: CommandError.failed("boom")))

        await #expect(throws: CommandError.failed("boom")) {
            try await runner.run(script: "true", prompt: "Because")
        }
    }

    // MARK: Real osascript, without elevation

    @Test func runsMultiLineScriptsThroughTheRealOsascript() async throws {
        try await withTemporaryDirectory { directory in
            let output = directory.appendingPathComponent("it's here")
            let script = "set -eu\n/usr/bin/printf '%s\\n' one two > \(ShellQuoting.quote(output.path))"
            let runner = OsascriptPrivilegedRunner(requestsAdministratorPrivileges: false)

            try await runner.run(script: script, prompt: "unused")

            #expect(try String(contentsOf: output, encoding: .utf8) == "one\ntwo\n")
        }
    }

    @Test func surfacesTheScriptsOwnErrorFromTheRealOsascript() async {
        let runner = OsascriptPrivilegedRunner(requestsAdministratorPrivileges: false)

        await #expect(throws: PrivilegedExecutionError.failed("it broke")) {
            try await runner.run(script: "echo 'it broke' >&2; exit 5", prompt: "unused")
        }
    }
}
