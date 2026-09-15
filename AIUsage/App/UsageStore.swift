import Foundation
import Observation

@MainActor
@Observable
final class UsageStore {
    private(set) var states: [ProviderType: ProviderState] = [:]
    private(set) var refreshing: Set<ProviderType> = []
    private var hasLoaded = false
    private(set) var lastCheckedAt: Date?
    private let service: UsageService

    init(service: UsageService) {
        self.service = service
    }

    static func demo(referenceDate: Date = .now) -> UsageStore {
        UsageStore(service: UsageService(providers: ProviderType.allCases.map {
            MockUsageProvider(id: $0, referenceDate: referenceDate)
        }))
    }

    static func local() -> UsageStore {
        UsageStore(service: UsageService(providers: [
            CodexProvider(), ClaudeProvider(), AntigravityProvider()
        ]))
    }

    var isRefreshing: Bool { !refreshing.isEmpty }

    // The oldest successful provider is the honest timestamp for an overview.
    var lastUpdatedAt: Date? {
        states.values.compactMap { $0.snapshot?.updatedAt }.min()
    }

    func state(for provider: ProviderType) -> ProviderState { states[provider] ?? .loading }

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        await refresh()
    }

    func refreshOnOpen() async {
        guard !hasLoaded || lastCheckedAt.map({ Date.now.timeIntervalSince($0) >= 60 }) ?? true else { return }
        await refresh()
    }

    func refresh(only provider: ProviderType? = nil) async {
        // Serialize user-triggered batches to avoid stale, overlapping responses.
        guard !isRefreshing else { return }
        let requested = provider.map { [$0] } ?? ProviderType.allCases
        refreshing = Set(requested)
        for id in requested where states[id]?.snapshot == nil { states[id] = .loading }
        defer { refreshing.removeAll() }
        await service.refresh(only: provider) { [weak self] update in
            await self?.apply(update)
        }
        if !Task.isCancelled {
            hasLoaded = true
            lastCheckedAt = .now
        }
    }

    private func apply(_ update: ProviderUpdate) {
        states[update.provider] = update.state
    }
}
