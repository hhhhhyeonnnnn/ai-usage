import Foundation

actor AntigravityProvider: UsageProvider {
    nonisolated let id = ProviderType.antigravity
    private var cached: UsageSnapshot?
    private var retryAfter: Date = .distantPast

    func fetchUsage() async throws -> UsageSnapshot {
        if let cached, Date.now.timeIntervalSince(cached.updatedAt) < 30 { return cached }
        guard Date.now >= retryAfter else { throw UsageProviderError.rateLimited }
        let endpoints = try await Task.detached { try AntigravityDiscovery.endpoints() }.value
        for endpoint in endpoints {
            try Task.checkCancellation()
            do {
                let client = QuotaHTTPClient()
                let data = try await client.data(for: endpoint.request(method: "RetrieveUserQuotaSummary"))
                let snapshot = try AntigravityQuotaParser.parse(data)
                cached = snapshot
                return snapshot
            } catch UsageProviderError.rateLimited {
                retryAfter = .now.addingTimeInterval(180)
                throw UsageProviderError.rateLimited
            } catch is CancellationError { throw CancellationError() }
            catch { continue }
        }
        throw UsageProviderError.antigravityUnavailable
    }
}

struct AntigravityEndpoint: Sendable {
    let port: Int
    let csrf: String

    func request(method: String) -> URLRequest {
        // Discovery only supplies loopback ports owned by the installed Antigravity binary.
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/exa.language_server_pb.LanguageServerService/\(method)")!)
        request.httpMethod = "POST"
        request.httpBody = Data("{}".utf8)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(csrf, forHTTPHeaderField: "X-Codeium-Csrf-Token")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        request.timeoutInterval = 4
        return request
    }
}

enum AntigravityDiscovery {
    static func endpoints() throws -> [AntigravityEndpoint] {
        let processes = try command("/bin/ps", ["-axo", "uid=,pid=,comm=,args="])
        var endpoints: [AntigravityEndpoint] = []
        for line in processes.split(separator: "\n") {
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.count > 3, UInt32(fields[0]) == getuid(),
                  let pid = Int32(fields[1]), pid > 0,
                  line.contains("/Applications/Antigravity.app/Contents/"),
                  let token = flag("--csrf_token", in: String(line)),
                  token.count <= 256, !token.isEmpty,
                  token.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "-_.".contains($0)) }) else { continue }
            // Confirm executable identity separately; arguments alone are not trusted.
            let executable = try command("/bin/ps", ["-p", String(pid), "-o", "comm="]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard executable.hasPrefix("/Applications/Antigravity.app/Contents/"),
                  URL(fileURLWithPath: executable).lastPathComponent.hasPrefix("language_server") else { continue }
            let listeners = try command("/usr/sbin/lsof", ["-nP", "-a", "-p", String(pid), "-iTCP", "-sTCP:LISTEN"])
            for port in ports(in: listeners) { endpoints.append(AntigravityEndpoint(port: port, csrf: token)) }
            if endpoints.count >= 8 { break }
        }
        guard !endpoints.isEmpty else { throw UsageProviderError.antigravityUnavailable }
        return Array(endpoints.prefix(8))
    }

    static func flag(_ name: String, in line: String) -> String? {
        let fields = line.split(whereSeparator: \.isWhitespace).map(String.init)
        if let index = fields.firstIndex(of: name), index + 1 < fields.count { return fields[index + 1] }
        return fields.first(where: { $0.hasPrefix(name + "=") }).map { String($0.dropFirst(name.count + 1)) }
    }

    static func ports(in output: String) -> [Int] {
        Array(Set(output.split(whereSeparator: \.isWhitespace).compactMap { field -> Int? in
            guard field.hasPrefix("127.0.0.1:"), let port = Int(field.dropFirst(10)), (1...65535).contains(port) else { return nil }
            return port
        })).sorted()
    }

    private static func command(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        // Fixed local utilities; cap output and runtime, never log process arguments.
        let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 3, execute: watchdog)
        defer { watchdog.cancel() }
        var data = Data()
        while let chunk = try pipe.fileHandleForReading.read(upToCount: 65_536), !chunk.isEmpty {
            guard data.count + chunk.count <= 4_000_000 else {
                if process.isRunning { process.terminate() }
                throw UsageProviderError.unavailable
            }
            data.append(chunk)
        }
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}

enum AntigravityQuotaParser {
    private struct Envelope: Decodable { let response: Response }
    private struct Response: Decodable { let groups: [Group] }
    private struct Group: Decodable { let displayName: String; let buckets: [Bucket] }
    private struct Bucket: Decodable {
        let window: String
        let remainingFraction: Double?
        let resetTime: String?
    }

    static func parse(_ data: Data, now: Date = .now) throws -> UsageSnapshot {
        let response = try JSONDecoder().decode(Envelope.self, from: data).response
        var buckets: [UsageBucket] = []
        for group in response.groups.prefix(20) {
            let family: String
            let name: String
            switch group.displayName.lowercased() {
            case "gemini models": family = "gemini"; name = "Gemini · 7d"
            case "claude and gpt models": family = "claude-gpt"; name = "Claude/GPT · 7d"
            default: continue // Never silently attach a new group to a known pool.
            }
            guard !buckets.contains(where: { $0.id == family }) else { throw UsageProviderError.invalidResponse }
            let windows = group.buckets.filter { ["weekly", "5h"].contains($0.window) }
            guard Set(windows.map(\.window)).count == windows.count else { throw UsageProviderError.invalidResponse }
            let children = windows.map { value in
                UsageBucket(id: family + "-" + value.window, name: value.window == "weekly" ? "Weekly" : "5 Hours",
                            remainingFraction: QuotaParsing.fraction(value.remainingFraction),
                            resetsAt: QuotaParsing.date(value.resetTime),
                            period: value.window == "weekly" ? .weekly : .rolling(hours: 5))
            }
            // The overview reports the server's weekly pool, never an average of model values.
            let weekly = children.first(where: { $0.period == .weekly })
            buckets.append(UsageBucket(id: family, name: name, remainingFraction: weekly?.remainingFraction,
                                       resetsAt: weekly?.resetsAt, period: .quotaPool, children: children))
        }
        guard !buckets.isEmpty else { throw UsageProviderError.invalidResponse }
        return UsageSnapshot(provider: .antigravity, updatedAt: now, buckets: buckets, source: .localServer)
    }
}
