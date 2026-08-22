import Foundation
import Security

enum ClipboardKeyProvider {
    private static let service = "dev.gauravpandey.broccoli.clipboard"
    private static let account = "history-encryption-key-v1"

    static func loadOrCreate() throws -> Data {
        if let data = try load(service: service) {
            return data
        }
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(errSecAllocate))
        }
        let data = Data(bytes)
        try add(data, service: service)
        return data
    }

    private static func load(service: String) throws -> Data? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess {
            guard let data = result as? Data, data.count == 32 else {
                throw NSError(domain: NSOSStatusErrorDomain, code: Int(errSecDecode))
            }
            return data
        }
        guard status == errSecItemNotFound else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
        return nil
    }

    private static func add(_ data: Data, service: String) throws {
        let add: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData: data,
        ]
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(addStatus))
        }
    }
}
