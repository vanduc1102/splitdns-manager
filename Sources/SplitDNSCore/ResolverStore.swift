import Foundation

protocol ResolverManaging: Sendable {
    var directoryPath: String { get }
    func loadEntries() async throws -> [ResolverEntry]
    func save(_ configuration: ResolverConfiguration) async throws
    func remove(fileName: String) async throws
    func flushDNSCache() async throws
}

/// Reads the resolver directory directly (it is world readable) and changes it through a privileged script.
struct ResolverStore: ResolverManaging {
    /// Real resolver files are a few lines long; anything bigger is not one.
    static let maximumFileSize = 64 * 1024

    var privilegedRunner: any PrivilegedScriptRunning
    var scriptBuilder = ResolverScriptBuilder()

    var directoryPath: String { scriptBuilder.directoryPath }

    func loadEntries() async throws -> [ResolverEntry] {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directoryPath, isDirectory: &isDirectory) else { return [] }
        guard isDirectory.boolValue else {
            throw CommandError.failed("\(directoryPath) exists but is not a directory.")
        }

        return try fileManager.contentsOfDirectory(atPath: directoryPath)
            .filter { !$0.hasPrefix(".") }
            .map(readEntry)
            .sorted { $0.fileName.localizedStandardCompare($1.fileName) == .orderedAscending }
    }

    func save(_ configuration: ResolverConfiguration) async throws {
        try await privilegedRunner.run(
            script: scriptBuilder.saveScript(for: configuration),
            prompt: "SplitDNS Manager wants to save the DNS resolver for \(configuration.domain.value)."
        )
    }

    func remove(fileName: String) async throws {
        try await privilegedRunner.run(
            script: scriptBuilder.removeScript(fileName: fileName),
            prompt: "SplitDNS Manager wants to remove the DNS resolver for \(fileName)."
        )
    }

    func flushDNSCache() async throws {
        try await privilegedRunner.run(
            script: scriptBuilder.flushScript(),
            prompt: "SplitDNS Manager wants to flush the DNS cache."
        )
    }

    private func readEntry(named fileName: String) -> ResolverEntry {
        let path = scriptBuilder.path(for: fileName)
        let fileManager = FileManager.default
        let type = (try? fileManager.attributesOfItem(atPath: path))?[.type] as? FileAttributeType ?? .typeRegular

        let origin: ResolverEntry.Origin
        switch type {
        case .typeSymbolicLink:
            let target = (try? fileManager.destinationOfSymbolicLink(atPath: path)) ?? "an unknown location"
            origin = .symlink(target: target)
        case .typeDirectory:
            origin = .other(description: "a directory")
        case .typeRegular:
            origin = .file
        default:
            origin = .other(description: "a special file")
        }
        if case .other = origin {
            return ResolverEntry(fileName: fileName, path: path, origin: origin)
        }

        switch readText(atPath: path) {
        case .success(let text):
            return ResolverEntry(fileName: fileName, path: path, origin: origin, rawText: text)
        case .failure(let error):
            return ResolverEntry(
                fileName: fileName,
                path: path,
                origin: origin,
                readError: error.localizedDescription
            )
        }
    }

    private func readText(atPath path: String) -> Result<String, any Error> {
        Result {
            let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
            defer { try? handle.close() }
            let data = try handle.read(upToCount: Self.maximumFileSize + 1) ?? Data()
            guard data.count <= Self.maximumFileSize else {
                throw CommandError.failed("The file is larger than \(Self.maximumFileSize / 1024) KB.")
            }
            guard let text = String(data: data, encoding: .utf8), !text.unicodeScalars.contains("\u{0}") else {
                throw CommandError.failed("The file is not valid UTF-8 text.")
            }
            return text
        }
    }
}
