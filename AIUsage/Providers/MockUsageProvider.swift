import Foundation

struct MockUsageProvider: UsageProvider {
    let id: ProviderType
    private let referenceDate: Date

    init(id: ProviderType, referenceDate: Date = .now) {
        self.id = id
        self.referenceDate = referenceDate
    }

    func fetchUsage() async throws -> UsageSnapshot {
        try await Task.sleep(for: .milliseconds(250))
        return snapshot(updatedAt: .now)
    }

    func snapshot(updatedAt: Date) -> UsageSnapshot {
        let buckets: [UsageBucket]
        switch id {
        case .codex:
            buckets = [
                bucket("5h", "5h", 0.72, 5_520, .rolling(hours: 5)),
                bucket("weekly", "Weekly", 0.41, 302_400, .weekly)
            ]
        case .claude:
            buckets = [bucket("weekly", "Weekly", 0.58, 352_800, .weekly)]
        case .antigravity:
            buckets = [
                bucket("gemini", "Gemini Pool", 0.63, 12_060, .quotaPool, children: [
                    activity("gemini-pro", "Gemini 3.1 Pro", 0.48),
                    activity("gemini-flash", "Gemini Flash", 0.15)
                ]),
                bucket("claude-gpt", "Claude / GPT Pool", 0.28, 100_800, .quotaPool, children: [
                    activity("claude-sonnet", "Claude Sonnet", 0.19),
                    activity("gpt", "GPT", 0.06)
                ])
            ]
        }
        return UsageSnapshot(provider: id, updatedAt: updatedAt, buckets: buckets)
    }

    private func bucket(
        _ id: String, _ name: String, _ used: Double, _ resetOffset: TimeInterval,
        _ period: UsagePeriod, children: [UsageBucket] = []
    ) -> UsageBucket {
        UsageBucket(id: id, name: name, usedFraction: used,
                    resetsAt: referenceDate.addingTimeInterval(resetOffset),
                    period: period, children: children)
    }

    private func activity(_ id: String, _ name: String, _ used: Double) -> UsageBucket {
        UsageBucket(id: id, name: name, usedFraction: used, period: .modelActivity)
    }
}
