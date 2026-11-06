import Testing

@testable import SplitDNSCore

struct NameserverAddressTests {
    @Test(arguments: [
        ("10.0.0.53", "10.0.0.53"),
        ("  1.1.1.1\n", "1.1.1.1"),
        ("2001:DB8::1", "2001:db8::1"),
        ("2001:0db8:0000:0000:0000:0000:0000:0001", "2001:db8::1"),
        ("::1", "::1"),
        ("fe80::1%en0", "fe80::1%en0"),
    ])
    func canonicalizesValidAddresses(input: String, expected: String) throws {
        #expect(try NameserverAddress(input).value == expected)
    }

    @Test(arguments: [
        "",
        "   ",
        "dns.example.com",
        "10.0.0",
        "10.0.0.256",
        "0x7f.1",
        "10.0.0.1 10.0.0.2",
        "1.1.1.1\n2.2.2.2",
        "1.1.1.1;reboot",
        "10.0.0.1%en0",
        "fe80::1%",
        ":::",
    ])
    func rejectsInvalidAddresses(input: String) {
        #expect(throws: ResolverValidationError.self) { try NameserverAddress(input) }
    }
}
