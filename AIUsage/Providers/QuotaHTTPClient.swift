import Foundation

/// Ephemeral requests; never follow redirects with authentication attached.
final class QuotaHTTPClient: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }

    func data(for request: URLRequest) async throws -> Data {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 15
        configuration.connectionProxyDictionary = [:]
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw UsageProviderError.invalidResponse }
        switch http.statusCode {
        case 200: break
        case 401, 403: throw UsageProviderError.signInRequired
        case 429: throw UsageProviderError.rateLimited
        default: throw UsageProviderError.unavailable
        }
        guard response.expectedContentLength <= 2_000_000 else { throw UsageProviderError.invalidResponse }
        var data = Data()
        for try await byte in bytes {
            guard data.count < 2_000_000 else { throw UsageProviderError.invalidResponse }
            data.append(byte)
        }
        return data
    }
}

enum QuotaParsing {
    static func date(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    static func fraction(_ value: Double?, scale: Double = 1) -> Double? {
        guard let value, value.isFinite, value >= 0, value <= scale else { return nil }
        return value / scale
    }
}
