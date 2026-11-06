import Testing

@testable import SplitDNSCore

struct SystemDNSTests {
    private static let sample = """
        DNS configuration

        resolver #1
          search domain[0] : lan
          nameserver[0] : 192.168.1.1
          if_index : 15 (en0)
          flags    : Request A records
          reach    : 0x00020002 (Reachable,Directly Reachable Address)

        resolver #2
          domain   : local
          options  : mdns
          timeout  : 5
          flags    : Request A records
          reach    : 0x00000000 (Not Reachable)
          order    : 300000

        resolver #3
          domain   : Corp.Example.com.
          nameserver[0] : 10.0.0.53
          nameserver[1] : FD00::53
          nameserver[2] : fe80::1%en0
          port     : 5353
          flags    : Request A records, Request AAAA records
          reach    : 0x00000002 (Reachable)
          order    : 100800

        resolver #4
          domain   : unflagged.example
          nameserver[0] : 10.9.9.9

        DNS configuration (for scoped queries)

        resolver #1
          domain   : scoped.example
          nameserver[0] : 192.168.1.1
          if_index : 15 (en0)
          reach    : 0x00020002 (Reachable,Directly Reachable Address)
        """

    @Test func parsesTheResolverBlocksOfTheDefaultConfiguration() {
        let resolvers = SystemDNSParser.parse(Self.sample)

        #expect(
            resolvers == [
                SystemResolver(domain: nil, nameservers: ["192.168.1.1"], port: nil, isReachable: true),
                SystemResolver(domain: "local", nameservers: [], port: nil, isReachable: false),
                SystemResolver(
                    domain: "corp.example.com",
                    nameservers: ["10.0.0.53", "fd00::53", "fe80::1%en0"],
                    port: 5353,
                    isReachable: true
                ),
                SystemResolver(domain: "unflagged.example", nameservers: ["10.9.9.9"], port: nil, isReachable: nil),
            ]
        )
    }

    @Test func ignoresTheScopedQueriesSection() {
        #expect(!SystemDNSParser.parse(Self.sample).contains { $0.domain == "scoped.example" })
    }

    @Test func returnsNothingForOutputWithoutResolvers() {
        #expect(SystemDNSParser.parse("").isEmpty)
        #expect(SystemDNSParser.parse("No DNS configuration available\n").isEmpty)
    }

    @Test func treatsMalformedReachabilityAsUnknown() {
        let resolvers = SystemDNSParser.parse("resolver #1\n  domain : a.example\n  reach : whatever\n")

        #expect(resolvers.first?.isReachable == nil)
    }

    @Test(arguments: [("Example.COM.", "example.com"), ("example.com", "example.com"), ("", "")])
    func normalizesDomains(input: String, expected: String) {
        #expect(SystemDNSParser.normalized(domain: input) == expected)
    }

    // MARK: Inspector

    @Test func inspectorRunsScutilAndParsesItsOutput() async throws {
        let commands = FakeCommandRunner(standardOutput: Self.sample)

        let resolvers = try await SystemDNSInspector(commandRunner: commands).resolvers()

        #expect(resolvers.count == 4)
        #expect(await commands.calls == [.init(executable: "/usr/sbin/scutil", arguments: ["--dns"])])
    }

    @Test func inspectorReportsAFailingScutil() async {
        let commands = FakeCommandRunner(status: 1, standardError: "scutil: boom\n")

        await #expect(throws: CommandError.failed("scutil: boom")) {
            try await SystemDNSInspector(commandRunner: commands).resolvers()
        }
    }

    @Test func inspectorCanReadTheRealSystemConfiguration() async throws {
        _ = try await SystemDNSInspector().resolvers()
    }
}
