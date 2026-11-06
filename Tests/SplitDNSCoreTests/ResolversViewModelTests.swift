import Testing

@testable import SplitDNSCore

@MainActor
struct ResolversViewModelTests {
    private struct Fixture {
        let viewModel: ResolversViewModel
        let store: FakeResolverStore
        let inspector: FakeSystemDNSInspector
    }

    private func makeFixture(entries: [ResolverEntry] = [], system: [SystemResolver] = []) -> Fixture {
        let store = FakeResolverStore(entries: entries)
        let inspector = FakeSystemDNSInspector(resolvers: system)
        return Fixture(
            viewModel: ResolversViewModel(store: store, inspector: inspector),
            store: store,
            inspector: inspector
        )
    }

    private func fillIn(_ draft: ResolverDraft, domain: String = "corp.example.com", nameserver: String = "10.0.0.53") {
        draft.domain = domain
        draft.nameservers[0].text = nameserver
    }

    /// Dismissing the password dialog surfaces as one of these, and must never be reported as a failure.
    private nonisolated static let cancellations: [any Error] = [
        PrivilegedExecutionError.cancelled, CancellationError(),
    ]

    // MARK: Loading

    @Test func reloadingListsTheEntriesAndSelectsTheFirst() async {
        let fixture = makeFixture(entries: [entry("a.example", "10.0.0.1"), entry("b.example", "10.0.0.2")])
        let viewModel = fixture.viewModel
        #expect(!viewModel.hasLoaded)

        await viewModel.reload()

        #expect(viewModel.entries.map(\.fileName) == ["a.example", "b.example"])
        #expect(viewModel.selection == "a.example")
        #expect(viewModel.selectedEntry?.fileName == "a.example")
        #expect(viewModel.hasLoaded)
        #expect(viewModel.loadError == nil)
        #expect(viewModel.directoryPath == "/fake/resolver")
    }

    @Test func reloadingKeepsAValidSelectionAndReplacesAStaleOne() async {
        let fixture = makeFixture(entries: [entry("a.example", "10.0.0.1"), entry("b.example", "10.0.0.2")])
        let viewModel = fixture.viewModel

        viewModel.selection = "b.example"
        await viewModel.reload()
        #expect(viewModel.selection == "b.example")

        viewModel.selection = "gone.example"
        await viewModel.reload()
        #expect(viewModel.selection == "a.example")
    }

    @Test func aFailedReloadShowsTheErrorAndRecoversLater() async {
        let fixture = makeFixture(entries: [entry("a.example", "10.0.0.1")])
        let viewModel = fixture.viewModel
        await viewModel.reload()

        await fixture.store.failLoading(with: CommandError.failed("Operation not permitted"))
        await viewModel.reload()
        #expect(viewModel.entries.isEmpty)
        #expect(viewModel.selection == nil)
        #expect(viewModel.loadError == "Operation not permitted")
        #expect(viewModel.hasLoaded)

        await fixture.store.failLoading(with: nil)
        await viewModel.reload()
        #expect(viewModel.entries.count == 1)
        #expect(viewModel.loadError == nil)
    }

    @Test func statusFollowsWhatMacOSHasLoaded() async {
        let loaded = entry("corp.example.com", "10.0.0.53")
        let missing = entry("other.example.com", "10.0.0.54")
        let system = [
            SystemResolver(domain: "corp.example.com", nameservers: ["10.0.0.53"], port: nil, isReachable: true)
        ]
        let viewModel = makeFixture(entries: [loaded, missing], system: system).viewModel
        #expect(viewModel.status(for: loaded) == .unknown)

        await viewModel.reload()

        #expect(viewModel.status(for: loaded) == .active(isReachable: true))
        #expect(viewModel.status(for: missing) == .notLoaded)
    }

    @Test func statusStaysUnknownWhenScutilFails() async {
        let target = entry("corp.example.com", "10.0.0.53")
        let fixture = makeFixture(entries: [target])
        await fixture.inspector.fail(with: CommandError.failed("scutil failed"))

        await fixture.viewModel.reload()

        #expect(fixture.viewModel.status(for: target) == .unknown)
        #expect(fixture.viewModel.loadError == nil)
    }

    // MARK: Opening the editor

    @Test func addingOpensAnEmptyDraftThatKnowsTheExistingDomains() async throws {
        let viewModel = makeFixture(entries: [entry("a.example", "10.0.0.1")]).viewModel
        await viewModel.reload()

        viewModel.beginAdding()

        let draft = try #require(viewModel.editor)
        #expect(draft.mode == .add)
        #expect(draft.isPristine)
        fillIn(draft, domain: "A.example")
        #expect(draft.validationMessage == ResolverValidationError.domainAlreadyExists("a.example").errorDescription)
    }

    @Test func editingOpensADraftOfTheEntry() async throws {
        let target = entry("a.example", "10.0.0.1", port: 5353)
        let viewModel = makeFixture(entries: [target]).viewModel
        await viewModel.reload()

        viewModel.beginEditing(target)

        let draft = try #require(viewModel.editor)
        #expect(draft.mode == .edit)
        #expect(draft.domain == "a.example")
        #expect(draft.port == "5353")
        viewModel.cancelEditing()
        #expect(viewModel.editor == nil)
    }

    @Test func aReadOnlyEntryShowsAnAlertInsteadOfAnEditor() {
        let link = ResolverEntry(
            fileName: "corp.example.com",
            path: "/fake/corp.example.com",
            origin: .symlink(target: "/nix/store/resolver"),
            rawText: "nameserver 10.0.0.1\n"
        )
        let viewModel = makeFixture(entries: [link]).viewModel

        viewModel.beginEditing(link)

        #expect(viewModel.editor == nil)
        #expect(viewModel.alert?.title == "“corp.example.com” Can’t Be Edited")
        #expect(viewModel.alert?.message.contains("/nix/store/resolver") == true)
    }

    // MARK: Saving

    @Test func savingStoresTheFileClosesTheEditorAndSelectsIt() async throws {
        let fixture = makeFixture(entries: [entry("a.example", "10.0.0.1")])
        let viewModel = fixture.viewModel
        await viewModel.reload()
        viewModel.beginAdding()
        fillIn(try #require(viewModel.editor), domain: "Corp.Example.com")

        await viewModel.saveEditor()

        #expect(await fixture.store.savedConfigurations.map(\.domain.value) == ["corp.example.com"])
        #expect(viewModel.editor == nil)
        #expect(viewModel.entries.map(\.fileName) == ["a.example", "corp.example.com"])
        #expect(viewModel.selection == "corp.example.com")
        #expect(viewModel.alert == nil)
        #expect(!viewModel.isBusy)
    }

    @Test func savingReadsTheSystemStatusAgainOnceMacOSHadAMoment() async throws {
        let fixture = makeFixture()
        fixture.viewModel.beginAdding()
        fillIn(try #require(fixture.viewModel.editor))

        await fixture.viewModel.saveEditor()
        await fixture.viewModel.settleTask?.value

        // Once while reloading after the save, once more after the settle delay.
        #expect(await fixture.inspector.callCount == 2)
    }

    @Test func savingAnInvalidDraftKeepsTheEditorOpenAndSkipsTheStore() async throws {
        let fixture = makeFixture()
        fixture.viewModel.beginAdding()

        await fixture.viewModel.saveEditor()

        #expect(fixture.viewModel.editor?.submissionError == ResolverValidationError.emptyDomain.errorDescription)
        #expect(await fixture.store.savedConfigurations.isEmpty)
        #expect(!fixture.viewModel.isBusy)
    }

    @Test func aFailedSaveIsShownInsideTheEditor() async throws {
        let fixture = makeFixture()
        await fixture.store.failChanges(with: PrivilegedExecutionError.failed("Operation not permitted"))
        fixture.viewModel.beginAdding()
        let draft = try #require(fixture.viewModel.editor)
        fillIn(draft)

        await fixture.viewModel.saveEditor()

        #expect(fixture.viewModel.editor === draft)
        #expect(draft.submissionError == "Operation not permitted")
        #expect(fixture.viewModel.alert == nil)
        #expect(!fixture.viewModel.isBusy)
    }

    @Test(arguments: cancellations)
    func cancellingThePasswordDialogDuringASaveChangesNothing(cancellation: any Error) async throws {
        let fixture = makeFixture()
        await fixture.store.failChanges(with: cancellation)
        fixture.viewModel.beginAdding()
        let draft = try #require(fixture.viewModel.editor)
        fillIn(draft)

        await fixture.viewModel.saveEditor()

        #expect(fixture.viewModel.editor === draft)
        #expect(draft.submissionError == nil)
        #expect(fixture.viewModel.alert == nil)
    }

    // MARK: Removing

    @Test func removalNeedsConfirmationBeforeAnythingIsDeleted() async {
        let target = entry("a.example", "10.0.0.1")
        let fixture = makeFixture(entries: [target])
        await fixture.viewModel.reload()

        fixture.viewModel.requestRemoval(of: target)

        #expect(fixture.viewModel.pendingRemoval == target)
        #expect(await fixture.store.removedFileNames.isEmpty)
    }

    @Test func removingSelectsTheNeighbourAtTheSamePosition() async {
        let entries = [entry("a.example", "10.0.0.1"), entry("b.example", "10.0.0.2"), entry("c.example", "10.0.0.3")]
        let fixture = makeFixture(entries: entries)
        let viewModel = fixture.viewModel
        await viewModel.reload()

        viewModel.selection = "b.example"
        viewModel.requestRemoval(of: entries[1])
        await viewModel.remove(entries[1])
        #expect(await fixture.store.removedFileNames == ["b.example"])
        #expect(viewModel.pendingRemoval == nil)
        #expect(viewModel.selection == "c.example")

        await viewModel.remove(entries[2])
        #expect(viewModel.selection == "a.example")

        await viewModel.remove(entries[0])
        #expect(viewModel.entries.isEmpty)
        #expect(viewModel.selection == nil)
    }

    @Test func removingAnotherEntryKeepsTheSelection() async {
        let entries = [entry("a.example", "10.0.0.1"), entry("b.example", "10.0.0.2")]
        let viewModel = makeFixture(entries: entries).viewModel
        await viewModel.reload()

        viewModel.selection = "a.example"
        await viewModel.remove(entries[1])

        #expect(viewModel.selection == "a.example")
    }

    @Test func aFailedRemovalShowsAnAlertAndKeepsTheEntry() async {
        let target = entry("a.example", "10.0.0.1")
        let fixture = makeFixture(entries: [target])
        await fixture.viewModel.reload()
        await fixture.store.failChanges(with: PrivilegedExecutionError.failed("Operation not permitted"))

        await fixture.viewModel.remove(target)

        #expect(fixture.viewModel.alert?.title == "“a.example” Was Not Removed")
        #expect(fixture.viewModel.alert?.message == "Operation not permitted")
        #expect(fixture.viewModel.entries == [target])
        #expect(!fixture.viewModel.isBusy)
    }

    @Test(arguments: cancellations)
    func cancellingThePasswordDialogDuringARemovalChangesNothing(cancellation: any Error) async {
        let target = entry("a.example", "10.0.0.1")
        let fixture = makeFixture(entries: [target])
        await fixture.viewModel.reload()
        await fixture.store.failChanges(with: cancellation)

        await fixture.viewModel.remove(target)

        #expect(fixture.viewModel.alert == nil)
        #expect(fixture.viewModel.entries == [target])
    }

    // MARK: Flushing

    @Test func flushingConfirmsWithAnAlert() async {
        let fixture = makeFixture()

        await fixture.viewModel.flushDNSCache()

        #expect(await fixture.store.flushCount == 1)
        #expect(fixture.viewModel.alert?.title == "DNS Cache Flushed")
        #expect(!fixture.viewModel.isBusy)
    }

    @Test func aFailedFlushShowsAnAlert() async {
        let fixture = makeFixture()
        await fixture.store.failChanges(with: PrivilegedExecutionError.failed("Operation not permitted"))

        await fixture.viewModel.flushDNSCache()

        #expect(fixture.viewModel.alert?.title == "The DNS Cache Was Not Flushed")
        #expect(fixture.viewModel.alert?.message == "Operation not permitted")
    }

    @Test(arguments: cancellations)
    func cancellingThePasswordDialogDuringAFlushChangesNothing(cancellation: any Error) async {
        let fixture = makeFixture()
        await fixture.store.failChanges(with: cancellation)

        await fixture.viewModel.flushDNSCache()

        #expect(fixture.viewModel.alert == nil)
        #expect(await fixture.store.flushCount == 0)
    }

    // MARK: Busy

    @Test(.timeLimit(.minutes(1)))
    func ignoresNewRequestsWhileAnotherOneIsRunning() async {
        let fixture = makeFixture()
        await fixture.store.holdFlushes()
        let first = Task { await fixture.viewModel.flushDNSCache() }
        while await !fixture.store.hasHeldFlush { await Task.yield() }
        #expect(fixture.viewModel.isBusy)

        await fixture.viewModel.flushDNSCache()
        #expect(await fixture.store.flushCount == 0)

        await fixture.store.releaseHeldFlush()
        await first.value
        #expect(await fixture.store.flushCount == 1)
        #expect(!fixture.viewModel.isBusy)
    }
}
