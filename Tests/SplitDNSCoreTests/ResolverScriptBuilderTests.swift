import Foundation
import Testing

@testable import SplitDNSCore

struct ResolverScriptBuilderTests {
    private func makeConfiguration(
        _ domain: String = "corp.example.com",
        nameservers: [String] = ["10.0.0.53"],
        port: Int? = nil,
        extraLines: [String] = []
    ) throws -> ResolverConfiguration {
        try ResolverConfiguration(
            domain: DomainName(domain),
            nameservers: nameservers.map(NameserverAddress.init),
            port: port,
            extraLines: extraLines
        )
    }

    /// A builder that never touches `/etc/resolver` or the real DNS cache.
    private func makeBuilder(in directory: URL) -> ResolverScriptBuilder {
        ResolverScriptBuilder(directoryPath: directory.path, flushesDNSCache: false)
    }

    private func contents(of url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    private func fileType(at url: URL) throws -> FileAttributeType? {
        try FileManager.default.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType
    }

    // MARK: Script text

    @Test func saveScriptFlushesBestEffortAfterTheFileIsInPlace() throws {
        let script = try ResolverScriptBuilder().saveScript(for: makeConfiguration())

        #expect(script.contains(#"/bin/mv -f -- "$tmp" '/etc/resolver/corp.example.com'"#))
        #expect(
            script.hasSuffix(
                "/usr/bin/dscacheutil -flushcache || true\n/usr/bin/killall -HUP mDNSResponder || true"
            )
        )
    }

    @Test func scriptsLeaveTheDNSCacheAloneWhenFlushingIsDisabled() throws {
        let builder = ResolverScriptBuilder(directoryPath: "/tmp/resolver", flushesDNSCache: false)

        #expect(try !builder.saveScript(for: makeConfiguration()).contains("mDNSResponder"))
        #expect(try !builder.removeScript(fileName: "corp.example.com").contains("mDNSResponder"))
        #expect(!builder.flushScript().contains("mDNSResponder"))
    }

    @Test func explicitFlushFailsLoudlyWhileChangesOnlyFlushBestEffort() throws {
        let builder = ResolverScriptBuilder()

        let flush = builder.flushScript()
        #expect(flush == "set -eu\n/usr/bin/dscacheutil -flushcache\n/usr/bin/killall -HUP mDNSResponder")
        #expect(try builder.removeScript(fileName: "corp.example.com").hasSuffix("mDNSResponder || true"))
    }

    // MARK: Saving, run through a real shell

    @Test func writesTheExactFileWithReadableRightsAndNoLeftovers() async throws {
        try await withTemporaryDirectory { directory in
            let configuration = try makeConfiguration(
                nameservers: ["10.0.0.53", "10.0.0.54"],
                port: 5353,
                extraLines: ["# note"]
            )

            let result = try await runShell(makeBuilder(in: directory).saveScript(for: configuration))

            let file = directory.appendingPathComponent("corp.example.com")
            #expect(result.status == 0, "\(result.standardError)")
            #expect(try contents(of: file) == "nameserver 10.0.0.53\nnameserver 10.0.0.54\nport 5353\n# note\n")
            #expect(try posixPermissions(atPath: file.path) == 0o644)
            #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["corp.example.com"])
        }
    }

    @Test func replacesTheContentsOfAnExistingFile() async throws {
        try await withTemporaryDirectory { directory in
            let file = directory.appendingPathComponent("corp.example.com")
            try "nameserver 192.0.2.1\n".write(to: file, atomically: true, encoding: .utf8)

            let result = try await runShell(makeBuilder(in: directory).saveScript(for: makeConfiguration()))

            #expect(result.status == 0, "\(result.standardError)")
            #expect(try contents(of: file) == "nameserver 10.0.0.53\n")
        }
    }

    @Test func createsAMissingDirectory() async throws {
        try await withTemporaryDirectory { base in
            let directory = base.appendingPathComponent("nested/resolver", isDirectory: true)

            let result = try await runShell(makeBuilder(in: directory).saveScript(for: makeConfiguration()))

            #expect(result.status == 0, "\(result.standardError)")
            #expect(try contents(of: directory.appendingPathComponent("corp.example.com")) == "nameserver 10.0.0.53\n")
        }
    }

    @Test func quotesDirectoryNamesThatContainShellSyntax() async throws {
        try await withTemporaryDirectory { base in
            let directory = base.appendingPathComponent("it's a \"resolver\" $HOME `id` dir", isDirectory: true)

            let result = try await runShell(makeBuilder(in: directory).saveScript(for: makeConfiguration()))

            #expect(result.status == 0, "\(result.standardError)")
            #expect(try contents(of: directory.appendingPathComponent("corp.example.com")) == "nameserver 10.0.0.53\n")
        }
    }

    @Test func writesPreservedLinesWithoutInterpretingThem() async throws {
        try await withTemporaryDirectory { directory in
            let extraLines = ["# it's $HOME `id` $(id) \"quoted\" \\ back", "search_order 1"]
            let configuration = try makeConfiguration(extraLines: extraLines)

            let result = try await runShell(makeBuilder(in: directory).saveScript(for: configuration))

            #expect(result.status == 0, "\(result.standardError)")
            #expect(
                try contents(of: directory.appendingPathComponent("corp.example.com")) == configuration.fileContents)
        }
    }

    @Test func replacesASymbolicLinkInsteadOfWritingThroughIt() async throws {
        try await withTemporaryDirectory { base in
            let target = base.appendingPathComponent("managed-elsewhere")
            try "nameserver 192.0.2.1\n".write(to: target, atomically: true, encoding: .utf8)
            let directory = base.appendingPathComponent("resolver", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let link = directory.appendingPathComponent("corp.example.com")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

            let result = try await runShell(makeBuilder(in: directory).saveScript(for: makeConfiguration()))

            #expect(result.status == 0, "\(result.standardError)")
            #expect(try fileType(at: link) == .typeRegular)
            #expect(try contents(of: link) == "nameserver 10.0.0.53\n")
            #expect(try contents(of: target) == "nameserver 192.0.2.1\n")
        }
    }

    @Test(.enabled(if: geteuid() != 0, "root ignores directory permissions"))
    func keepsTheExistingFileWhenTheDirectoryIsNotWritable() async throws {
        try await withTemporaryDirectory { directory in
            let file = directory.appendingPathComponent("corp.example.com")
            try "nameserver 192.0.2.1\n".write(to: file, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directory.path)
            defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path) }

            let result = try await runShell(makeBuilder(in: directory).saveScript(for: makeConfiguration()))

            #expect(result.status != 0)
            #expect(try contents(of: file) == "nameserver 192.0.2.1\n")
        }
    }

    // MARK: Removing, run through a real shell

    @Test func removesTheFileAndToleratesItAlreadyBeingGone() async throws {
        try await withTemporaryDirectory { directory in
            let file = directory.appendingPathComponent("corp.example.com")
            try "nameserver 10.0.0.53\n".write(to: file, atomically: true, encoding: .utf8)
            let script = try makeBuilder(in: directory).removeScript(fileName: "corp.example.com")

            let first = try await runShell(script)
            let second = try await runShell(script)

            #expect(first.status == 0, "\(first.standardError)")
            #expect(second.status == 0, "\(second.standardError)")
            #expect(!FileManager.default.fileExists(atPath: file.path))
        }
    }

    @Test func removesASymbolicLinkWithoutTouchingItsTarget() async throws {
        try await withTemporaryDirectory { base in
            let target = base.appendingPathComponent("managed-elsewhere")
            try "nameserver 192.0.2.1\n".write(to: target, atomically: true, encoding: .utf8)
            let directory = base.appendingPathComponent("resolver", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let link = directory.appendingPathComponent("corp.example.com")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

            let script = try makeBuilder(in: directory).removeScript(fileName: "corp.example.com")
            let result = try await runShell(script)

            #expect(result.status == 0, "\(result.standardError)")
            #expect(throws: (any Error).self) { try FileManager.default.destinationOfSymbolicLink(atPath: link.path) }
            #expect(try contents(of: target) == "nameserver 192.0.2.1\n")
        }
    }

    @Test(arguments: ["", ".hidden", "..", "a/b", "../etc/passwd", "nul\u{0}byte"])
    func refusesToRemoveNamesThatCouldEscapeTheDirectory(name: String) {
        #expect(throws: ResolverValidationError.invalidFileName(name)) {
            try ResolverScriptBuilder().removeScript(fileName: name)
        }
    }
}
