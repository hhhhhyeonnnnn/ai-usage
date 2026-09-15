import Foundation

enum UsagePeriod: Equatable, Sendable {
    case rolling(hours: Int)
    case rollingMinutes(Int)
    case weekly
    case quotaPool
    case modelActivity
}

struct UsageBucket: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let usedFraction: Double?
    let remainingFraction: Double?
    let resetsAt: Date?
    let period: UsagePeriod
    let children: [UsageBucket]

    init(
        id: String, name: String, usedFraction: Double? = nil,
        remainingFraction: Double? = nil, resetsAt: Date? = nil,
        period: UsagePeriod, children: [UsageBucket] = []
    ) {
        self.id = id
        self.name = name
        self.usedFraction = Self.normalized(usedFraction)
        self.remainingFraction = Self.normalized(remainingFraction)
        self.resetsAt = resetsAt
        self.period = period
        self.children = children
    }

    // Unknown values remain unknown. Pool values never derive from child activity.
    var resolvedUsedFraction: Double? {
        usedFraction ?? remainingFraction.map { 1 - $0 }
    }

    var resolvedRemainingFraction: Double? {
        remainingFraction ?? usedFraction.map { 1 - $0 }
    }

    static func normalized(_ value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        return min(max(value, 0), 1)
    }
}
