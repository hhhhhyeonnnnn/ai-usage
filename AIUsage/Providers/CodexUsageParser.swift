import Foundation

// Codex's local JSONL schema is isolated here. Only quota telemetry is decoded;
// messages, tools, account credentials and token totals are not part of these DTOs.
enum CodexUsageParser {
    static func snapshot(from line: Data) -> UsageSnapshot? {
        guard line.range(of: Data("\"rate_limits\"".utf8)) != nil else { return nil }
        guard let event = try? JSONDecoder().decode(Event.self, from: line),
              event.type == "event_msg", event.payload.type == "token_count",
              let limits = event.payload.rateLimits,
              limits.limitID == nil || limits.limitID == "codex",
              let timestamp = date(event.timestamp) else { return nil }

        let buckets = [("primary", limits.primary), ("secondary", limits.secondary)]
            .compactMap { id, window in window?.bucket(id: id) }
        // An explicit latest record with no windows must supersede older quotas.
        return UsageSnapshot(provider: .codex, updatedAt: timestamp, buckets: buckets, source: .localSession)
    }

    private static func date(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    private struct Event: Decodable {
        let type: String
        let timestamp: String
        let payload: Payload
    }

    private struct Payload: Decodable {
        let type: String
        let rateLimits: Limits?
        enum CodingKeys: String, CodingKey {
            case type
            case rateLimits = "rate_limits"
        }
    }

    private struct Limits: Decodable {
        let limitID: String?
        let primary: Window?
        let secondary: Window?
        enum CodingKeys: String, CodingKey {
            case primary, secondary
            case limitID = "limit_id"
        }
    }

    private struct Window: Decodable {
        let usedPercent: Double?
        let windowMinutes: Int?
        let resetsAt: Double?
        enum CodingKeys: String, CodingKey {
            case usedPercent = "used_percent"
            case windowMinutes = "window_minutes"
            case resetsAt = "resets_at"
        }

        func bucket(id: String) -> UsageBucket? {
            guard let minutes = windowMinutes, minutes > 0 else { return nil }
            let name: String
            let period: UsagePeriod
            if minutes == 10_080 {
                name = "Weekly"
                period = .weekly
            } else if minutes.isMultiple(of: 60) {
                name = "\(minutes / 60)h"
                period = .rolling(hours: minutes / 60)
            } else {
                name = "\(minutes)m"
                period = .rollingMinutes(minutes)
            }
            // Invalid telemetry is unknown, rather than clamped to a convincing 0/100%.
            let used = usedPercent.flatMap { $0.isFinite && (0...100).contains($0) ? $0 / 100 : nil }
            let reset = resetsAt.flatMap {
                $0.isFinite && $0 > 0 && $0 < 253_402_300_800 ? Date(timeIntervalSince1970: $0) : nil
            }
            return UsageBucket(id: id, name: name, usedFraction: used, resetsAt: reset, period: period)
        }
    }
}
