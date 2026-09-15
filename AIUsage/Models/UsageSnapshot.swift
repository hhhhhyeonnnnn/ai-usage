import Foundation

enum UsageSource: String, Equatable, Sendable {
    case demo
    case localSession
    case claudeDesktop
    case localServer

    var label: String {
        switch self {
        case .demo: "Demo"
        case .localSession: "Local record"
        case .claudeDesktop: "Connected"
        case .localServer: "Live · weekly"
        }
    }
}

struct UsageSnapshot: Identifiable, Equatable, Sendable {
    var id: ProviderType { provider }
    let provider: ProviderType
    let updatedAt: Date
    let buckets: [UsageBucket]
    let source: UsageSource

    init(provider: ProviderType, updatedAt: Date, buckets: [UsageBucket], source: UsageSource = .demo) {
        self.provider = provider
        self.updatedAt = updatedAt
        self.buckets = buckets
        self.source = source
    }

    func isStale(relativeTo now: Date) -> Bool {
        source == .localSession && (
            now.timeIntervalSince(updatedAt) >= 15 * 60 ||
            buckets.contains { $0.resetsAt.map { $0 <= now } ?? false }
        )
    }
}
