import SwiftUI

@main
struct FreeFlowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @StateObject private var controller = DictationController.shared
    @StateObject private var preferences = Preferences.shared

    // The menu bar icon is an NSStatusItem set up in AppDelegate, because its panel
    // drops out of the notch rather than hanging under the icon, which a
    // MenuBarExtra can't do.
    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(controller)
                .environmentObject(preferences)
        }
    }
}

/// Wraps the main window so first-run setup appears over it as a sheet rather than
/// as a second floating window.
struct RootView: View {
    @EnvironmentObject private var preferences: Preferences

    var body: some View {
        MainWindow()
            .sheet(isPresented: .constant(!preferences.hasOnboarded)) {
                OnboardingView()
                    .frame(width: 440, height: 520)
                    .background(Theme.background)
            }
    }
}

/// The main window is managed in AppKit rather than as a SwiftUI `Window` scene.
///
/// A SwiftUI `Window` is torn down when the user closes it, and there's no reliable
/// way to ask for it back from an `NSApplicationDelegate`, which left the app
/// running with a Dock icon that did nothing. Owning the `NSWindow` here means
/// closing and reopening always works.
@MainActor
final class MainWindowController: NSObject, NSWindowDelegate {
    static let shared = MainWindowController()

    private var window: NSWindow?

    func show() {
        if window == nil {
            let hosting = NSHostingController(
                rootView: RootView()
                    .environmentObject(DictationController.shared)
                    .environmentObject(Preferences.shared)
            )

            let window = NSWindow(contentViewController: hosting)
            window.title = "FreeFlow"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.setContentSize(NSSize(width: 1080, height: 720))
            window.minSize = NSSize(width: 940, height: 620)
            window.delegate = self
            window.setFrameAutosaveName("FreeFlowMainWindow")
            if window.frame.origin == .zero { window.center() }
            self.window = window
        }

        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}

/// Kept as the name the rest of the UI calls to surface the window.
@MainActor
enum MainWindowOpener {
    static func open() {
        MainWindowController.shared.show()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Regular policy so FreeFlow gets a Dock icon and a menu bar of its own,
        // alongside the status item.
        NSApp.setActivationPolicy(.regular)

        // Load the stored credential off the main thread before any view asks for it.
        CredentialStore.shared.load()

        DictationController.shared.start()
        StatusItemController.shared.install()
        MainWindowController.shared.show()
    }

    /// Clicking the Dock icon always brings the window back, even after it's closed.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainWindowController.shared.show()
        return true
    }

    /// Closing the window shouldn't quit. FreeFlow keeps listening from the menu bar.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
