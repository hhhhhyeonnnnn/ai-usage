import SwiftUI

struct SettingsView: View {
    let store: UsageStore
    @AppStorage("appearance") private var appearance = AppAppearance.system
    @AppStorage("usageDisplay") private var display = UsageDisplay.remaining

    var body: some View {
        Form {
            Section("General") {
                Picker("Appearance", selection: $appearance) {
                    ForEach(AppAppearance.allCases) { Text($0.title).tag($0) }
                }
                Picker("Display", selection: $display) {
                    ForEach(UsageDisplay.allCases) { Text($0.title).tag($0) }
                }
                LabeledContent("Refresh", value: "On open / Manual · ⌘R")
                Toggle("Launch at Login", isOn: .constant(false)).disabled(true)
                Text("Automatic refresh and launch at login are planned for Phase 3.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Providers") {
                ForEach(ProviderType.allCases) { provider in
                    LabeledContent(provider.displayName, value: store.state(for: provider).statusLabel)
                }
            }
            Section {
                Text("Connected usage sources")
                    .font(.headline)
                Text("Codex reads local session records. Claude uses your desktop login and Keychain; some accounts do not report percentage limits. Antigravity must be running and shows the server’s weekly pools, with 5-hour limits in Details. Credentials stay in memory.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 460)
        .preferredColorScheme(appearance.colorScheme)
    }
}
