import Foundation

/// One `resolver #N` block of `scutil --dns`.
struct SystemResolver: Equatable, Sendable {
    var domain: String?
    var nameservers: [String] = []
    var port: Int?
    /// `nil` when `scutil` printed no reachability flags.
    var isReachable: Bool?
}

/// Parses the "DNS configuration" section of `scutil --dns`, which is what macOS really uses to route queries.
enum SystemDNSParser {
    private static let scopedSectionHeader = "DNS configuration (for scoped queries)"
    private static let reachableFlag: UInt32 = 0x2

    static func parse(_ output: String) -> [SystemResolver] {
        var resolvers: [SystemResolver] = []
        var current: SystemResolver?

        for rawLine in output.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix(scopedSectionHeader) { break }
            if line.hasPrefix("resolver #") {
                if let current { resolvers.append(current) }
                current = SystemResolver()
                continue
            }
            guard current != nil, let separator = line.firstIndex(of: ":") else { continue }

            let key = line[..<separator].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
            switch key {
            case "domain":
                current?.domain = normalized(domain: value)
            case _ where key.hasPrefix("nameserver["):
                current?.nameservers.append(value.lowercased())
            case "port":
                current?.port = Int(value)
            case "reach":
                current?.isReachable = isReachable(reachValue: value)
            default:
                break
            }
        }
        if let current { resolvers.append(current) }
        return resolvers
    }

    static func normalized(domain: String) -> String {
        let lowered = domain.lowercased()
        return lowered.hasSuffix(".") ? String(lowered.dropLast()) : lowered
    }

    private static func isReachable(reachValue: String) -> Bool? {
        guard let hex = reachValue.split(separator: " ").first, hex.hasPrefix("0x"),
            let flags = UInt32(hex.dropFirst(2), radix: 16)
        else { return nil }
        return flags & reachableFlag != 0
    }
}

protocol SystemDNSInspecting: Sendable {
    func resolvers() async throws -> [SystemResolver]
}

struct SystemDNSInspector: SystemDNSInspecting {
    var commandRunner: any CommandRunning = ProcessCommandRunner()

    func resolvers() async throws -> [SystemResolver] {
        let result = try await commandRunner.run("/usr/sbin/scutil", arguments: ["--dns"])
        guard result.status == 0 else {
            throw CommandError.failed(result.standardError.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return SystemDNSParser.parse(result.standardOutput)
    }
}
