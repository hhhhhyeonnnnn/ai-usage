// Compiled by render-previews.py alongside the app views, without AIUsageApp.swift.
import AppKit
import SwiftUI

@main
struct RenderPreviews {
    @MainActor
    static func main() async throws {
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let application = NSApplication.shared
        application.setActivationPolicy(.prohibited)
        AppPreferences.migrateRemainingDisplay()
        let useLocal = CommandLine.arguments.contains("--local")
        let store = useLocal ? UsageStore.local() : UsageStore.demo()
        await store.loadIfNeeded()
        if useLocal {
            guard let snapshot = store.state(for: .codex).snapshot, snapshot.source == .localSession else {
                throw CocoaError(.fileReadCorruptFile)
            }
            for provider in [ProviderType.claude, .antigravity] {
                guard let connected = store.state(for: provider).snapshot, connected.source != .demo else {
                    print("Integration failed: \(provider.displayName), \(store.state(for: provider).statusLabel)")
                    throw CocoaError(.fileReadCorruptFile)
                }
                print("\(provider.displayName): \(connected.source.label); \(connected.buckets.map { "\($0.name): \(UsageFormatting.percentage($0.resolvedRemainingFraction)) remaining" }.joined(separator: ", "))")
            }
            print("Codex local integration: \(snapshot.buckets.map(\.name).joined(separator: ", ")); recorded \(snapshot.updatedAt)")
        }

        for (name, scheme, appearance) in [
            ("light", ColorScheme.light, NSAppearance.Name.aqua),
            ("dark", ColorScheme.dark, NSAppearance.Name.darkAqua)
        ] {
            for expanded in [false, true] {
                let view = MenuBarView(store: store, detailsExpanded: expanded)
                    .environment(\.colorScheme, scheme)
                    .background(Color(nsColor: .windowBackgroundColor))
                let host = NSHostingView(rootView: view)
                host.appearance = NSAppearance(named: appearance)
                let size = host.fittingSize
                host.setFrameSize(size)
                host.layoutSubtreeIfNeeded()
                guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
                    throw CocoaError(.fileWriteUnknown)
                }
                host.cacheDisplay(in: host.bounds, to: bitmap)
                guard let data = bitmap.representation(using: .png, properties: [:]) else {
                    throw CocoaError(.fileWriteUnknown)
                }
                let filename = "\(useLocal ? "local-" : "")\(name)-\(expanded ? "expanded" : "compact").png"
                try data.write(to: output.appendingPathComponent(filename))
                print("\(filename): \(Int(size.width)) × \(Int(size.height)) pt")
            }
        }
    }
}
