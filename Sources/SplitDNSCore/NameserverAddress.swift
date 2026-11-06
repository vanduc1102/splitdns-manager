import Foundation

/// A numeric IPv4 or IPv6 name server address in canonical form.
/// resolver(5) only accepts numeric addresses, so host names are rejected.
public struct NameserverAddress: Hashable, Sendable, CustomStringConvertible {
    public let value: String

    public var description: String { value }

    public init(_ input: String) throws {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let canonical = Self.canonicalForm(of: text) else {
            throw ResolverValidationError.invalidNameserver(text)
        }
        value = canonical
    }

    private static func canonicalForm(of text: String) -> String? {
        guard !text.isEmpty, text.unicodeScalars.allSatisfy(isAllowed) else { return nil }
        if let ipv4 = format(text, family: AF_INET) {
            return ipv4
        }

        // Link-local IPv6 addresses carry a zone, such as fe80::1%en0.
        let parts = text.split(separator: "%", maxSplits: 1, omittingEmptySubsequences: false)
        guard let ipv6 = format(String(parts[0]), family: AF_INET6) else { return nil }
        guard parts.count == 2 else { return ipv6 }
        let zone = String(parts[1])
        return zone.isEmpty ? nil : "\(ipv6)%\(zone)"
    }

    private static func isAllowed(_ scalar: Unicode.Scalar) -> Bool {
        scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar) || ".:%_-".unicodeScalars.contains(scalar))
    }

    private static func format(_ text: String, family: Int32) -> String? {
        var storage = in6_addr()
        guard inet_pton(family, text, &storage) == 1 else { return nil }
        var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
        guard inet_ntop(family, &storage, &buffer, socklen_t(buffer.count)) != nil else { return nil }
        return String(decoding: buffer.prefix { $0 != 0 }.map(UInt8.init(bitPattern:)), as: UTF8.self)
    }
}
