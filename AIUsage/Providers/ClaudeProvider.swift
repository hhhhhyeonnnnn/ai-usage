import Foundation

actor ClaudeProvider: UsageProvider {
    nonisolated let id = ProviderType.claude
    private var cached: UsageSnapshot?
    private var retryAfter: Date = .distantPast

    func fetchUsage() async throws -> UsageSnapshot {
        if let cached, Date.now.timeIntervalSince(cached.updatedAt) < 30 { return cached }
        guard Date.now >= retryAfter else { throw UsageProviderError.rateLimited }
        let credentials = try await Task.detached { try ClaudeDesktopCredentials.read() }.value
        var request = URLRequest(url: URL(string: "https://claude.ai/api/organizations/\(credentials.organization)/usage")!)
        request.setValue("sessionKey=\(credentials.sessionKey)", forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("https://claude.ai", forHTTPHeaderField: "Origin")
        request.setValue("https://claude.ai/settings/usage", forHTTPHeaderField: "Referer")
        do {
            let data = try await QuotaHTTPClient().data(for: request)
            let snapshot = try ClaudeQuotaParser.parse(data)
            cached = snapshot
            return snapshot
        } catch UsageProviderError.rateLimited {
            retryAfter = .now.addingTimeInterval(180)
            throw UsageProviderError.rateLimited
        }
    }
}

enum ClaudeQuotaParser {
    private struct Response: Decodable {
        let five_hour: Window?
        let seven_day: Window?
    }
    private struct Window: Decodable {
        let utilization: Double?
        let resets_at: String?
    }

    static func parse(_ data: Data, now: Date = .now) throws -> UsageSnapshot {
        // Explicit null windows are a valid authenticated response (e.g. this Free account).
        // Missing fields/error envelopes must never look like a successful connection.
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["five_hour"] != nil, root["seven_day"] != nil, root["error"] == nil else {
            throw UsageProviderError.invalidResponse
        }
        let response = try JSONDecoder().decode(Response.self, from: data)
        let buckets = [
            UsageBucket(id: "claude-5h", name: "5 Hours",
                        usedFraction: QuotaParsing.fraction(response.five_hour?.utilization, scale: 100),
                        resetsAt: QuotaParsing.date(response.five_hour?.resets_at), period: .rolling(hours: 5)),
            UsageBucket(id: "claude-7d", name: "Weekly",
                        usedFraction: QuotaParsing.fraction(response.seven_day?.utilization, scale: 100),
                        resetsAt: QuotaParsing.date(response.seven_day?.resets_at), period: .weekly)
        ]
        return UsageSnapshot(provider: .claude, updatedAt: now, buckets: buckets, source: .claudeDesktop)
    }
}
