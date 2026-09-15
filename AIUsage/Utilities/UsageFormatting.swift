import Foundation

enum UsageFormatting {
    static func percentage(_ fraction: Double?) -> String {
        guard let fraction = UsageBucket.normalized(fraction) else { return "—" }
        return "\(Int((fraction * 100).rounded()))%"
    }

    static func reset(_ date: Date?, relativeTo now: Date) -> String {
        guard let date else { return "Reset unknown" }
        let seconds = date.timeIntervalSince(now)
        guard seconds > 0 else { return "Reset due" }
        let minutes = Int(ceil(seconds / 60))
        if minutes >= 1_440 { return "reset \(minutes / 1_440)d \((minutes % 1_440) / 60)h" }
        if minutes >= 60 { return "reset \(minutes / 60)h \(minutes % 60)m" }
        return "reset \(minutes)m"
    }

    static func updated(_ date: Date?, relativeTo now: Date, label: String = "Updated") -> String {
        guard let date else { return "Not \(label.lowercased()) yet" }
        let minutes = max(0, Int(now.timeIntervalSince(date) / 60))
        if minutes == 0 { return "\(label) just now" }
        if minutes < 60 { return "\(label) \(minutes)m ago" }
        if minutes < 1_440 { return "\(label) \(minutes / 60)h ago" }
        return "\(label) \(minutes / 1_440)d ago"
    }
}
