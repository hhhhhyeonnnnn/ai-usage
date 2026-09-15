import Foundation
import Testing
@testable import AIUsage

struct ConnectedProviderTests {
    @Test func claudeConvertsActualUtilizationAndPreservesUnknownWindows() throws {
        let data = Data(#"{"five_hour":{"utilization":72.5,"resets_at":"2026-09-16T09:00:00.123Z"},"seven_day":null}"#.utf8)
        let snapshot = try ClaudeQuotaParser.parse(data)
        #expect(snapshot.source == .claudeDesktop)
        #expect(abs(snapshot.buckets[0].resolvedRemainingFraction! - 0.275) < 0.00001)
        #expect(snapshot.buckets[0].resetsAt != nil)
        #expect(snapshot.buckets[1].resolvedRemainingFraction == nil)
    }

    @Test func authenticatedNullLimitsAreNotFullOrEmptyQuota() throws {
        let data = Data(#"{"five_hour":null,"seven_day":null,"extra_usage":null}"#.utf8)
        let snapshot = try ClaudeQuotaParser.parse(data)
        #expect(snapshot.source == .claudeDesktop)
        #expect(snapshot.buckets.allSatisfy { $0.resolvedRemainingFraction == nil })
    }

    @Test(arguments: [#"{}"#, #"{"error":"secret"}"#, #"{"five_hour":null}"#,
                      #"{"five_hour":{"utilization":true},"seven_day":null}"#])
    func claudeMalformedResponseIsNotConnected(json: String) {
        #expect(throws: (any Error).self) { try ClaudeQuotaParser.parse(Data(json.utf8)) }
    }

    @Test func outOfRangeQuotaDoesNotBecomeZeroOrFull() throws {
        let data = Data(#"{"five_hour":{"utilization":101},"seven_day":{"utilization":-1}}"#.utf8)
        let snapshot = try ClaudeQuotaParser.parse(data)
        #expect(snapshot.buckets.allSatisfy { $0.resolvedRemainingFraction == nil })
    }

    @Test func antigravityUsesExplicitWeeklyPoolAndKeepsBothWindows() throws {
        let data = Data(#"{"response":{"groups":[{"displayName":"Gemini Models","buckets":[{"window":"5h","remainingFraction":1,"resetTime":"2026-09-15T10:00:00Z"},{"window":"weekly","remainingFraction":0.66,"resetTime":"2026-09-16T11:00:00Z"}]},{"displayName":"Claude and GPT models","buckets":[{"window":"weekly","remainingFraction":0.31},{"window":"5h","remainingFraction":0.92}]}]}}"#.utf8)
        let snapshot = try AntigravityQuotaParser.parse(data)
        #expect(snapshot.source == .localServer)
        #expect(snapshot.buckets.map(\.remainingFraction) == [0.66, 0.31])
        #expect(snapshot.buckets[0].children.count == 2)
        #expect(snapshot.buckets[0].resetsAt == QuotaParsing.date("2026-09-16T11:00:00Z"))
    }

    @Test func missingWeeklyDoesNotSubstituteFiveHourOrZero() throws {
        let data = Data(#"{"response":{"groups":[{"displayName":"Gemini Models","buckets":[{"window":"5h","remainingFraction":0.9}]}]}}"#.utf8)
        let snapshot = try AntigravityQuotaParser.parse(data)
        #expect(snapshot.buckets[0].remainingFraction == nil)
        #expect(snapshot.buckets[0].children[0].remainingFraction == 0.9)
    }

    @Test(arguments: [
        #"{"response":{"groups":[{"displayName":"Unknown models","buckets":[]}]}}"#,
        #"{"response":{"groups":[{"displayName":"Gemini Models","buckets":[{"window":"weekly","remainingFraction":0.2},{"window":"weekly","remainingFraction":0.8}]}]}}"#
    ])
    func ambiguousPoolResponsesAreRejected(json: String) {
        #expect(throws: (any Error).self) { try AntigravityQuotaParser.parse(Data(json.utf8)) }
    }

    @Test func discoveryRejectsNonLoopbackListenersAndInvalidPorts() {
        let ports = AntigravityDiscovery.ports(in: "TCP *:55920 (LISTEN) TCP 127.0.0.1:55922 (LISTEN) TCP 192.168.1.1:55923 TCP 127.0.0.1:99999 TCP 127.0.0.1:55922")
        #expect(ports == [55922])
        #expect(AntigravityDiscovery.flag("--csrf_token", in: "x --csrf_token=fixture --other 1") == "fixture")
        #expect(AntigravityDiscovery.flag("--csrf_token", in: "x --csrf_token") == nil)
    }

    @Test func cookieDomainHashAndCipherVersionAreVerified() throws {
        let key = try ClaudeCookieCrypto.key(password: Data("fixture-password".utf8))
        #expect(key == hex("5d84e88b8d2628e23102b464d77a5bbd"))
        // Synthetic vector generated independently with OpenSSL, not a real cookie.
        let encrypted = hex("7631305767e7ee44a2a58ff7ab218ea85db23b1c5e492578180c5248102811431e5583cb119d085e5f9ebf7e4bc53d2deb9b940c3396a817c7ab9e03f7fd32b133a3ff")
        #expect(try ClaudeCookieCrypto.decrypt(encrypted, key: key, host: ".claude.ai", hasDomainHash: true) == "sk-ant-sid01-fixture")
        for host in ["claude.ai", "example.com"] {
            #expect(throws: (any Error).self) { try ClaudeCookieCrypto.decrypt(encrypted, key: key, host: host, hasDomainHash: true) }
        }
        #expect(throws: (any Error).self) { try ClaudeCookieCrypto.decrypt(Data("v20bad".utf8), key: key, host: ".claude.ai", hasDomainHash: true) }
        #expect(!ClaudeDesktopCredentials.validSession("value\r\nHost: evil"))
        #expect(!ClaudeDesktopCredentials.validSession("value;other=1"))
    }

    @Test func authenticatedRedirectsAreNeverFollowed() async {
        let client = QuotaHTTPClient()
        let original = URL(string: "https://claude.ai/api/organizations/fixture/usage")!
        let response = HTTPURLResponse(url: original, statusCode: 302, httpVersion: nil, headerFields: nil)!
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let task = session.dataTask(with: original)
        let rejected = await withCheckedContinuation { continuation in
            client.urlSession(session, task: task, willPerformHTTPRedirection: response,
                              newRequest: URLRequest(url: URL(string: "https://example.com/")!)) {
                continuation.resume(returning: $0 == nil)
            }
        }
        #expect(rejected)
    }

    @Test func remainingMigrationRunsOnceAndPreservesLaterChoice() {
        let suite = "AIUsageTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("used", forKey: "usageDisplay")
        AppPreferences.migrateRemainingDisplay(defaults: defaults)
        #expect(defaults.string(forKey: "usageDisplay") == "remaining")
        defaults.set("used", forKey: "usageDisplay")
        AppPreferences.migrateRemainingDisplay(defaults: defaults)
        #expect(defaults.string(forKey: "usageDisplay") == "used")
    }

    private func hex(_ value: String) -> Data {
        let bytes = Array(value.utf8)
        return Data(stride(from: 0, to: bytes.count, by: 2).map {
            UInt8(String(decoding: bytes[$0..<$0 + 2], as: UTF8.self), radix: 16)!
        })
    }
}
