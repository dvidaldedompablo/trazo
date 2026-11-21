import Foundation
import Security

/// La clave de Gemini, guardada en el llavero de iOS (Keychain).
///
/// CLAUDE.md: la clave del modelo externo la escribe el usuario en Ajustes y va al llavero, nunca al
/// código, al repositorio ni a UserDefaults. El llavero la guarda cifrada y solo esta app puede leerla.
/// `WhenUnlockedThisDeviceOnly`: solo con el iPhone desbloqueado y sin salir de él en las copias.
enum KeychainStore {
    private static let service = "io.github.dvidaldedompablo.trazo.gemini"
    private static let account = "api-key"

    /// La clave guardada, o `nil` si no hay.
    static var geminiKey: String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data, let key = String(data: data, encoding: .utf8), !key.isEmpty
        else { return nil }
        return key
    }

    /// Guarda la clave (sustituye la anterior). Devuelve si se ha podido guardar.
    @discardableResult
    static func saveGeminiKey(_ key: String) -> Bool {
        deleteGeminiKey()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(key.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    static func deleteGeminiKey() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
