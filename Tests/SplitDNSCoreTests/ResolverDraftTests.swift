import Testing

@testable import SplitDNSCore

@MainActor
struct ResolverDraftTests {
    private func makeDraft(
        mode: ResolverDraft.Mode = .add,
        domain: String = "corp.example.com",
        nameservers: [String] = ["10.0.0.53"],
        port: String = "",
        preservedLines: [String] = [],
        existingDomains: Set<String> = []
    ) -> ResolverDraft {
        ResolverDraft(
            mode: mode,
            domain: domain,
            nameservers: nameservers,
            port: port,
            preservedLines: preservedLines,
            existingDomains: existingDomains
        )
    }

    private func message(of error: ResolverValidationError) -> String? {
        error.errorDescription
    }

    // MARK: Validation

    @Test func anUntouchedNewDraftIsPristineAndInvalid() {
        let draft = ResolverDraft(mode: .add)

        #expect(draft.isPristine)
        #expect(!draft.isValid)
        #expect(draft.nameservers.count == 1)
        #expect(draft.targetFileName == nil)
    }

    @Test func aCompleteDraftBuildsTheConfiguration() throws {
        let draft = makeDraft(domain: "  Corp.Example.COM. ", nameservers: [" 10.0.0.53 "], port: " 5353 ")

        let configuration = try draft.makeConfiguration()

        #expect(draft.isValid)
        #expect(draft.validationMessage == nil)
        #expect(draft.targetFileName == "corp.example.com")
        #expect(configuration.fileContents == "nameserver 10.0.0.53\nport 5353\n")
    }

    @Test func ignoresBlankNameserverRows() throws {
        let draft = makeDraft(nameservers: ["10.0.0.53", "   ", ""])

        #expect(try draft.makeConfiguration().nameservers.map(\.value) == ["10.0.0.53"])
    }

    @Test func requiresAtLeastOneNameserver() {
        let draft = makeDraft(nameservers: ["", " "])

        #expect(draft.validationMessage == message(of: .noNameservers))
    }

    @Test func reportsTheFirstProblemInTheDomain() {
        #expect(makeDraft(domain: "*.example.com").validationMessage == message(of: .wildcardDomain))
        #expect(makeDraft(domain: "").validationMessage == message(of: .emptyDomain))
    }

    @Test func reportsAnInvalidNameserver() {
        let draft = makeDraft(nameservers: ["10.0.0.53", "dns.example.com"])

        #expect(draft.validationMessage == message(of: .invalidNameserver("dns.example.com")))
    }

    @Test func recognisesTheSameAddressWrittenDifferently() {
        let draft = makeDraft(nameservers: ["fd00::53", "FD00:0:0:0:0:0:0:53"])

        #expect(draft.validationMessage == message(of: .duplicateNameserver("fd00::53")))
    }

    @Test(arguments: ["abc", "0", "-5", "65536", "53.5"])
    func rejectsInvalidPorts(port: String) {
        #expect(makeDraft(port: port).validationMessage == message(of: .invalidPort(port)))
    }

    @Test func rejectsADomainThatAlreadyHasAFileWhenAdding() {
        let draft = makeDraft(domain: "CORP.example.com", existingDomains: ["corp.example.com"])

        #expect(draft.validationMessage == message(of: .domainAlreadyExists("corp.example.com")))
    }

    @Test func allowsTheExistingDomainWhenEditing() {
        let draft = makeDraft(mode: .edit, existingDomains: ["corp.example.com"])

        #expect(draft.isValid)
    }

    // MARK: Nameserver rows

    @Test func allowsAtMostThreeNameserverRows() {
        let draft = makeDraft()

        draft.addNameserver()
        draft.addNameserver()
        #expect(draft.nameservers.count == 3)
        #expect(!draft.canAddNameserver)

        draft.addNameserver()
        #expect(draft.nameservers.count == 3)
    }

    @Test func alwaysKeepsOneNameserverRow() {
        let draft = makeDraft(nameservers: ["10.0.0.1", "10.0.0.2"])

        draft.removeNameserver(id: draft.nameservers[0].id)
        #expect(draft.nameservers.map(\.text) == ["10.0.0.2"])
        #expect(!draft.canRemoveNameserver)

        draft.removeNameserver(id: draft.nameservers[0].id)
        #expect(draft.nameservers.map(\.text) == ["10.0.0.2"])
    }

    // MARK: Editing existing files

    @Test func editingStartsFromTheFilesValuesAndKeepsItsOtherLines() throws {
        let file = ResolverEntry(
            fileName: "corp.example.com",
            path: "/fake/corp.example.com",
            rawText: "# managed by hand\nnameserver 10.0.0.53\nnameserver 10.0.0.54\nport 5353\nsearch_order 1\n"
        )

        let draft = ResolverDraft(editing: file, existingDomains: ["corp.example.com"])

        #expect(draft.mode == .edit)
        #expect(draft.domain == "corp.example.com")
        #expect(draft.nameservers.map(\.text) == ["10.0.0.53", "10.0.0.54"])
        #expect(draft.port == "5353")
        #expect(draft.preservedLines == ["# managed by hand", "search_order 1"])
        #expect(
            try draft.makeConfiguration().fileContents
                == "nameserver 10.0.0.53\nnameserver 10.0.0.54\nport 5353\n# managed by hand\nsearch_order 1\n"
        )
    }

    @Test func aDraftIsNotPristineOnceTheUserTypedOrIsEditing() {
        let typed = ResolverDraft(mode: .add)
        typed.nameservers[0].text = "1"

        #expect(!typed.isPristine)
        #expect(!makeDraft(mode: .edit, domain: "", nameservers: [], port: "").isPristine)
    }

    // MARK: Preview

    @Test func previewShowsTheCanonicalFileWhenValid() {
        let draft = makeDraft(nameservers: ["FD00:0:0:0:0:0:0:53"], port: "53", preservedLines: ["# keep"])

        #expect(draft.preview == "nameserver fd00::53\nport 53\n# keep")
    }

    @Test func previewStillShowsWhatWasTypedWhileInvalid() {
        let draft = makeDraft(domain: "", nameservers: [" 10.0.0.5 ", ""], port: " 99 ", preservedLines: ["# keep"])

        #expect(draft.preview == "nameserver 10.0.0.5\nport 99\n# keep")
    }
}
