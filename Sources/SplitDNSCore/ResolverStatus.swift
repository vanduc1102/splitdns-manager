import Foundation

/// How a resolver file compares with what macOS has actually loaded (`scutil --dns`).
public enum ResolverStatus: Equatable, Sendable {
    /// macOS routes the domain to the file's name servers.
    case active(isReachable: Bool)
    /// macOS has a resolver for the domain, but with different name servers.
    case mismatch(loadedNameservers: [String])
    case notLoaded
    /// The file has no usable name servers, or `scutil` could not be read.
    case unknown

    static func evaluate(_ entry: ResolverEntry, against system: [SystemResolver]?) -> ResolverStatus {
        guard let system, entry.readError == nil, !entry.nameservers.isEmpty else { return .unknown }

        let domain = SystemDNSParser.normalized(domain: entry.effectiveDomain)
        let matching = system.filter { $0.domain == domain }
        guard !matching.isEmpty else { return .notLoaded }

        let expected = Set(entry.nameservers.map { $0.lowercased() })
        if let exact = matching.first(where: { Set($0.nameservers) == expected }) {
            return .active(isReachable: exact.isReachable ?? true)
        }
        return .mismatch(loadedNameservers: matching.flatMap(\.nameservers))
    }
}
