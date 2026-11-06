import Foundation
import Testing

@testable import SplitDNSCore

struct ResolverStoreTests {
    private func makeStore(
        in directory: URL,
        runner: any PrivilegedScriptRunning = RecordingPrivilegedRunner()
    ) -> ResolverStore {
        ResolverStore(
            privilegedRunner: runner,
            scriptBuilder: ResolverScriptBuilder(directoryPath: directory.path, flushesDNSCache: false)
        )
    }

    private func write(_ text: String, named name: String, in directory: URL) throws {
        try text.write(to: directory.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    private func makeConfiguration(extraLines: [String] = []) throws -> ResolverConfiguration {
        try ResolverConfiguration(
            domain: DomainName("corp.example.com"),
            nameservers: [NameserverAddress("10.0.0.53")],
            port: 5353,
            extraLines: extraLines
        )
    }

    /// Loads the directory and insists that it holds exactly one file.
    private func loadOnlyEntry(in directory: URL) async throws -> ResolverEntry {
        let entries = try await makeStore(in: directory).loadEntries()
        #expect(entries.count == 1)
        return try #require(entries.first)
    }

    // MARK: Loading

    @Test func aMissingDirectoryMeansNoResolvers() async throws {
        try await withTemporaryDirectory { directory in
            let store = makeStore(in: directory.appendingPathComponent("missing"))

            let entries = try await store.loadEntries()

            #expect(entries.isEmpty)
        }
    }

    @Test func aPathThatIsNotADirectoryIsAnError() async throws {
        try await withTemporaryDirectory { directory in
            try write("not a directory", named: "resolver", in: directory)
            let store = makeStore(in: directory.appendingPathComponent("resolver"))

            await #expect(throws: CommandError.self) { try await store.loadEntries() }
        }
    }

    @Test func listsFilesInNaturalOrderAndSkipsHiddenOnes() async throws {
        try await withTemporaryDirectory { directory in
            for name in ["a10.example", "a2.example", "B.example", ".DS_Store", ".splitdns.abc123"] {
                try write("nameserver 10.0.0.1\n", named: name, in: directory)
            }

            let entries = try await makeStore(in: directory).loadEntries()

            #expect(entries.map(\.fileName) == ["a2.example", "a10.example", "B.example"])
        }
    }

    @Test func readsNameserversPortAndUnknownLines() async throws {
        try await withTemporaryDirectory { directory in
            try write(
                "# hi\nnameserver 10.0.0.53\nport 5353\nsearch_order 1\n", named: "corp.example.com", in: directory)

            let entry = try await loadOnlyEntry(in: directory)

            #expect(entry.path == directory.appendingPathComponent("corp.example.com").path)
            #expect(entry.nameservers == ["10.0.0.53"])
            #expect(entry.port == 5353)
            #expect(entry.extraLines == ["# hi", "search_order 1"])
            #expect(entry.origin == .file)
            #expect(entry.isEditable)
        }
    }

    @Test func reportsSymbolicLinksWithTheirTargetAndMakesThemReadOnly() async throws {
        try await withTemporaryDirectory { base in
            let target = base.appendingPathComponent("managed-elsewhere")
            try "nameserver 192.0.2.1\n".write(to: target, atomically: true, encoding: .utf8)
            let directory = base.appendingPathComponent("resolver", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(
                at: directory.appendingPathComponent("corp.example.com"),
                withDestinationURL: target
            )

            let entry = try await loadOnlyEntry(in: directory)

            #expect(entry.origin == .symlink(target: target.path))
            #expect(entry.isSymlink)
            #expect(entry.nameservers == ["192.0.2.1"])
            #expect(!entry.isEditable)
        }
    }

    @Test func reportsABrokenSymbolicLinkAsUnreadable() async throws {
        try await withTemporaryDirectory { directory in
            try FileManager.default.createSymbolicLink(
                at: directory.appendingPathComponent("corp.example.com"),
                withDestinationURL: directory.appendingPathComponent("does-not-exist")
            )

            let entry = try await loadOnlyEntry(in: directory)

            #expect(entry.isSymlink)
            #expect(entry.readError != nil)
            #expect(entry.nameservers.isEmpty)
        }
    }

    @Test func reportsADirectoryAsNotARegularFile() async throws {
        try await withTemporaryDirectory { directory in
            try FileManager.default.createDirectory(
                at: directory.appendingPathComponent("corp.example.com"),
                withIntermediateDirectories: false
            )

            let entry = try await loadOnlyEntry(in: directory)

            #expect(entry.origin == .other(description: "a directory"))
            #expect(!entry.isEditable)
        }
    }

    @Test(arguments: [
        ("invalid UTF-8", Data([0x6E, 0xFF, 0xFE, 0x0A])),
        ("a NUL byte", Data("nameserver 10.0.0.1\n\u{0}".utf8)),
        ("more than 64 KB", Data(repeating: UInt8(ascii: "#"), count: ResolverStore.maximumFileSize + 1)),
    ])
    func flagsFilesThatAreNotResolverText(_ description: String, content: Data) async throws {
        try await withTemporaryDirectory { directory in
            try content.write(to: directory.appendingPathComponent("corp.example.com"))

            let entry = try await loadOnlyEntry(in: directory)

            #expect(entry.readError != nil, "\(description) should be flagged")
            #expect(!entry.isEditable)
        }
    }

    @Test func fileNamesThatAreNotLowercaseDomainsAreReadOnly() async throws {
        try await withTemporaryDirectory { directory in
            try write("nameserver 10.0.0.1\n", named: "Corp.Example.com", in: directory)

            let entry = try await loadOnlyEntry(in: directory)

            #expect(!entry.isEditable)
            #expect(entry.nameservers == ["10.0.0.1"])
        }
    }

    // MARK: Changing, with a recording runner

    @Test func savingRunsTheSaveScriptWithAClearPrompt() async throws {
        let runner = RecordingPrivilegedRunner()
        let directory = URL(fileURLWithPath: "/fake/resolver", isDirectory: true)
        let store = makeStore(in: directory, runner: runner)
        let configuration = try makeConfiguration(extraLines: ["# keep"])

        try await store.save(configuration)

        let expected = RecordingPrivilegedRunner.Call(
            script: store.scriptBuilder.saveScript(for: configuration),
            prompt: "SplitDNS Manager wants to save the DNS resolver for corp.example.com."
        )
        #expect(await runner.calls == [expected])
    }

    @Test func removingRunsTheRemoveScriptWithAClearPrompt() async throws {
        let runner = RecordingPrivilegedRunner()
        let directory = URL(fileURLWithPath: "/fake/resolver", isDirectory: true)
        let store = makeStore(in: directory, runner: runner)

        try await store.remove(fileName: "corp.example.com")

        let expected = RecordingPrivilegedRunner.Call(
            script: try store.scriptBuilder.removeScript(fileName: "corp.example.com"),
            prompt: "SplitDNS Manager wants to remove the DNS resolver for corp.example.com."
        )
        #expect(await runner.calls == [expected])
    }

    @Test func removingAnUnsafeNameNeverAsksForAPassword() async {
        let runner = RecordingPrivilegedRunner()
        let store = makeStore(in: URL(fileURLWithPath: "/fake/resolver"), runner: runner)

        await #expect(throws: ResolverValidationError.invalidFileName("../passwd")) {
            try await store.remove(fileName: "../passwd")
        }
        #expect(await runner.calls.isEmpty)
    }

    @Test func flushingRunsTheFlushScriptWithAClearPrompt() async throws {
        let runner = RecordingPrivilegedRunner()
        let store = ResolverStore(privilegedRunner: runner)

        try await store.flushDNSCache()

        let expected = RecordingPrivilegedRunner.Call(
            script: ResolverScriptBuilder().flushScript(),
            prompt: "SplitDNS Manager wants to flush the DNS cache."
        )
        #expect(await runner.calls == [expected])
    }

    @Test func passesRunnerFailuresThrough() async throws {
        let store = makeStore(
            in: URL(fileURLWithPath: "/fake/resolver"),
            runner: RecordingPrivilegedRunner(failure: PrivilegedExecutionError.cancelled)
        )

        await #expect(throws: PrivilegedExecutionError.cancelled) {
            try await store.save(makeConfiguration())
        }
    }

    @Test func usesTheSystemResolverDirectoryByDefault() {
        #expect(ResolverStore(privilegedRunner: RecordingPrivilegedRunner()).directoryPath == "/etc/resolver")
    }

    // MARK: End to end, through a real shell

    @Test func savesReloadsEditsAndRemovesThroughARealShell() async throws {
        try await withTemporaryDirectory { directory in
            let store = makeStore(in: directory, runner: ShellPrivilegedRunner())

            try await store.save(makeConfiguration(extraLines: ["# keep me"]))
            let saved = try await loadOnlyEntry(in: directory)
            #expect(saved.fileName == "corp.example.com")
            #expect(saved.nameservers == ["10.0.0.53"])
            #expect(saved.port == 5353)
            #expect(saved.extraLines == ["# keep me"])

            // Editing goes through a draft, which must carry the unrecognised lines along.
            let edited = try await MainActor.run {
                try ResolverDraft(editing: saved, existingDomains: ["corp.example.com"]).makeConfiguration()
            }
            try await store.save(edited)
            let resaved = try await loadOnlyEntry(in: directory)
            #expect(resaved.rawText == saved.rawText)

            try await store.remove(fileName: "corp.example.com")
            let remaining = try await store.loadEntries()
            #expect(remaining.isEmpty)
        }
    }
}
