import SwiftUI

/// Closing the window quits the app, and quitting glides the outputs to 0 V first. Both ask first if there are
/// unsaved edits.
final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor static var player: Player?
    @MainActor static var store: MatrixStore?

    /// Started from a terminal (swift run) the app is not a bundle and may not come to the front,
    /// so Cmd-Q would go to whatever is in front instead (e.g. VS Code).
    @MainActor func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    @MainActor func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Self.store?.confirmDiscard() == false ? .terminateCancel : .terminateNow
    }

    @MainActor func applicationWillTerminate(_ notification: Notification) {
        Self.player?.shutdown()
    }
}

@main
struct CVMatrixApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var store: MatrixStore
    @State private var player: Player

    init() {
        let s = MatrixStore()
        let p = Player(store: s)
        _store = State(initialValue: s)
        _player = State(initialValue: p)
        AppDelegate.player = p
        AppDelegate.store = s
    }

    var body: some Scene {
        WindowGroup("THEREELPEET CV Matrix") {
            ContentView(store: store, player: player)
        }
        .windowStyle(.hiddenTitleBar)            // the grey panel runs up under the window buttons
        .defaultSize(width: 1100, height: 780)   // room for about six rows; drag any edge to resize
        .windowResizability(.contentMinSize)
    }
}
