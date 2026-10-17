import Foundation
import Security

/// Decides when Broccoli asks the keychain for the clipboard key. The keychain can wait on a
/// permission prompt, so there is only one request at a time, and a refused or failed request
/// is not repeated on every settings change, which would bring the prompt back each time.
/// Turning clipboard history off and on again asks once more.
struct ClipboardKeyRequestGate {
    private(set) var isRequesting = false
    private(set) var hasFailed = false

    /// Whether to ask the keychain now. Turning history off clears an earlier failure.
    mutating func beginRequest(historyEnabled: Bool, historyRunning: Bool) -> Bool {
        guard historyEnabled else {
            hasFailed = false
            return false
        }
        guard !historyRunning, !isRequesting, !hasFailed else { return false }
        isRequesting = true
        return true
    }

    mutating func finish(succeeded: Bool) {
        isRequesting = false
        hasFailed = !succeeded
    }
}

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
