import Foundation
import Observation

public struct AppAlert: Identifiable, Equatable, Sendable {
    public let id = UUID()
    public let title: String
    public let message: String
}

/// All state and actions behind the main window. It knows nothing about SwiftUI, which keeps it unit testable.
@MainActor
@Observable
public final class ResolversViewModel {
    public private(set) var entries: [ResolverEntry] = []
    public private(set) var isBusy = false
    public private(set) var hasLoaded = false
    public private(set) var loadError: String?
    public var selection: ResolverEntry.ID?
    public var editor: ResolverDraft?
    public var pendingRemoval: ResolverEntry?
    public var alert: AppAlert?
    private(set) var systemResolvers: [SystemResolver]?

    @ObservationIgnored private let store: any ResolverManaging
    @ObservationIgnored private let inspector: any SystemDNSInspecting
    @ObservationIgnored private let settleDelay: Duration
    @ObservationIgnored private(set) var settleTask: Task<Void, Never>?

    public convenience init() {
        self.init(
            store: ResolverStore(privilegedRunner: OsascriptPrivilegedRunner()),
            inspector: SystemDNSInspector(),
            settleDelay: .seconds(1)
        )
    }

    /// `settleDelay` is how long macOS gets to pick up a change before the status is read again.
    init(store: any ResolverManaging, inspector: any SystemDNSInspecting, settleDelay: Duration = .zero) {
        self.store = store
        self.inspector = inspector
        self.settleDelay = settleDelay
    }

    public var directoryPath: String { store.directoryPath }

    public var selectedEntry: ResolverEntry? {
        entries.first { $0.id == selection }
    }

    public func status(for entry: ResolverEntry) -> ResolverStatus {
        ResolverStatus.evaluate(entry, against: systemResolvers)
    }

    // MARK: Loading

    public func reload() async {
        do {
            entries = try await store.loadEntries()
            loadError = nil
        } catch {
            entries = []
            loadError = error.localizedDescription
        }
        hasLoaded = true
        reconcileSelection()
        await refreshSystemResolvers()
    }

    func refreshSystemResolvers() async {
        systemResolvers = try? await inspector.resolvers()
    }

    // MARK: Editing

    public func beginAdding() {
        editor = ResolverDraft(mode: .add, existingDomains: existingDomains)
    }

    public func beginEditing(_ entry: ResolverEntry) {
        guard entry.isEditable else {
            alert = AppAlert(
                title: "“\(entry.fileName)” Can’t Be Edited",
                message: entry.editBlockReason ?? "This file cannot be edited."
            )
            return
        }
        editor = ResolverDraft(editing: entry, existingDomains: existingDomains)
    }

    public func cancelEditing() {
        editor = nil
    }

    public func saveEditor() async {
        guard let draft = editor, !isBusy else { return }
        let configuration: ResolverConfiguration
        do {
            configuration = try draft.makeConfiguration()
        } catch {
            draft.submissionError = error.localizedDescription
            return
        }
        draft.submissionError = nil

        isBusy = true
        defer { isBusy = false }
        switch await attempt({ try await store.save(configuration) }) {
        case .success:
            editor = nil
            await reloadAfterChange()
            if entries.contains(where: { $0.id == configuration.domain.value }) {
                selection = configuration.domain.value
            }
        case .cancelled:
            break
        case .failure(let message):
            draft.submissionError = message
        }
    }

    // MARK: Removing

    public func requestRemoval(of entry: ResolverEntry) {
        pendingRemoval = entry
    }

    public func remove(_ entry: ResolverEntry) async {
        pendingRemoval = nil
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }

        let removedIndex = entries.firstIndex(of: entry)
        let wasSelected = selection == entry.id
        switch await attempt({ try await store.remove(fileName: entry.fileName) }) {
        case .success:
            await reloadAfterChange()
            if wasSelected, let removedIndex, !entries.isEmpty {
                selection = entries[min(removedIndex, entries.count - 1)].id
            }
        case .cancelled:
            break
        case .failure(let message):
            alert = AppAlert(title: "“\(entry.fileName)” Was Not Removed", message: message)
        }
    }

    // MARK: Cache

    public func flushDNSCache() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }

        switch await attempt({ try await store.flushDNSCache() }) {
        case .success:
            alert = AppAlert(
                title: "DNS Cache Flushed",
                message: "macOS will look up names again instead of using cached answers."
            )
            await refreshSystemResolvers()
        case .cancelled:
            break
        case .failure(let message):
            alert = AppAlert(title: "The DNS Cache Was Not Flushed", message: message)
        }
    }

    // MARK: Helpers

    private enum Outcome {
        case success
        case cancelled
        case failure(String)
    }

    private var existingDomains: Set<String> {
        Set(entries.map { $0.fileName.lowercased() })
    }

    /// Cancelling the password dialog is a decision, not an error, so it never produces a message.
    private func attempt(_ work: () async throws -> Void) async -> Outcome {
        do {
            try await work()
            return .success
        } catch is CancellationError {
            return .cancelled
        } catch PrivilegedExecutionError.cancelled {
            return .cancelled
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    private func reloadAfterChange() async {
        await reload()
        scheduleSettledRefresh()
    }

    /// macOS needs a moment to pick up a changed resolver file, so the status is read once more shortly afterwards.
    private func scheduleSettledRefresh() {
        settleTask?.cancel()
        let delay = settleDelay
        settleTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.refreshSystemResolvers()
        }
    }

    private func reconcileSelection() {
        if let selection, entries.contains(where: { $0.id == selection }) { return }
        selection = entries.first?.id
    }
}
