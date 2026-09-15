import Foundation

protocol UsageProvider: Sendable {
    var id: ProviderType { get }
    var displayName: String { get }
    func fetchUsage() async throws -> UsageSnapshot
}

extension UsageProvider {
    var displayName: String { id.displayName }
}

enum UsageProviderError: Error {
    case unavailable
    case invalidResponse
    case signInRequired
    case keychainRequired
    case antigravityUnavailable
    case rateLimited
}
