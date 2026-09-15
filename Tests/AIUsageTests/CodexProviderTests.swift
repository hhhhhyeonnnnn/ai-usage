import Foundation
import Testing
@testable import AIUsage

private func record(
    timestamp: String = "2026-09-15T04:00:00.000Z", minutes: Int = 300,
    used: String = "72", secondary: String = "null", limitID: String = "\"codex\""
) -> String {
    """
    {"timestamp":"\(timestamp)","type":"event_msg","payload":{"type":"token_count","rate_limits":{"limit_id":\(limitID),"primary":{"used_percent":\(used),"window_minutes":\(minutes),"resets_at":1789500000},"secondary":\(secondary)}}}
    """ + "\n"
}

private final class TemporarySessions {
    let home: URL
    let sessions: URL
    init() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        sessions = home.appendingPathComponent("sessions")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
    }
    deinit { try? FileManager.default.removeItem(at: home) }
    @discardableResult
    func write(_ text: String, name: String = "rollout-fixture.jsonl") throws -> URL {
        let url = sessions.appendingPathComponent(name)
        try Data(text.utf8).write(to: url)
        return url
    }
}

struct CodexParserTests {
    @Test func parsesFiveHourAndWeeklyWithRecordedTime() throws {
        let secondary = "{\"used_percent\":41,\"window_minutes\":10080,\"resets_at\":1789827200}"
        let snapshot = try #require(CodexUsageParser.snapshot(from: Data(record(secondary: secondary).utf8)))
        #expect(snapshot.source == .localSession)
        #expect(snapshot.buckets.map(\.name) == ["5h", "Weekly"])
        #expect(snapshot.buckets.map(\.resolvedUsedFraction) == [0.72, 0.41])
        #expect(snapshot.buckets[1].resetsAt == Date(timeIntervalSince1970: 1_789_827_200))
        #expect(snapshot.updatedAt == ISO8601DateFormatter().date(from: "2026-09-15T04:00:00Z"))
    }

    @Test func primaryCanBeWeeklyWithoutInventingFiveHours() throws {
        let snapshot = try #require(CodexUsageParser.snapshot(from: Data(record(minutes: 10_080).utf8)))
        #expect(snapshot.buckets.count == 1)
        #expect(snapshot.buckets.first?.name == "Weekly")
        #expect(snapshot.buckets.first?.period == .weekly)
    }

    @Test func handlesOtherWindowLengthsAndLegacyMissingLimitID() throws {
        let snapshot = try #require(CodexUsageParser.snapshot(from: Data(record(minutes: 90, limitID: "null").utf8)))
        #expect(snapshot.buckets.first?.name == "90m")
        #expect(snapshot.buckets.first?.period == .rollingMinutes(90))
        #expect(CodexUsageParser.snapshot(from: Data(record(limitID: "\"codex_other\"").utf8)) == nil)
    }

    @Test func invalidAndMissingPercentagesRemainUnknown() throws {
        for percent in ["null", "-2", "150"] {
            let snapshot = try #require(CodexUsageParser.snapshot(from: Data(record(used: percent).utf8)))
            #expect(snapshot.buckets.first?.resolvedUsedFraction == nil)
        }
        #expect(CodexUsageParser.snapshot(from: Data(record(minutes: 0).utf8))?.buckets.isEmpty == true)
    }

    @Test func ignoresNonTelemetryMalformedJSONAndInvalidDates() {
        let text = record()
        #expect(CodexUsageParser.snapshot(from: Data(text.replacingOccurrences(of: "event_msg", with: "response_item").utf8)) == nil)
        #expect(CodexUsageParser.snapshot(from: Data(text.replacingOccurrences(of: "token_count", with: "agent_message").utf8)) == nil)
        #expect(CodexUsageParser.snapshot(from: Data(record(timestamp: "invalid").utf8)) == nil)
        #expect(CodexUsageParser.snapshot(from: Data("{incomplete".utf8)) == nil)
    }

    @Test func distinguishesStaleRecordsAndResetDueWithoutZeroingUsage() throws {
        let snapshot = try #require(CodexUsageParser.snapshot(from: Data(record().utf8)))
        #expect(!snapshot.isStale(relativeTo: snapshot.updatedAt.addingTimeInterval(899)))
        #expect(snapshot.isStale(relativeTo: snapshot.updatedAt.addingTimeInterval(900)))
        let reset = try #require(snapshot.buckets[0].resetsAt)
        let nearReset = UsageSnapshot(provider: .codex, updatedAt: reset.addingTimeInterval(-60),
                                      buckets: snapshot.buckets, source: .localSession)
        #expect(nearReset.isStale(relativeTo: reset))
        #expect(nearReset.buckets[0].resolvedUsedFraction == 0.72)
        #expect(!MockUsageProvider(id: .codex).snapshot(updatedAt: .distantPast).isStale(relativeTo: .now))
    }
}

struct CodexReaderTests {
    @Test func newestEventWinsOverFileModificationTime() async throws {
        let fixture = try TemporarySessions()
        let newEvent = try fixture.write(record(timestamp: "2026-09-15T04:10:00Z", used: "22"), name: "rollout-new.jsonl")
        let oldEvent = try fixture.write(record(used: "11"), name: "rollout-old.jsonl")
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1)], ofItemAtPath: newEvent.path)
        try FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: oldEvent.path)
        let snapshot = try await CodexSessionReader(directory: fixture.sessions).latestSnapshot()
        #expect(snapshot?.buckets.first?.resolvedUsedFraction == 0.22)
    }

    @Test func ignoresIncompleteLastLineThenReadsCompletedAppend() async throws {
        let fixture = try TemporarySessions()
        let newer = record(timestamp: "2026-09-15T04:10:00Z", used: "31")
        let url = try fixture.write(record() + newer.dropLast())
        let reader = CodexSessionReader(directory: fixture.sessions)
        #expect(try await reader.latestSnapshot()?.buckets.first?.resolvedUsedFraction == 0.72)
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("\n".utf8))
        try handle.close()
        #expect(try await reader.latestSnapshot()?.buckets.first?.resolvedUsedFraction == 0.31)
    }

    @Test func skipsPartialFirstLineAndMalformedTrailingRecord() async throws {
        let fixture = try TemporarySessions()
        let valid = record(used: "40")
        try fixture.write(String(repeating: "x", count: 2_000) + "\n" + valid + "{bad}\n")
        let reader = CodexSessionReader(directory: fixture.sessions, tailBytes: valid.utf8.count + 50)
        #expect(try await reader.latestSnapshot()?.buckets.first?.resolvedUsedFraction == 0.4)
    }

    @Test func latestExplicitEmptyWindowsSupersedeOldUsage() async throws {
        let fixture = try TemporarySessions()
        let empty = """
        {"timestamp":"2026-09-15T04:30:00Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"limit_id":"codex","primary":null,"secondary":null}}}
        """ + "\n"
        try fixture.write(record() + empty)
        let reader = CodexSessionReader(directory: fixture.sessions)
        #expect(try await reader.latestSnapshot()?.buckets.isEmpty == true)
        await #expect(throws: UsageProviderError.self) {
            _ = try await CodexProvider(codexDirectory: fixture.home).fetchUsage()
        }
    }

    @Test func cacheInvalidatesAfterTruncationAndDeletion() async throws {
        let fixture = try TemporarySessions()
        let url = try fixture.write(record())
        let reader = CodexSessionReader(directory: fixture.sessions)
        #expect(try await reader.latestSnapshot() != nil)
        try Data().write(to: url)
        #expect(try await reader.latestSnapshot() == nil)
        try fixture.write(record())
        #expect(try await reader.latestSnapshot() != nil)
        try FileManager.default.removeItem(at: url)
        #expect(try await reader.latestSnapshot() == nil)
    }

    @Test func skipsUnrelatedAndSymlinkFiles() async throws {
        let fixture = try TemporarySessions()
        let unrelated = try fixture.write(record(), name: "history.jsonl")
        try FileManager.default.createSymbolicLink(at: fixture.sessions.appendingPathComponent("rollout-link.jsonl"),
                                                  withDestinationURL: unrelated)
        #expect(try await CodexSessionReader(directory: fixture.sessions).latestSnapshot() == nil)
    }

    @Test func boundedFileCountAndTailDoNotFallBackToMock() async throws {
        let fixture = try TemporarySessions()
        let old = try fixture.write(record(), name: "rollout-old.jsonl")
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1)], ofItemAtPath: old.path)
        try fixture.write("unrelated\n", name: "rollout-new.jsonl")
        #expect(try await CodexSessionReader(directory: fixture.sessions, maximumFiles: 1).latestSnapshot() == nil)
        #expect(try await CodexSessionReader(directory: fixture.sessions, tailBytes: 10).latestSnapshot() == nil)
    }

    @Test func missingDirectoryIsUnavailable() async throws {
        let fixture = try TemporarySessions()
        let missing = fixture.home.appendingPathComponent("missing")
        #expect(try await CodexSessionReader(directory: missing).latestSnapshot() == nil)
        await #expect(throws: UsageProviderError.self) {
            _ = try await CodexProvider(codexDirectory: missing).fetchUsage()
        }
    }

    @MainActor
    @Test func integrationRetainsRecordTimeWhenCheckedAgain() async throws {
        let fixture = try TemporarySessions()
        try fixture.write(record(minutes: 10_080))
        let store = UsageStore(service: UsageService(providers: [CodexProvider(codexDirectory: fixture.home)]))
        await store.refresh(only: .codex)
        let first = try #require(store.state(for: .codex).snapshot)
        await store.refresh(only: .codex)
        let second = try #require(store.state(for: .codex).snapshot)
        #expect(first == second)
        #expect(second.source == .localSession)
        #expect(try #require(store.lastCheckedAt) > second.updatedAt)
        #expect(store.state(for: .codex).statusLabel == "Local record")
    }
}
