import Foundation

enum ProviderType: String, CaseIterable, Identifiable, Sendable {
    case codex, claude, antigravity

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .codex: "Codex"
        case .claude: "Claude"
        case .antigravity: "Antigravity"
        }
    }
}
