import Foundation

/// Problems found while validating the input for a resolver file.
public enum ResolverValidationError: LocalizedError, Equatable, Sendable {
    case emptyDomain
    case wildcardDomain
    case nonASCIIDomain
    case domainTooLong
    case emptyLabel
    case labelTooLong(String)
    case invalidLabel(String)
    case domainAlreadyExists(String)
    case invalidFileName(String)
    case noNameservers
    case tooManyNameservers
    case invalidNameserver(String)
    case duplicateNameserver(String)
    case invalidPort(String)
    case unsafeLine

    public var errorDescription: String? {
        switch self {
        case .emptyDomain:
            "Enter the domain to route, for example corp.example.com."
        case .wildcardDomain:
            "Wildcards are not needed: a resolver for example.com already covers all of its subdomains."
        case .nonASCIIDomain:
            "Domain names may only contain ASCII letters, digits, hyphens and underscores. "
                + "Use the punycode form (xn--…) for international domain names."
        case .domainTooLong:
            "A domain name can be at most \(DomainName.maximumLength) characters long."
        case .emptyLabel:
            "A domain name cannot contain empty parts such as a leading dot or two dots in a row."
        case .labelTooLong(let label):
            "“\(label)” is longer than \(DomainName.maximumLabelLength) characters."
        case .invalidLabel(let label):
            "“\(label)” is not a valid domain label. Use letters, digits, hyphens and underscores, "
                + "and do not start or end with a hyphen."
        case .domainAlreadyExists(let domain):
            "A resolver for \(domain) already exists. Edit it instead."
        case .invalidFileName(let name):
            "“\(name)” cannot be used as a resolver file name."
        case .noNameservers:
            "Add at least one name server."
        case .tooManyNameservers:
            "macOS uses at most \(ResolverConfiguration.maximumNameservers) name servers per domain."
        case .invalidNameserver(let text):
            "“\(text)” is not a valid IPv4 or IPv6 address."
        case .duplicateNameserver(let address):
            "The name server \(address) is listed more than once."
        case .invalidPort(let text):
            "“\(text)” is not a valid port. Enter a number from 1 to 65535."
        case .unsafeLine:
            "Preserved lines cannot contain line breaks or NUL characters."
        }
    }
}
