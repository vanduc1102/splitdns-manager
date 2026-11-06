import Foundation
import Observation

/// The form state behind the add/edit sheet. Everything is kept as text so half-typed input is fine;
/// `makeConfiguration()` turns it into a validated `ResolverConfiguration`.
@MainActor
@Observable
public final class ResolverDraft: Identifiable {
    public enum Mode: Equatable, Sendable {
        case add
        case edit
    }

    public struct NameserverField: Identifiable, Equatable, Sendable {
        public let id = UUID()
        public var text: String
    }

    public let id = UUID()
    public let mode: Mode
    public var domain: String
    public var nameservers: [NameserverField]
    public var port: String
    /// Set by the view model when saving fails, so the message appears inside the sheet.
    public var submissionError: String?
    /// Comments and directives of the existing file that this app does not edit. They are written back unchanged.
    public let preservedLines: [String]
    private let existingDomains: Set<String>

    init(
        mode: Mode,
        domain: String = "",
        nameservers: [String] = [],
        port: String = "",
        preservedLines: [String] = [],
        existingDomains: Set<String> = []
    ) {
        self.mode = mode
        self.domain = domain
        self.nameservers = (nameservers.isEmpty ? [""] : nameservers).map(NameserverField.init(text:))
        self.port = port
        self.preservedLines = preservedLines
        self.existingDomains = existingDomains
    }

    convenience init(editing entry: ResolverEntry, existingDomains: Set<String>) {
        self.init(
            mode: .edit,
            domain: entry.fileName,
            nameservers: entry.nameservers,
            port: entry.port.map(String.init) ?? "",
            preservedLines: entry.extraLines,
            existingDomains: existingDomains
        )
    }

    public var canAddNameserver: Bool {
        nameservers.count < ResolverConfiguration.maximumNameservers
    }

    public var canRemoveNameserver: Bool {
        nameservers.count > 1
    }

    /// `nil` while the form is valid.
    public var validationMessage: String? {
        do {
            _ = try makeConfiguration()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    public var isValid: Bool {
        validationMessage == nil
    }

    /// True until the user typed anything, so an untouched form does not open with an error message.
    public var isPristine: Bool {
        mode == .add && trimmed(domain).isEmpty && trimmed(port).isEmpty
            && nameservers.allSatisfy { trimmed($0.text).isEmpty }
    }

    public var targetFileName: String? {
        try? DomainName(domain).value
    }

    /// The text that will be written to the resolver file.
    public var preview: String {
        if let configuration = try? makeConfiguration() {
            return configuration.fileLines.joined(separator: "\n")
        }
        let nameserverLines = nameservers.map(\.text).map(trimmed).filter { !$0.isEmpty }.map { "nameserver \($0)" }
        let portLines = trimmed(port).isEmpty ? [] : ["port \(trimmed(port))"]
        return (nameserverLines + portLines + preservedLines).joined(separator: "\n")
    }

    public func addNameserver() {
        guard canAddNameserver else { return }
        nameservers.append(NameserverField(text: ""))
    }

    public func removeNameserver(id: NameserverField.ID) {
        guard canRemoveNameserver else { return }
        nameservers.removeAll { $0.id == id }
    }

    func makeConfiguration() throws -> ResolverConfiguration {
        let name = try DomainName(domain)
        if mode == .add, existingDomains.contains(name.value) {
            throw ResolverValidationError.domainAlreadyExists(name.value)
        }
        let addresses = try nameservers.map(\.text)
            .filter { !trimmed($0).isEmpty }
            .map(NameserverAddress.init)
        return try ResolverConfiguration(
            domain: name,
            nameservers: addresses,
            port: try parsedPort(),
            extraLines: preservedLines
        )
    }

    private func parsedPort() throws -> Int? {
        let text = trimmed(port)
        guard !text.isEmpty else { return nil }
        guard let value = Int(text), ResolverFileParser.validPorts.contains(value) else {
            throw ResolverValidationError.invalidPort(text)
        }
        return value
    }

    private func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
