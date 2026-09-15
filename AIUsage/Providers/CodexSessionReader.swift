import Foundation

actor CodexSessionReader {
    private let directory: URL
    private let maximumFiles: Int
    private let tailBytes: Int
    private var cache: [URL: CachedFile] = [:]

    init(directory: URL, maximumFiles: Int = 32, tailBytes: Int = 2 * 1_024 * 1_024) {
        self.directory = directory
        self.maximumFiles = max(1, maximumFiles)
        self.tailBytes = max(1, tailBytes)
    }

    func latestSnapshot() throws -> UsageSnapshot? {
        let files = try candidates()
        let activeURLs = Set(files.map(\.url))
        cache = cache.filter { activeURLs.contains($0.key) }
        var latest: UsageSnapshot?
        var readFailed = false
        var readSucceeded = false
        for file in files {
            try Task.checkCancellation()
            let snapshot: UsageSnapshot?
            if let cached = cache[file.url], cached.file == file {
                snapshot = cached.snapshot
                readSucceeded = true
            } else {
                do {
                    snapshot = try read(file)
                    cache[file.url] = CachedFile(file: file, snapshot: snapshot)
                    readSucceeded = true
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    // A disappearing/unreadable file doesn't prevent other sessions from loading.
                    cache[file.url] = nil
                    readFailed = true
                    continue
                }
            }
            if let snapshot, snapshot.updatedAt <= Date.now.addingTimeInterval(300),
               latest == nil || snapshot.updatedAt > latest!.updatedAt {
                latest = snapshot
            }
        }
        if !readSucceeded && readFailed { throw CocoaError(.fileReadNoPermission) }
        return latest
    }

    private func candidates() throws -> [SessionFile] {
        let manager = FileManager.default
        var isDirectory: ObjCBool = false
        guard manager.fileExists(atPath: directory.path, isDirectory: &isDirectory) else { return [] }
        guard isDirectory.boolValue else { throw CocoaError(.fileReadCorruptFile) }
        guard manager.isReadableFile(atPath: directory.path) else { throw CocoaError(.fileReadNoPermission) }
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey]
        guard let entries = manager.enumerator(at: directory, includingPropertiesForKeys: Array(keys),
                                              options: [.skipsHiddenFiles, .skipsPackageDescendants]) else {
            throw CocoaError(.fileReadNoPermission)
        }
        var files: [SessionFile] = []
        // Enumerate metadata only; never open auth/config/history or archive files.
        for case let url as URL in entries {
            try Task.checkCancellation()
            guard url.lastPathComponent.hasPrefix("rollout-"), url.pathExtension == "jsonl",
                  let values = try? url.resourceValues(forKeys: keys),
                  values.isRegularFile == true, values.isSymbolicLink != true,
                  let size = values.fileSize, let modified = values.contentModificationDate else { continue }
            files.append(SessionFile(url: url, size: size, modified: modified))
        }
        return Array(files.sorted {
            $0.modified == $1.modified ? $0.url.path < $1.url.path : $0.modified > $1.modified
        }.prefix(maximumFiles))
    }

    private func read(_ file: SessionFile) throws -> UsageSnapshot? {
        let handle = try FileHandle(forReadingFrom: file.url)
        defer { try? handle.close() }
        // Read the tail only, bounding memory and avoiding repeatedly decoding full conversations.
        let size = try handle.seekToEnd()
        let start = size > UInt64(tailBytes) ? size - UInt64(tailBytes) : 0
        try handle.seek(toOffset: start)
        let data = try handle.read(upToCount: tailBytes) ?? Data()
        var lines = data.split(separator: 0x0A, omittingEmptySubsequences: false)
        if start > 0 && !lines.isEmpty { lines.removeFirst() }
        // Only newline-terminated records are committed; a writer may still be appending the last line.
        if !lines.isEmpty { lines.removeLast() }
        var latest: UsageSnapshot?
        for line in lines.reversed() {
            try Task.checkCancellation()
            guard let snapshot = CodexUsageParser.snapshot(from: Data(line)) else { continue }
            if latest == nil || snapshot.updatedAt > latest!.updatedAt { latest = snapshot }
        }
        return latest
    }

    private struct SessionFile: Equatable {
        let url: URL
        let size: Int
        let modified: Date
    }

    private struct CachedFile {
        let file: SessionFile
        let snapshot: UsageSnapshot?
    }
}
