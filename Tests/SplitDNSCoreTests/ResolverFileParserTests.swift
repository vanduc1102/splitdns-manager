import Testing

@testable import SplitDNSCore

struct ResolverFileParserTests {
    @Test func parsesNameserversAndPort() throws {
        let parsed = ResolverFileParser.parse("nameserver 10.0.0.53\nnameserver 2001:DB8::1\nport 5353\n")

        #expect(parsed.nameservers.map(\.value) == ["10.0.0.53", "2001:db8::1"])
        #expect(parsed.port == 5353)
        #expect(parsed.extraLines.isEmpty)
    }

    @Test func keepsEverythingElseInOrder() {
        let text = """
            # managed by ansible
            nameserver 10.0.0.53
            search_order 1

            ; another comment
            timeout 5
            options mdns
            """
        let parsed = ResolverFileParser.parse(text)

        #expect(parsed.nameservers.map(\.value) == ["10.0.0.53"])
        #expect(
            parsed.extraLines == [
                "# managed by ansible", "search_order 1", "; another comment", "timeout 5", "options mdns",
            ]
        )
    }

    @Test func handlesWindowsLineEndingsAndIndentation() {
        let parsed = ResolverFileParser.parse("  nameserver\t10.0.0.53  \r\nport 53\r\n")

        #expect(parsed.nameservers.map(\.value) == ["10.0.0.53"])
        #expect(parsed.port == 53)
    }

    @Test func keepsLinesItCannotInterpret() {
        let parsed = ResolverFileParser.parse(
            "nameserver dns.example.com\nnameserver\nnameserver 10.0.0.1 10.0.0.2\nport abc\nport 70000\nport 53\nport 54\n"
        )

        #expect(parsed.nameservers.isEmpty)
        #expect(parsed.port == 53)
        #expect(
            parsed.extraLines == [
                "nameserver dns.example.com", "nameserver", "nameserver 10.0.0.1 10.0.0.2", "port abc", "port 70000",
                "port 54",
            ]
        )
    }

    @Test func findsExplicitDomainOverride() {
        #expect(
            ResolverFileParser.parse("domain other.example\nnameserver 10.0.0.1\n").domainOverride == "other.example")
        #expect(ResolverFileParser.parse("nameserver 10.0.0.1\n").domainOverride == nil)
        #expect(ResolverFileParser.parse("domain\n").domainOverride == nil)
    }

    @Test func roundTripsRenderedConfigurations() throws {
        let configuration = try ResolverConfiguration(
            domain: DomainName("corp.example.com"),
            nameservers: [NameserverAddress("10.0.0.53"), NameserverAddress("fe80::1%en0")],
            port: 5353,
            extraLines: ["# note", "search_order 2"]
        )

        let parsed = ResolverFileParser.parse(configuration.fileContents)

        #expect(parsed.nameservers == configuration.nameservers)
        #expect(parsed.port == configuration.port)
        #expect(parsed.extraLines == configuration.extraLines)
    }
}
