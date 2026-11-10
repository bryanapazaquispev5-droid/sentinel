import Foundation
import Security
#if DEBUG
import CryptoKit
#endif

enum KeychainStore {
    private static let service = "com.sentinel.app"
    private static let account = "access-token"
    #if DEBUG
    // Solo para builds DEBUG instalados sin firma en el simulador. Se guarda cifrado para poder restaurar la sesión.
    private static var debugInMemoryToken: String?
    private static let debugFallbackKey = "sentinel.debug.encrypted-session"
    private static let debugEncryptionKey = SymmetricKey(data: SHA256.hash(data: Data("sentinel-local-debug-session-key".utf8)))
    #endif

    static func saveToken(_ token: String) throws {
        let data = Data(token.utf8)
        let identity: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let updateStatus = SecItemUpdate(identity as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        if updateStatus == errSecMissingEntitlement {
            #if DEBUG
            saveDebugFallback(token)
            return
            #else
            throw KeychainError.saveFailed(updateStatus)
            #endif
        }
        guard updateStatus == errSecItemNotFound else { throw KeychainError.saveFailed(updateStatus) }

        var addQuery = identity
        attributes.forEach { addQuery[$0.key] = $0.value }
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus == errSecDuplicateItem {
            let retryStatus = SecItemUpdate(identity as CFDictionary, attributes as CFDictionary)
            if retryStatus == errSecMissingEntitlement {
                #if DEBUG
                saveDebugFallback(token)
                return
                #else
                throw KeychainError.saveFailed(retryStatus)
                #endif
            }
            guard retryStatus == errSecSuccess else { throw KeychainError.saveFailed(retryStatus) }
        } else if addStatus == errSecMissingEntitlement {
            #if DEBUG
            saveDebugFallback(token)
            return
            #else
            throw KeychainError.saveFailed(addStatus)
            #endif
        } else if addStatus != errSecSuccess {
            throw KeychainError.saveFailed(addStatus)
        }
    }

    static func readToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            #if DEBUG
            if status == errSecMissingEntitlement || status == errSecItemNotFound { return readDebugFallback() }
            #endif
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    static func deleteToken() {
        #if DEBUG
        debugInMemoryToken = nil
        UserDefaults.standard.removeObject(forKey: debugFallbackKey)
        #endif
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
    }

    #if DEBUG
    private static func saveDebugFallback(_ token: String) {
        debugInMemoryToken = token
        guard let sealedBox = try? AES.GCM.seal(Data(token.utf8), using: debugEncryptionKey), let combined = sealedBox.combined else { return }
        UserDefaults.standard.set(combined.base64EncodedString(), forKey: debugFallbackKey)
    }

    private static func readDebugFallback() -> String? {
        if let debugInMemoryToken { return debugInMemoryToken }
        guard let encoded = UserDefaults.standard.string(forKey: debugFallbackKey), let combined = Data(base64Encoded: encoded), let sealedBox = try? AES.GCM.SealedBox(combined: combined), let data = try? AES.GCM.open(sealedBox, using: debugEncryptionKey), let token = String(data: data, encoding: .utf8) else { return nil }
        debugInMemoryToken = token
        return token
    }
    #endif
}

enum KeychainError: LocalizedError {
    case saveFailed(OSStatus)

    var errorDescription: String? {
        switch self { case .saveFailed(let status): return "No se pudo guardar la sesión segura (código \(status))." }
    }
}
