import SwiftUI

struct MenuBarView: View {
    let store: UsageStore
    @AppStorage("appearance") private var appearance = AppAppearance.system
    @AppStorage("usageDisplay") private var display = UsageDisplay.remaining
    @Environment(\.openSettings) private var openSettings
    @State private var detailsExpanded = false

    init(store: UsageStore, detailsExpanded: Bool = false) {
        self.store = store
        _detailsExpanded = State(initialValue: detailsExpanded)
    }

    var body: some View {
        VStack(spacing: 0) {
            header.padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 10)

            // A bounded scrolling area keeps Settings and Quit reachable on small displays.
            ScrollView { providerContent }
                .id(detailsExpanded) // Start each page at the top.
                .scrollIndicators(.visible)
                .frame(height: contentHeight)

            footer
        }
        .frame(width: 320)
        .fixedSize(horizontal: false, vertical: true)
        .background(.regularMaterial)
        .preferredColorScheme(appearance.colorScheme)
        .task { await store.refreshOnOpen() }
    }

    private var contentHeight: CGFloat {
        // Keep the menu window size stable when navigating: MenuBarExtra may retain
        // its original window bounds while SwiftUI lays out a taller detail view.
        let preferred: CGFloat = 276
        let available = (NSScreen.main?.visibleFrame.height ?? 800) - 180
        return min(preferred, max(200, available))
    }

    private var header: some View {
        HStack(spacing: 8) {
            if detailsExpanded {
                Button(action: toggleDetails) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.borderless)
                .help("All providers")
                .accessibilityLabel("All providers")
            }
            Text(detailsExpanded ? "Antigravity" : "AI Usage")
                .font(.system(size: 14, weight: .semibold))
            Spacer()
            Text(display == .used ? "Used %" : "Remaining %")
                .font(.system(size: 10)).foregroundStyle(.secondary)
            Button {
                Task { await store.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .disabled(store.isRefreshing)
            .help("Refresh usage (⌘R)")
            .accessibilityLabel("Refresh usage")
            .keyboardShortcut("r", modifiers: .command)
        }
    }

    private var providerContent: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            VStack(alignment: .leading, spacing: 8) {
                ForEach(detailsExpanded ? [.antigravity] : ProviderType.allCases) { provider in
                    providerSection(provider, now: context.date)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func providerSection(_ provider: ProviderType, now: Date) -> some View {
        if provider != .codex && !detailsExpanded { Divider() }
        if detailsExpanded, let snapshot = store.state(for: provider).snapshot {
            AntigravityDetailView(snapshot: snapshot)
        } else {
            ProviderCard(
                provider: provider, state: store.state(for: provider),
                isRefreshing: store.refreshing.contains(provider), canRetry: !store.isRefreshing,
                display: display, now: now,
                retry: { Task { await store.refresh(only: provider) } },
                showsTitle: !detailsExpanded,
                detailExpanded: detailsExpanded,
                toggleDetails: provider == .antigravity ? { toggleDetails() } : nil
            )
        }
    }

    private func toggleDetails() {
        detailsExpanded.toggle()
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            TimelineView(.periodic(from: .now, by: 60)) { context in
                Text(store.isRefreshing ? "Refreshing…" : UsageFormatting.updated(store.lastCheckedAt, relativeTo: context.date, label: "Checked"))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button("Settings…") {
                    NSApp.activate(ignoringOtherApps: true)
                    openSettings()
                }
                .keyboardShortcut(",", modifiers: .command)
                Spacer()
                Toggle("Launch at Login", isOn: .constant(false))
                    .toggleStyle(.checkbox)
                    .font(.system(size: 9))
                    .disabled(true)
                    .help("Planned for Phase 3.")
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .keyboardShortcut("q", modifiers: .command)
            }
            .buttonStyle(.borderless)
            .font(.system(size: 11))
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }
}
