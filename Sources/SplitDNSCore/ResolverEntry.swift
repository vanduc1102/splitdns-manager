import Foundation

/// A file found in the resolver directory, whether or not this app can edit it.
public struct ResolverEntry: Identifiable, Hashable, Sendable {
    public enum Origin: Hashable, Sendable {
        case file
        case symlink(target: String)
        case other(description: String)
    }

    public let fileName: String
    public let path: String
    public let origin: Origin
    public let rawText: String
    public let readError: String?
    let parsed: ParsedResolverFile

    init(fileName: String, path: String, origin: Origin = .file, rawText: String = "", readError: String? = nil) {
        self.fileName = fileName
        self.path = path
        self.origin = origin
        self.rawText = rawText
        self.readError = readError
        self.parsed = ResolverFileParser.parse(rawText)
    }

    public var id: String { fileName }
    public var nameservers: [String] { parsed.nameservers.map(\.value) }
    public var port: Int? { parsed.port }
    public var extraLines: [String] { parsed.extraLines }

    /// The domain macOS matches queries against.
    public var effectiveDomain: String { parsed.domainOverride ?? fileName }

    public var isSymlink: Bool {
        if case .symlink = origin { return true }
        return false
    }

    public var isEditable: Bool { editBlockReason == nil }

    /// Why this file cannot be edited here, or `nil` if it can.
    public var editBlockReason: String? {
        switch origin {
        case .symlink(let target):
            return "This file is a symbolic link to \(target), so it is probably managed by another tool "
                + "such as nix-darwin. Change it at its source."
        case .other(let description):
            return "This is \(description), not a regular file."
        case .file:
            if let readError {
                return readError
            }
            guard (try? DomainName(fileName))?.value == fileName else {
                return "The file name is not a lowercase domain name, so it cannot be edited here."
            }
            return nil
        }
    }
}
