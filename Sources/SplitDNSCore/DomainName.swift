import Foundation

/// A DNS domain a resolver file applies to. The file name inside `/etc/resolver` is the domain itself,
/// so a valid `DomainName` is also always a safe file name.
public struct DomainName: Hashable, Sendable, CustomStringConvertible {
    public static let maximumLength = 253
    public static let maximumLabelLength = 63

    public let value: String

    public var description: String { value }

    public init(_ input: String) throws {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasSuffix(".") {
            text.removeLast()
        }
        guard !text.isEmpty else { throw ResolverValidationError.emptyDomain }
        guard !text.contains("*") else { throw ResolverValidationError.wildcardDomain }
        guard text.unicodeScalars.allSatisfy(\.isASCII) else { throw ResolverValidationError.nonASCIIDomain }

        text = text.lowercased()
        guard text.count <= Self.maximumLength else { throw ResolverValidationError.domainTooLong }
        for label in text.split(separator: ".", omittingEmptySubsequences: false) {
            try Self.validate(label: String(label))
        }
        value = text
    }

    private static func validate(label: String) throws {
        guard !label.isEmpty else { throw ResolverValidationError.emptyLabel }
        guard label.count <= maximumLabelLength else { throw ResolverValidationError.labelTooLong(label) }
        guard !label.hasPrefix("-"), !label.hasSuffix("-"), label.unicodeScalars.allSatisfy(isAllowed) else {
            throw ResolverValidationError.invalidLabel(label)
        }
    }

    private static func isAllowed(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar {
        case "a"..."z", "0"..."9", "-", "_":
            true
        default:
            false
        }
    }
}
