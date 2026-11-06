import Foundation
import Testing

@testable import SplitDNSCore

// MARK: - File system helpers

func withTemporaryDirectory<T>(_ body: (URL) async throws -> T) async throws -> T {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("splitdns-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: url) }
    return try await body(url)
}

func runShell(_ script: String) async throws -> CommandResult {
    try await ProcessCommandRunner().run("/bin/sh", arguments: ["-c", script])
}

func posixPermissions(atPath path: String) throws -> Int {
    let attributes = try FileManager.default.attributesOfItem(atPath: path)
    return try #require(attributes[.posixPermissions] as? Int)
}

func entry(_ name: String, _ nameservers: String..., port: Int? = nil) -> ResolverEntry {
    var lines = nameservers.map { "nameserver \($0)" }
    if let port { lines.append("port \(port)") }
    return ResolverEntry(
        fileName: name,
        path: "/fake/resolver/\(name)",
        rawText: lines.joined(separator: "\n") + "\n"
    )
}

// MARK: - Test doubles

actor RecordingPrivilegedRunner: PrivilegedScriptRunning {
    struct Call: Equatable, Sendable {
        var script: String
        var prompt: String
    }

    private(set) var calls: [Call] = []
    private var failure: (any Error)?

    init(failure: (any Error)? = nil) {
        self.failure = failure
    }

    func run(script: String, prompt: String) async throws {
        calls.append(Call(script: script, prompt: prompt))
        if let failure { throw failure }
    }
}

/// Runs the script as the current user in `/bin/sh`, so tests can exercise real scripts against a temp directory.
struct ShellPrivilegedRunner: PrivilegedScriptRunning {
    func run(script: String, prompt: String) async throws {
        let result = try await runShell(script)
        guard result.status == 0 else {
            throw PrivilegedExecutionError.failed(result.standardError)
        }
    }
}

actor FakeCommandRunner: CommandRunning {
    struct Call: Equatable, Sendable {
        var executable: String
        var arguments: [String]
    }

    private(set) var calls: [Call] = []
    private let result: Result<CommandResult, any Error>

    init(status: Int32 = 0, standardOutput: String = "", standardError: String = "") {
        result = .success(CommandResult(status: status, standardOutput: standardOutput, standardError: standardError))
    }

    init(failure: any Error) {
        result = .failure(failure)
    }

    func run(_ executable: String, arguments: [String]) async throws -> CommandResult {
        calls.append(Call(executable: executable, arguments: arguments))
        return try result.get()
    }
}

actor FakeResolverStore: ResolverManaging {
    nonisolated let directoryPath = "/fake/resolver"

    private(set) var entries: [ResolverEntry]
    private(set) var savedConfigurations: [ResolverConfiguration] = []
    private(set) var removedFileNames: [String] = []
    private(set) var flushCount = 0
    private(set) var loadCount = 0
    private var loadFailure: (any Error)?
    private var changeFailure: (any Error)?
    private var holdsFlushes = false
    private var heldFlush: CheckedContinuation<Void, Never>?

    init(entries: [ResolverEntry] = []) {
        self.entries = entries
    }

    func failLoading(with error: (any Error)?) {
        loadFailure = error
    }

    func failChanges(with error: (any Error)?) {
        changeFailure = error
    }

    /// Makes the next flush suspend until `releaseHeldFlush()`, to observe the view model while it is busy.
    func holdFlushes() {
        holdsFlushes = true
    }

    var hasHeldFlush: Bool {
        heldFlush != nil
    }

    func releaseHeldFlush() {
        heldFlush?.resume()
        heldFlush = nil
    }

    func loadEntries() async throws -> [ResolverEntry] {
        loadCount += 1
        if let loadFailure { throw loadFailure }
        return entries
    }

    func save(_ configuration: ResolverConfiguration) async throws {
        if let changeFailure { throw changeFailure }
        savedConfigurations.append(configuration)
        let name = configuration.domain.value
        entries.removeAll { $0.fileName == name }
        entries.append(
            ResolverEntry(fileName: name, path: "/fake/resolver/\(name)", rawText: configuration.fileContents)
        )
        entries.sort { $0.fileName < $1.fileName }
    }

    func remove(fileName: String) async throws {
        if let changeFailure { throw changeFailure }
        removedFileNames.append(fileName)
        entries.removeAll { $0.fileName == fileName }
    }

    func flushDNSCache() async throws {
        if let changeFailure { throw changeFailure }
        if holdsFlushes {
            await withCheckedContinuation { heldFlush = $0 }
        }
        flushCount += 1
    }
}

actor FakeSystemDNSInspector: SystemDNSInspecting {
    private(set) var callCount = 0
    private var result: Result<[SystemResolver], any Error>

    init(resolvers: [SystemResolver] = []) {
        result = .success(resolvers)
    }

    func setResolvers(_ resolvers: [SystemResolver]) {
        result = .success(resolvers)
    }

    func fail(with error: any Error) {
        result = .failure(error)
    }

    func resolvers() async throws -> [SystemResolver] {
        callCount += 1
        return try result.get()
    }
}
