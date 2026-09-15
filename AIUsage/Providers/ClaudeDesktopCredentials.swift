import Foundation
import Security
import CommonCrypto
import SQLite3

/// Reads only Claude's own two authentication cookies; never browser profiles or chat history.
struct ClaudeDesktopCredentials: Sendable {
    let sessionKey: String
    let organization: String

    static func read(directory: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Claude", isDirectory: true)) throws -> Self {
        let path = directory.appendingPathComponent("Cookies").path
        guard FileManager.default.fileExists(atPath: path) else { throw UsageProviderError.signInRequired }
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            if db != nil { sqlite3_close(db) }
            throw UsageProviderError.signInRequired
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 500)
        var versionStatement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT value FROM meta WHERE key='version'", -1, &versionStatement, nil) == SQLITE_OK else {
            throw UsageProviderError.invalidResponse
        }
        defer { sqlite3_finalize(versionStatement) }
        guard sqlite3_step(versionStatement) == SQLITE_ROW else { throw UsageProviderError.invalidResponse }
        let hasDomainHash = sqlite3_column_int(versionStatement, 0) >= 24
        var statement: OpaquePointer?
        // Prefer recently used cookies if both host forms exist. No plaintext copies of the DB.
        let query = "SELECT name,encrypted_value,host_key FROM cookies WHERE host_key IN ('.claude.ai','claude.ai') AND name IN ('sessionKey','lastActiveOrg') AND (expires_utc=0 OR expires_utc > ?) ORDER BY last_access_utc DESC"
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else { throw UsageProviderError.invalidResponse }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, Int64((Date.now.timeIntervalSince1970 + 11_644_473_600) * 1_000_000))
        let key = try ClaudeCookieCrypto.key(password: safeStoragePassword())
        var cookies: [String: String] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let namePointer = sqlite3_column_text(statement, 0),
                  let hostPointer = sqlite3_column_text(statement, 2),
                  let bytes = sqlite3_column_blob(statement, 1) else { continue }
            let name = String(cString: namePointer)
            let host = String(cString: hostPointer)
            let length = Int(sqlite3_column_bytes(statement, 1))
            guard cookies[name] == nil, length > 3, length < 16_384 else { continue }
            let encrypted = Data(bytes: bytes, count: length)
            cookies[name] = try? ClaudeCookieCrypto.decrypt(encrypted, key: key, host: host, hasDomainHash: hasDomainHash)
        }
        guard let session = cookies["sessionKey"], validSession(session),
              let org = cookies["lastActiveOrg"], let uuid = UUID(uuidString: org) else { throw UsageProviderError.signInRequired }
        return Self(sessionKey: session, organization: uuid.uuidString.lowercased())
    }

    static func validSession(_ value: String) -> Bool {
        !value.isEmpty && value.count < 8192 && value.allSatisfy {
            $0.isASCII && ($0.isLetter || $0.isNumber || "-_".contains($0))
        }
    }

    private static func safeStoragePassword() throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Safe Storage",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let password = result as? Data, !password.isEmpty else { throw UsageProviderError.keychainRequired }
        return password
    }
}

enum ClaudeCookieCrypto {
    static func key(password: Data) throws -> Data {
        guard !password.isEmpty else { throw UsageProviderError.signInRequired }
        var key = [UInt8](repeating: 0, count: 16)
        let salt = Array("saltysalt".utf8)
        let status = password.withUnsafeBytes { p in
            salt.withUnsafeBufferPointer { s in
                CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), p.baseAddress!.assumingMemoryBound(to: CChar.self),
                                    password.count, s.baseAddress, salt.count,
                                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1), 1003, &key, key.count)
            }
        }
        guard status == kCCSuccess else { throw UsageProviderError.signInRequired }
        return Data(key)
    }

    static func decrypt(_ encrypted: Data, key: Data, host: String, hasDomainHash: Bool) throws -> String {
        guard ["claude.ai", ".claude.ai"].contains(host), key.count == 16,
              encrypted.starts(with: Data("v10".utf8)), encrypted.count > 3,
              encrypted.count < 16_384 else { throw UsageProviderError.signInRequired }
        let body = Data(encrypted.dropFirst(3))
        var output = [UInt8](repeating: 0, count: body.count + 16)
        let capacity = output.count
        var written = 0
        let iv = [UInt8](repeating: 32, count: 16)
        let status = body.withUnsafeBytes { p in
            key.withUnsafeBytes { k in
                iv.withUnsafeBytes { i in
                    CCCrypt(CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding),
                            k.baseAddress, 16, i.baseAddress, p.baseAddress, body.count, &output, capacity, &written)
                }
            }
        }
        guard status == kCCSuccess else { throw UsageProviderError.signInRequired }
        var plain = Data(output.prefix(written))
        if hasDomainHash {
            let domain = Data(host.utf8)
            var hash = [UInt8](repeating: 0, count: 32)
            domain.withUnsafeBytes { _ = CC_SHA256($0.baseAddress, CC_LONG(domain.count), &hash) }
            guard plain.starts(with: Data(hash)) else { throw UsageProviderError.signInRequired }
            plain = Data(plain.dropFirst(32))
        }
        guard let value = String(data: plain, encoding: .utf8) else { throw UsageProviderError.signInRequired }
        return value
    }
}
