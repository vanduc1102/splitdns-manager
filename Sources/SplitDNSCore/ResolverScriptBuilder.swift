import Foundation

/// Builds the `/bin/sh` scripts that change the resolver directory. They run as root, so every path and
/// value is quoted and nothing is ever taken from the user without validation first.
struct ResolverScriptBuilder: Sendable {
    static let defaultDirectoryPath = "/etc/resolver"

    var directoryPath = Self.defaultDirectoryPath
    /// Tests turn this off so they never restart the real `mDNSResponder`.
    var flushesDNSCache = true

    func path(for fileName: String) -> String {
        (directoryPath as NSString).appendingPathComponent(fileName)
    }

    /// Writes the file via a temporary file and an atomic rename, so macOS never sees a half-written resolver
    /// and a symbolic link at the destination is replaced instead of being written through.
    func saveScript(for configuration: ResolverConfiguration) -> String {
        let destination = ShellQuoting.quote(path(for: configuration.domain.value))
        let template = ShellQuoting.quote(path(for: ".splitdns.XXXXXX"))
        let lines = configuration.fileLines.map(ShellQuoting.quote).joined(separator: " ")
        let commands = [
            "set -eu",
            "umask 022",
            "/bin/mkdir -p -- \(ShellQuoting.quote(directoryPath))",
            "tmp=$(/usr/bin/mktemp \(template))",
            "trap '/bin/rm -f -- \"$tmp\"' EXIT",
            "/usr/bin/printf '%s\\n' \(lines) > \"$tmp\"",
            "/bin/chmod 644 \"$tmp\"",
            "/bin/mv -f -- \"$tmp\" \(destination)",
        ]
        return (commands + flushCommands(failOnError: false)).joined(separator: "\n")
    }

    func removeScript(fileName: String) throws -> String {
        let path = try validatedPath(for: fileName)
        let commands = ["set -eu", "/bin/rm -f -- \(ShellQuoting.quote(path))"]
        return (commands + flushCommands(failOnError: false)).joined(separator: "\n")
    }

    func flushScript() -> String {
        (["set -eu"] + flushCommands(failOnError: true)).joined(separator: "\n")
    }

    /// After a change the flush is best effort, because the change itself already succeeded.
    private func flushCommands(failOnError: Bool) -> [String] {
        guard flushesDNSCache else { return [] }
        let suffix = failOnError ? "" : " || true"
        return [
            "/usr/bin/dscacheutil -flushcache\(suffix)",
            "/usr/bin/killall -HUP mDNSResponder\(suffix)",
        ]
    }

    private func validatedPath(for fileName: String) throws -> String {
        guard !fileName.isEmpty, !fileName.hasPrefix("."), !fileName.contains("/"),
            !fileName.unicodeScalars.contains("\u{0}")
        else {
            throw ResolverValidationError.invalidFileName(fileName)
        }
        return path(for: fileName)
    }
}
