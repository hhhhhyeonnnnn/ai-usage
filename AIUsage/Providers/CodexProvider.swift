import Foundation

struct CodexProvider: UsageProvider {
    let id = ProviderType.codex
    private let reader: CodexSessionReader

    init(codexDirectory: URL = FileLocations.codexDirectory) {
        reader = CodexSessionReader(directory: codexDirectory.appendingPathComponent("sessions", isDirectory: true))
    }

    func fetchUsage() async throws -> UsageSnapshot {
        guard let snapshot = try await reader.latestSnapshot(), !snapshot.buckets.isEmpty else {
            throw UsageProviderError.unavailable
        }
        return snapshot
    }
}
