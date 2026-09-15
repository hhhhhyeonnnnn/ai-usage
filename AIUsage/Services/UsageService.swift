import Foundation

struct ProviderUpdate: Sendable {
    let provider: ProviderType
    let state: ProviderState
}

actor UsageService {
    private let providers: [any UsageProvider]

    init(providers: [any UsageProvider]) {
        self.providers = providers
    }

    // Each provider finishes independently; a failed provider cannot cancel its siblings.
    func refresh(
        only selected: ProviderType? = nil,
        receive: @escaping @Sendable (ProviderUpdate) async -> Void
    ) async {
        let selectedProviders = providers.filter { selected == nil || $0.id == selected }
        await withTaskGroup(of: ProviderUpdate.self) { group in
            for provider in selectedProviders {
                group.addTask {
                    do {
                        let snapshot = try await provider.fetchUsage()
                        guard snapshot.provider == provider.id else {
                            return ProviderUpdate(provider: provider.id, state: .error("Invalid provider response."))
                        }
                        return ProviderUpdate(provider: provider.id, state: .loaded(snapshot))
                    } catch is CancellationError {
                        return ProviderUpdate(provider: provider.id, state: .unavailable)
                    } catch UsageProviderError.unavailable {
                        return ProviderUpdate(provider: provider.id, state: .unavailable)
                    } catch UsageProviderError.signInRequired {
                        return ProviderUpdate(provider: provider.id, state: .error("Open Claude and sign in, then retry."))
                    } catch UsageProviderError.keychainRequired {
                        return ProviderUpdate(provider: provider.id, state: .error("Allow Claude Keychain access, then retry."))
                    } catch UsageProviderError.antigravityUnavailable {
                        return ProviderUpdate(provider: provider.id, state: .error("Open Antigravity and sign in, then retry."))
                    } catch UsageProviderError.rateLimited {
                        return ProviderUpdate(provider: provider.id, state: .error("Too many requests. Retry in 3 minutes."))
                    } catch UsageProviderError.invalidResponse {
                        return ProviderUpdate(provider: provider.id, state: .error("Quota response unavailable."))
                    } catch {
                        // Raw provider errors can contain URLs or credentials. Never display/log them.
                        return ProviderUpdate(provider: provider.id, state: .error("Usage couldn’t be refreshed. Try again."))
                    }
                }
            }
            for await update in group {
                guard !Task.isCancelled else { continue }
                await receive(update)
            }
        }
    }
}
