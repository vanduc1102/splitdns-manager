import AppKit
import SplitDNSCore
import SwiftUI

@MainActor
@main
struct SplitDNSManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    // The App value is created once per launch, so a plain `let` keeps the model alive without `@State`
    // (whose macro implementation isn't shipped with the Command Line Tools).
    private let viewModel = ResolversViewModel()

    var body: some Scene {
        Window("SplitDNS Manager", id: "main") {
            ContentView(viewModel: viewModel)
                .frame(minWidth: 760, minHeight: 460)
        }
        .defaultSize(width: 920, height: 600)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Resolver…") { viewModel.beginAdding() }
                    .keyboardShortcut("n")
            }
            CommandMenu("DNS") {
                Button("Refresh") { Task { await viewModel.reload() } }
                    .keyboardShortcut("r")
                Button("Flush DNS Cache") { Task { await viewModel.flushDNSCache() } }
                    .keyboardShortcut("f", modifiers: [.command, .option])
                    .disabled(viewModel.isBusy)
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
