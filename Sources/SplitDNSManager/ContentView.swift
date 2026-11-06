import AppKit
import SplitDNSCore
import SwiftUI

struct ContentView: View {
    @Bindable var viewModel: ResolversViewModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 420)
        } detail: {
            detail
        }
        .toolbar { toolbarContent }
        .sheet(item: $viewModel.editor) { draft in
            ResolverEditorView(
                draft: draft,
                directoryPath: viewModel.directoryPath,
                isSaving: viewModel.isBusy,
                onSave: { Task { await viewModel.saveEditor() } },
                onCancel: viewModel.cancelEditing
            )
        }
        .confirmationDialog(
            "Remove “\(viewModel.pendingRemoval?.fileName ?? "")”?",
            isPresented: isRemovalPresented,
            titleVisibility: .visible,
            presenting: viewModel.pendingRemoval
        ) { entry in
            Button("Remove", role: .destructive) { Task { await viewModel.remove(entry) } }
        } message: { entry in
            Text(
                "Lookups for \(entry.effectiveDomain) will go back to your normal DNS servers. This asks for your administrator password."
            )
        }
        .alert(
            viewModel.alert?.title ?? "",
            isPresented: isAlertPresented,
            presenting: viewModel.alert
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { alert in
            Text(alert.message)
        }
        .task { await viewModel.reload() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await viewModel.reload() }
            }
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        List(selection: $viewModel.selection) {
            ForEach(viewModel.entries) { entry in
                ResolverRow(entry: entry, status: viewModel.status(for: entry))
            }
        }
        .contextMenu(forSelectionType: ResolverEntry.ID.self) { ids in
            if let entry = entry(for: ids) {
                Button("Edit…") { viewModel.beginEditing(entry) }
                    .disabled(!entry.isEditable)
                Button("Reveal in Finder") { reveal(entry) }
                Divider()
                Button("Remove…", role: .destructive) { viewModel.requestRemoval(of: entry) }
            }
        } primaryAction: { ids in
            if let entry = entry(for: ids) {
                viewModel.beginEditing(entry)
            }
        }
        .onDeleteCommand {
            if let entry = viewModel.selectedEntry {
                viewModel.requestRemoval(of: entry)
            }
        }
        .overlay {
            if viewModel.hasLoaded, viewModel.loadError == nil, viewModel.entries.isEmpty {
                Text("No Resolvers")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        if let entry = viewModel.selectedEntry {
            ResolverDetailView(
                entry: entry,
                status: viewModel.status(for: entry),
                onReveal: { reveal(entry) }
            )
        } else if let error = viewModel.loadError {
            ContentUnavailableView(
                "Can’t Read \(viewModel.directoryPath)",
                systemImage: "exclamationmark.triangle",
                description: Text(error)
            )
        } else if viewModel.hasLoaded {
            ContentUnavailableView {
                Label("No Resolvers", systemImage: "point.3.connected.trianglepath.dotted")
            } description: {
                Text(
                    "Add a domain to send its DNS lookups to a specific name server, such as your company DNS for an internal domain."
                )
            } actions: {
                Button("Add Resolver…") { viewModel.beginAdding() }
            }
        } else {
            ProgressView()
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            Button("Add Resolver", systemImage: "plus") { viewModel.beginAdding() }
                .help("Add a resolver (⌘N)")
            Button("Edit Resolver", systemImage: "pencil") {
                if let entry = viewModel.selectedEntry {
                    viewModel.beginEditing(entry)
                }
            }
            .disabled(viewModel.selectedEntry?.isEditable != true)
            .help("Edit the selected resolver")
            Button("Remove Resolver", systemImage: "trash") {
                if let entry = viewModel.selectedEntry {
                    viewModel.requestRemoval(of: entry)
                }
            }
            .disabled(viewModel.selectedEntry == nil || viewModel.isBusy)
            .help("Remove the selected resolver")
        }
        ToolbarItemGroup {
            if viewModel.isBusy {
                ProgressView().controlSize(.small)
            }
            Button("Refresh", systemImage: "arrow.clockwise") { Task { await viewModel.reload() } }
                .help("Reload the resolvers and their status (⌘R)")
            Button("Flush DNS Cache", systemImage: "wind") { Task { await viewModel.flushDNSCache() } }
                .disabled(viewModel.isBusy)
                .help("Flush the DNS cache (⌥⌘F)")
        }
    }

    // MARK: Helpers

    private var isRemovalPresented: Binding<Bool> {
        Binding(
            get: { viewModel.pendingRemoval != nil },
            set: { if !$0 { viewModel.pendingRemoval = nil } }
        )
    }

    private var isAlertPresented: Binding<Bool> {
        Binding(
            get: { viewModel.alert != nil },
            set: { if !$0 { viewModel.alert = nil } }
        )
    }

    private func entry(for ids: Set<ResolverEntry.ID>) -> ResolverEntry? {
        viewModel.entries.first { ids.contains($0.id) }
    }

    private func reveal(_ entry: ResolverEntry) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: entry.path)])
    }
}
