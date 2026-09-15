import Foundation
import Testing
@testable import AIUsage

struct UsageModelTests {
    @Test func unknownUsageIsNotZero() {
        let bucket = UsageBucket(id: "unknown", name: "Unknown", period: .quotaPool)
        #expect(bucket.resolvedUsedFraction == nil)
        #expect(bucket.resolvedRemainingFraction == nil)
        #expect(UsageFormatting.percentage(bucket.resolvedUsedFraction) == "—")
    }

    @Test func remainingOnlyProviderConvertsToUsed() {
        let bucket = UsageBucket(id: "quota", name: "Quota", remainingFraction: 0.25, period: .weekly)
        #expect(bucket.resolvedUsedFraction == 0.75)
        #expect(UsageDisplay.remaining.fraction(for: bucket) == 0.25)
    }

    @Test func malformedFractionsAreSafeToRender() {
        #expect(UsageBucket.normalized(.nan) == nil)
        #expect(UsageBucket.normalized(.infinity) == nil)
        #expect(UsageBucket.normalized(-0.2) == 0)
        #expect(UsageBucket.normalized(1.4) == 1)
        #expect(UsageFormatting.percentage(1.4) == "100%")
    }

    @Test func modelActivityDoesNotDeterminePoolUsage() {
        let child = UsageBucket(id: "model", name: "Model", usedFraction: 0.9, period: .modelActivity)
        let pool = UsageBucket(id: "pool", name: "Pool", usedFraction: 0.2, period: .quotaPool, children: [child])
        #expect(pool.resolvedUsedFraction == 0.2)
        let unknownPool = UsageBucket(id: "unknown", name: "Unknown pool", period: .quotaPool, children: [child])
        #expect(unknownPool.resolvedUsedFraction == nil)
    }

    @Test func resetFormattingHandlesBoundaries() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(UsageFormatting.reset(nil, relativeTo: now) == "Reset unknown")
        #expect(UsageFormatting.reset(now, relativeTo: now) == "Reset due")
        #expect(UsageFormatting.reset(now.addingTimeInterval(-60), relativeTo: now) == "Reset due")
        #expect(UsageFormatting.reset(now.addingTimeInterval(1), relativeTo: now) == "reset 1m")
        #expect(UsageFormatting.reset(now.addingTimeInterval(5_520), relativeTo: now) == "reset 1h 32m")
        #expect(UsageFormatting.reset(now.addingTimeInterval(302_400), relativeTo: now) == "reset 3d 12h")
    }

    @Test func refreshingMockDoesNotSlideResetTime() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let provider = MockUsageProvider(id: .codex, referenceDate: now)
        let first = provider.snapshot(updatedAt: now)
        let next = provider.snapshot(updatedAt: now.addingTimeInterval(180))
        #expect(first.buckets[0].resetsAt == next.buckets[0].resetsAt)
        #expect(next.updatedAt > first.updatedAt)
    }
}
