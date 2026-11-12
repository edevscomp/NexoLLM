import Foundation
import Security

/// Versions before 0.8 could use a cloud provider with the user's own API key. Every suggestion is now
/// computed on this computer only, so any key those versions stored is deleted from the Keychain, once.
enum LegacyCleanup {
    private static let doneKey = "cleanup.cloudKeysRemoved"

    static func removeCloudKeysOnce() {
        let d = UserDefaults.standard
        guard !d.bool(forKey: doneKey) else { return }
        d.set(true, forKey: doneKey)
        for provider in ["openAI", "anthropic", "gemini", "compatible"] {
            let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: Brand.bundleID,
                                    kSecAttrAccount as String: "api-key-\(provider)"]
            if SecItemDelete(q as CFDictionary) == errSecSuccess { Log.info("cleanup: removed a stored cloud API key") }
            d.removeObject(forKey: "cloud.verified.\(provider)")
        }
    }
}
