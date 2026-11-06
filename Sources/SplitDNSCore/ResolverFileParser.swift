import Foundation

/// The contents of an existing resolver file, split into the directives this app edits and everything else.
struct ParsedResolverFile: Hashable, Sendable {
    var nameservers: [NameserverAddress] = []
    var port: Int?
    /// Comments, unknown directives and anything that could not be parsed, in their original order.
    var extraLines: [String] = []

    /// An explicit `domain` directive overrides the file name as the domain macOS matches.
    var domainOverride: String? {
        extraLines.lazy.compactMap(Self.domain(in:)).first
    }

    private static func domain(in line: String) -> String? {
        let tokens = line.split(whereSeparator: \.isWhitespace)
        guard tokens.count == 2, tokens[0] == "domain" else { return nil }
        return String(tokens[1])
    }
}

enum ResolverFileParser {
    static let validPorts = 1...65535

    static func parse(_ text: String) -> ParsedResolverFile {
        var result = ParsedResolverFile()
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            let tokens = line.split(whereSeparator: \.isWhitespace).map(String.init)
            if tokens.count == 2, tokens[0] == "nameserver", let address = try? NameserverAddress(tokens[1]) {
                result.nameservers.append(address)
            } else if tokens.count == 2, tokens[0] == "port", result.port == nil,
                let port = Int(tokens[1]), validPorts.contains(port)
            {
                result.port = port
            } else {
                result.extraLines.append(line)
            }
        }
        return result
    }
}
