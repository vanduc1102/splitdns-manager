import Foundation

enum ShellQuoting {
    /// Quotes a value so that a POSIX shell reads it back as exactly one unchanged word.
    /// The value must not contain NUL characters, which cannot be passed to a shell at all.
    static func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
