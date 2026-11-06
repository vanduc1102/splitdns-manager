import Testing

@testable import SplitDNSCore

struct ResolverConfigurationTests {
    private func domain(_ text: String = "corp.example.com") throws -> DomainName {
        try DomainName(text)
    }

    private func addresses(_ texts: String...) throws -> [NameserverAddress] {
        try texts.map(NameserverAddress.init)
    }

    @Test func rendersNameserversThenPortThenPreservedLines() throws {
        let configuration = try ResolverConfiguration(
            domain: domain(),
            nameservers: addresses("10.0.0.53", "10.0.0.54"),
            port: 5353,
            extraLines: ["# managed by hand", "search_order 1"]
        )

        #expect(
            configuration.fileContents
                == "nameserver 10.0.0.53\nnameserver 10.0.0.54\nport 5353\n# managed by hand\nsearch_order 1\n"
        )
    }

    @Test func rendersMinimalFile() throws {
        let configuration = try ResolverConfiguration(domain: domain(), nameservers: addresses("10.0.0.53"))

        #expect(configuration.fileContents == "nameserver 10.0.0.53\n")
    }

    @Test func requiresAtLeastOneNameserver() throws {
        #expect(throws: ResolverValidationError.noNameservers) {
            try ResolverConfiguration(domain: domain(), nameservers: [])
        }
    }

    @Test func allowsAtMostThreeNameservers() throws {
        #expect(throws: ResolverValidationError.tooManyNameservers) {
            try ResolverConfiguration(
                domain: domain(),
                nameservers: addresses("10.0.0.1", "10.0.0.2", "10.0.0.3", "10.0.0.4")
            )
        }
    }

    @Test func rejectsDuplicateNameservers() throws {
        #expect(throws: ResolverValidationError.duplicateNameserver("10.0.0.1")) {
            try ResolverConfiguration(domain: domain(), nameservers: addresses("10.0.0.1", "10.0.0.1"))
        }
    }

    @Test(arguments: [0, -1, 65536])
    func rejectsPortsOutOfRange(port: Int) throws {
        #expect(throws: ResolverValidationError.invalidPort(String(port))) {
            try ResolverConfiguration(domain: domain(), nameservers: addresses("10.0.0.1"), port: port)
        }
    }

    @Test(arguments: ["first\nsecond", "carriage\rreturn", "nul\u{0}byte"])
    func rejectsPreservedLinesThatCouldInjectDirectives(line: String) throws {
        #expect(throws: ResolverValidationError.unsafeLine) {
            try ResolverConfiguration(domain: domain(), nameservers: addresses("10.0.0.1"), extraLines: [line])
        }
    }
}
