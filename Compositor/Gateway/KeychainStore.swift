import Foundation
import Security

/// Stores API keys in the macOS Keychain, never in plaintext.
final class KeychainStore {
    static let shared = KeychainStore()
    
    private let service = "com.compositor.gateway"
    
    private init() {}
    
    /// Stores an API key for a channel, replacing any existing key.
    func store(key: String, for channelID: UUID) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: channelID.uuidString
        ]
        
        guard let data = key.data(using: .utf8) else {
            throw KeychainError.storeFailed(errSecParam)
        }
        
        // Update in place when a key already exists. Deleting first and re-adding would drop the stored key
        // outright if the add then failed.
        let updated = SecItemUpdate(query as CFDictionary,
                                    [kSecValueData as String: data] as CFDictionary)
        if updated == errSecSuccess { return }
        guard updated == errSecItemNotFound else {
            throw KeychainError.storeFailed(updated)
        }
        
        // No existing item: add a fresh one.
        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.storeFailed(status)
        }
    }
    
    /// Retrieves the API key for a channel, or nil if not found.
    func retrieve(for channelID: UUID) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: channelID.uuidString,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        switch status {
        case errSecSuccess:
            guard let data = result as? Data, let key = String(data: data, encoding: .utf8) else {
                throw KeychainError.decodeFailed
            }
            return key
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.retrieveFailed(status)
        }
    }
    
    /// Deletes the API key for a channel.
    func delete(for channelID: UUID) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: channelID.uuidString
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }
    
    /// Returns the last 4 characters of a key for display, or "••••" if not found.
    func displayKey(for channelID: UUID) -> String {
        guard let key = try? retrieve(for: channelID), key.count >= 4 else {
            return "••••"
        }
        return String(key.suffix(4))
    }
}

enum KeychainError: Error, LocalizedError {
    case storeFailed(OSStatus)
    case retrieveFailed(OSStatus)
    case deleteFailed(OSStatus)
    case decodeFailed
    
    var errorDescription: String? {
        switch self {
        case .storeFailed(let status):
            return "Failed to store key in Keychain (status: \(status))"
        case .retrieveFailed(let status):
            return "Failed to retrieve key from Keychain (status: \(status))"
        case .deleteFailed(let status):
            return "Failed to delete key from Keychain (status: \(status))"
        case .decodeFailed:
            return "Failed to decode key from Keychain"
        }
    }
}
