import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum UsageDisplay: String, CaseIterable, Identifiable {
    case used, remaining
    var id: String { rawValue }
    var title: String { self == .used ? "Used %" : "Remaining %" }
    func fraction(for bucket: UsageBucket) -> Double? {
        self == .used ? bucket.resolvedUsedFraction : bucket.resolvedRemainingFraction
    }
}


enum AppPreferences {
    static func migrateRemainingDisplay(defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: "remainingDisplayMigrationV1") else { return }
        defaults.set(UsageDisplay.remaining.rawValue, forKey: "usageDisplay")
        defaults.set(true, forKey: "remainingDisplayMigrationV1")
    }
}
