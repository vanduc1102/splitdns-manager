import Foundation

enum PrivilegedExecutionError: LocalizedError, Equatable {
    case cancelled
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .cancelled:
            "The request was cancelled."
        case .failed(let message):
            message
        }
    }
}

protocol PrivilegedScriptRunning: Sendable {
    /// Runs a `/bin/sh` script as root. `prompt` explains the request in the system password dialog.
    func run(script: String, prompt: String) async throws
}

/// Elevates through AppleScript's `do shell script ... with administrator privileges`, which shows the standard
/// macOS password dialog. This needs no helper tool, no entitlements and no Developer ID signature.
struct OsascriptPrivilegedRunner: PrivilegedScriptRunning {
    static let executable = "/usr/bin/osascript"

    var commandRunner: any CommandRunning = ProcessCommandRunner()
    /// Tests turn this off so the script runs as the current user, without a password dialog.
    var requestsAdministratorPrivileges = true

    func run(script: String, prompt: String) async throws {
        let arguments = Self.arguments(
            script: script,
            prompt: prompt,
            elevated: requestsAdministratorPrivileges
        )
        let result = try await commandRunner.run(Self.executable, arguments: arguments)
        guard result.status == 0 else {
            throw Self.failure(fromStandardError: result.standardError)
        }
    }

    /// The script and prompt are passed as arguments to the AppleScript `run` handler, so they never have to be
    /// escaped into AppleScript source code.
    static func arguments(script: String, prompt: String, elevated: Bool) -> [String] {
        let command =
            elevated
            ? "do shell script (item 1 of argv) with prompt (item 2 of argv) with administrator privileges"
            : "do shell script (item 1 of argv)"
        return ["-e", "on run argv", "-e", command, "-e", "end run", "--", script, prompt]
    }

    /// `osascript` reports errors as `0:17: execution error: <message> (<number>)`; -128 means the user cancelled.
    static func failure(fromStandardError standardError: String) -> PrivilegedExecutionError {
        // AppleScript turns every line feed of the command's output into a carriage return.
        var message =
            standardError
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if message.contains("(-128)") {
            return .cancelled
        }
        if let prefix = message.range(of: #"^(\d+:\d+: )?(execution error: )?"#, options: .regularExpression) {
            message.removeSubrange(prefix)
        }
        if let suffix = message.range(of: #" \(-?\d+\)$"#, options: .regularExpression) {
            message.removeSubrange(suffix)
        }
        return .failed(message.isEmpty ? "The administrator command failed." : message)
    }
}
