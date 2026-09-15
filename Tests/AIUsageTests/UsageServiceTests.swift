import Foundation
import Testing
@testable import AIUsage

private struct FixtureProvider: UsageProvider {
    enum Result: Sendable { case success, unavailable, failure, mismatched }
    let id: ProviderType
    let result: Result

    func fetchUsage() async throws -> UsageSnapshot {
        switch result {
        case .success:
            return MockUsageProvider(id: id).snapshot(updatedAt: .now)
        case .unavailable:
            throw UsageProviderError.unavailable
        case .failure:
            throw NSError(domain: "sensitive-token-must-never-appear", code: 401)
        case .mismatched:
            return MockUsageProvider(id: .antigravity).snapshot(updatedAt: .now)
        }
    }
}

private actor UpdateCollector {
    var updates: [ProviderUpdate] = []
    func append(_ update: ProviderUpdate) { updates.append(update) }
}

struct UsageServiceTests {
    @Test func providerFailureIsIsolatedAndSanitized() async {
        let service = UsageService(providers: [
            FixtureProvider(id: .codex, result: .success),
            FixtureProvider(id: .claude, result: .failure),
            FixtureProvider(id: .antigravity, result: .unavailable)
        ])
        let collector = UpdateCollector()
        await service.refresh { await collector.append($0) }
        let updates = await collector.updates
        #expect(updates.count == 3)
        #expect(updates.first { $0.provider == .codex }?.state.snapshot != nil)
        #expect(updates.first { $0.provider == .antigravity }?.state == .unavailable)
        #expect(updates.first { $0.provider == .claude }?.state == .error("Usage couldn’t be refreshed. Try again."))
    }

    @Test func retryFetchesOnlySelectedProvider() async {
        let service = UsageService(providers: ProviderType.allCases.map {
            FixtureProvider(id: $0, result: .success)
        })
        let collector = UpdateCollector()
        await service.refresh(only: .claude) { await collector.append($0) }
        let updates = await collector.updates
        #expect(updates.count == 1)
        #expect(updates.first?.provider == .claude)
    }

    @Test func mismatchedResponseCannotPopulateAnotherProvider() async {
        let service = UsageService(providers: [FixtureProvider(id: .codex, result: .mismatched)])
        let collector = UpdateCollector()
        await service.refresh { await collector.append($0) }
        #expect(await collector.updates.first?.state == .error("Invalid provider response."))
    }

    @MainActor
    @Test func storePublishesIndependentStatesAndCompletesRefresh() async {
        let store = UsageStore(service: UsageService(providers: [
            FixtureProvider(id: .codex, result: .success),
            FixtureProvider(id: .claude, result: .unavailable),
            FixtureProvider(id: .antigravity, result: .success)
        ]))
        await store.loadIfNeeded()
        #expect(store.state(for: .codex).snapshot?.buckets.count == 2)
        #expect(store.state(for: .claude) == .unavailable)
        #expect(store.state(for: .antigravity).snapshot?.buckets.count == 2)
        #expect(!store.isRefreshing)
        #expect(store.lastUpdatedAt != nil)
    }
}
