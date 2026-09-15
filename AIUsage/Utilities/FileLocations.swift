import Foundation

enum FileLocations {
    static var codexDirectory: URL {
        if let path = ProcessInfo.processInfo.environment["CODEX_HOME"], path.hasPrefix("/") {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex", isDirectory: true)
    }
}
