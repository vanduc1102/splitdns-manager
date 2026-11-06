import Foundation
import Testing

@testable import SplitDNSCore

struct ShellQuotingTests {
    @Test func wrapsPlainTextInSingleQuotes() {
        #expect(ShellQuoting.quote("nameserver 10.0.0.53") == "'nameserver 10.0.0.53'")
        #expect(ShellQuoting.quote("") == "''")
    }

    @Test func escapesEmbeddedSingleQuotes() {
        #expect(ShellQuoting.quote("it's") == #"'it'\''s'"#)
    }

    /// The only real proof that quoting is right is asking an actual shell to undo it.
    @Test(arguments: [
        "plain",
        "with spaces  and\ttabs",
        "it's",
        "'",
        "''",
        "a'b'c",
        "$HOME",
        "`id`",
        "$(id)",
        #"back\slash"#,
        #""double""#,
        "; rm -rf /",
        "line1\nline2",
        "*",
        "-n",
        "~",
        "# not a comment",
        "ünïcödé ✓",
    ])
    func shellReadsQuotedValuesBackUnchanged(value: String) async throws {
        let result = try await runShell("/usr/bin/printf '%s' \(ShellQuoting.quote(value))")

        #expect(result.status == 0)
        #expect(result.standardOutput == value)
    }
}
