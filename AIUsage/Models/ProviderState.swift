import Foundation

enum ProviderState: Equatable, Sendable {
    case loading
    case loaded(UsageSnapshot)
    case unavailable
    case error(String)

    var snapshot: UsageSnapshot? {
        guard case .loaded(let snapshot) = self else { return nil }
        return snapshot
    }

    var statusLabel: String {
        switch self {
        case .loading: "Loading"
        case .loaded(let snapshot): snapshot.source.label
        case .unavailable: "Unavailable"
        case .error: "Couldn’t refresh"
        }
    }
}
