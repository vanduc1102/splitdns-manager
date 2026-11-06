import Testing

@testable import SplitDNSCore

struct DomainNameTests {
    @Test(arguments: [
        ("corp.example.com", "corp.example.com"),
        ("  Corp.Example.COM  ", "corp.example.com"),
        ("corp.example.com.", "corp.example.com"),
        ("test", "test"),
        ("10.in-addr.arpa", "10.in-addr.arpa"),
        ("_service.example.com", "_service.example.com"),
        ("xn--bcher-kva.example", "xn--bcher-kva.example"),
    ])
    func normalizesValidDomains(input: String, expected: String) throws {
        #expect(try DomainName(input).value == expected)
    }

    static let longLabel = String(repeating: "a", count: 64)
    static let longDomain = Array(repeating: String(repeating: "a", count: 60), count: 5).joined(separator: ".")

    static let invalidDomains: [(String, ResolverValidationError)] = [
        ("", .emptyDomain),
        ("   ", .emptyDomain),
        (".", .emptyDomain),
        ("*.example.com", .wildcardDomain),
        ("bücher.example", .nonASCIIDomain),
        ("a..example.com", .emptyLabel),
        (".example.com", .emptyLabel),
        ("../etc/passwd", .emptyLabel),
        ("-bad.example.com", .invalidLabel("-bad")),
        ("bad-.example.com", .invalidLabel("bad-")),
        ("ba d.example.com", .invalidLabel("ba d")),
        ("a/b.example.com", .invalidLabel("a/b")),
        ("example.com;reboot", .invalidLabel("com;reboot")),
        ("\(longLabel).com", .labelTooLong(longLabel)),
        (longDomain, .domainTooLong),
    ]

    @Test(arguments: invalidDomains)
    func rejectsInvalidDomains(input: String, expected: ResolverValidationError) {
        #expect(throws: expected) { try DomainName(input) }
    }
}
