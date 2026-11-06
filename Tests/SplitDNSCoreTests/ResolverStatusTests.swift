import Testing

@testable import SplitDNSCore

struct ResolverStatusTests {
    private func system(
        _ domain: String?,
        _ nameservers: String...,
        isReachable: Bool? = true
    ) -> SystemResolver {
        SystemResolver(domain: domain, nameservers: nameservers, port: nil, isReachable: isReachable)
    }

    private func status(of entry: ResolverEntry, in resolvers: [SystemResolver]?) -> ResolverStatus {
        ResolverStatus.evaluate(entry, against: resolvers)
    }

    @Test func isActiveWhenMacOSRoutesTheDomainToTheFilesNameservers() {
        let resolvers = [system("corp.example.com", "10.0.0.53")]

        #expect(status(of: entry("corp.example.com", "10.0.0.53"), in: resolvers) == .active(isReachable: true))
    }

    @Test func flagsAnActiveResolverThatIsNotReachable() {
        let resolvers = [system("corp.example.com", "10.0.0.53", isReachable: false)]

        #expect(status(of: entry("corp.example.com", "10.0.0.53"), in: resolvers) == .active(isReachable: false))
    }

    @Test func assumesReachableWhenScutilGaveNoFlags() {
        let resolvers = [system("corp.example.com", "10.0.0.53", isReachable: nil)]

        #expect(status(of: entry("corp.example.com", "10.0.0.53"), in: resolvers) == .active(isReachable: true))
    }

    @Test func ignoresNameserverOrderAndCase() {
        let resolvers = [system("corp.example.com", "fd00::53", "10.0.0.53")]
        let file = ResolverEntry(
            fileName: "corp.example.com",
            path: "/fake/corp.example.com",
            rawText: "nameserver 10.0.0.53\nnameserver FD00::53\n"
        )

        #expect(status(of: file, in: resolvers) == .active(isReachable: true))
    }

    @Test func reportsAMismatchWithTheLoadedNameservers() {
        let resolvers = [system("corp.example.com", "192.0.2.1", "192.0.2.2")]

        #expect(
            status(of: entry("corp.example.com", "10.0.0.53"), in: resolvers)
                == .mismatch(loadedNameservers: ["192.0.2.1", "192.0.2.2"])
        )
    }

    @Test func reportsAFileThatMacOSHasNotLoaded() {
        let resolvers = [system("other.example.com", "10.0.0.53"), system(nil, "10.0.0.53")]

        #expect(status(of: entry("corp.example.com", "10.0.0.53"), in: resolvers) == .notLoaded)
        #expect(status(of: entry("corp.example.com", "10.0.0.53"), in: []) == .notLoaded)
    }

    @Test func isUnknownWithoutSystemInformation() {
        #expect(status(of: entry("corp.example.com", "10.0.0.53"), in: nil) == .unknown)
    }

    @Test func isUnknownForFilesWithoutUsableNameservers() {
        let resolvers = [system("corp.example.com", "10.0.0.53")]

        #expect(status(of: entry("corp.example.com"), in: resolvers) == .unknown)
        #expect(
            status(
                of: ResolverEntry(fileName: "corp.example.com", path: "/fake", readError: "unreadable"),
                in: resolvers
            ) == .unknown
        )
    }

    @Test func followsAnExplicitDomainDirective() {
        let file = ResolverEntry(
            fileName: "alias",
            path: "/fake/alias",
            rawText: "domain Corp.Example.com\nnameserver 10.0.0.53\n"
        )

        #expect(
            status(of: file, in: [system("corp.example.com", "10.0.0.53")]) == .active(isReachable: true)
        )
    }
}
