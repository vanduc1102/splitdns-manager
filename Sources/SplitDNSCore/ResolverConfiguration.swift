import Foundation

/// A validated resolver file: one domain routed to one to three name servers.
public struct ResolverConfiguration: Equatable, Sendable {
    public static let maximumNameservers = 3

    public let domain: DomainName
    public let nameservers: [NameserverAddress]
    public let port: Int?
    /// Lines of an existing file that this app does not model (comments, `search_order`, ...). They are kept as is.
    public let extraLines: [String]

    public init(
        domain: DomainName,
        nameservers: [NameserverAddress],
        port: Int? = nil,
        extraLines: [String] = []
    ) throws {
        guard !nameservers.isEmpty else { throw ResolverValidationError.noNameservers }
        guard nameservers.count <= Self.maximumNameservers else { throw ResolverValidationError.tooManyNameservers }
        var seen = Set<NameserverAddress>()
        for nameserver in nameservers where !seen.insert(nameserver).inserted {
            throw ResolverValidationError.duplicateNameserver(nameserver.value)
        }
        if let port, !ResolverFileParser.validPorts.contains(port) {
            throw ResolverValidationError.invalidPort(String(port))
        }
        guard extraLines.allSatisfy(Self.isSafe) else { throw ResolverValidationError.unsafeLine }

        self.domain = domain
        self.nameservers = nameservers
        self.port = port
        self.extraLines = extraLines
    }

    /// The lines of the resolver file, without line terminators.
    public var fileLines: [String] {
        nameservers.map { "nameserver \($0.value)" } + (port.map { ["port \($0)"] } ?? []) + extraLines
    }

    /// The exact text written to the resolver file.
    public var fileContents: String {
        fileLines.joined(separator: "\n") + "\n"
    }

    private static func isSafe(_ line: String) -> Bool {
        !line.contains(where: \.isNewline) && !line.unicodeScalars.contains("\u{0}")
    }
}
