import SwiftUI

@main
struct AIUsageApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var store = UsageStore.local()
    @State private var menuBarInserted = true

    init() { AppPreferences.migrateRemainingDisplay() }

    var body: some Scene {
        MenuBarExtra("AI", isInserted: $menuBarInserted) {
            MenuBarView(store: store)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(store: store)
        }
        .windowResizability(.contentSize)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
