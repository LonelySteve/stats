import Foundation
import Security

public struct MihomoSubscription: Codable {
    public let upload: Int64
    public let download: Int64
    public let total: Int64
    public let expire: Int64

    private enum CodingKeys: String, CodingKey {
        case upload = "Upload", download = "Download", total = "Total", expire = "Expire"
    }

    public var used: Int64 { self.upload + self.download }
    public var usage: Double? { self.total > 0 ? Double(self.used) / Double(self.total) : nil }
    func menuBarPercentage(showUsed: Bool = false) -> Int? {
        guard let usage = self.usage else { return nil }
        let value = showUsed ? usage : max(0, 1 - usage)
        return Int((value * 100).rounded())
    }
    public var expirationDate: Date? {
        self.expire > 0 ? Date(timeIntervalSince1970: TimeInterval(self.expire)) : nil
    }
}

public struct MihomoProvider: Codable {
    public let name: String
    public let vehicleType: String
    public let proxyCount: Int
    public let subscriptionInfo: MihomoSubscription?
}

enum MihomoAPI {
    static let defaultAddress = "http://192.168.8.1:9090"
    static let defaultInterval = 1800

    private struct Response: Decodable {
        let providers: [String: Provider]
        struct Provider: Decodable {
            let vehicleType: String
            let proxies: [Proxy]
            let subscriptionInfo: MihomoSubscription?
        }
        struct Proxy: Decodable {}
    }

    enum APIError: LocalizedError {
        case invalidAddress, invalidResponse, http(Int)

        var errorDescription: String? {
            switch self {
            case .invalidAddress: return "Invalid mihomo API address"
            case .invalidResponse: return "Invalid mihomo API response"
            case .http(401), .http(403): return "Mihomo authentication failed; check the secret"
            case .http(let status): return "Mihomo API returned HTTP \(status)"
            }
        }
    }

    static func request(address: String, secret: String) throws -> URLRequest {
        guard let url = URL(string: address.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme, ["http", "https"].contains(scheme.lowercased()),
              url.host != nil else { throw APIError.invalidAddress }
        var request = URLRequest(url: url.appendingPathComponent("providers/proxies"),
                                 cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if !secret.isEmpty {
            request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    static func decode(_ data: Data) throws -> [MihomoProvider] {
        let response = try JSONDecoder().decode(Response.self, from: data)
        // Compatible providers are internal collections for direct proxies and policy groups.
        return response.providers.filter { $0.value.vehicleType != "Compatible" }.map { name, provider in
            MihomoProvider(name: name, vehicleType: provider.vehicleType,
                           proxyCount: provider.proxies.count, subscriptionInfo: provider.subscriptionInfo)
        }.sorted {
            if ($0.subscriptionInfo != nil) != ($1.subscriptionInfo != nil) {
                return $0.subscriptionInfo != nil
            }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    static func fetch(address: String, secret: String, session: URLSession = .shared) async throws -> [MihomoProvider] {
        let (data, response) = try await session.data(for: self.request(address: address, secret: secret))
        guard let response = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(response.statusCode) else { throw APIError.http(response.statusCode) }
        return try self.decode(data)
    }
}

enum MihomoKeychain {
    static let service = "eu.exelban.Stats.mihomo"
    private static var cachedResult: Result<String, Error>?
    private static let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: "secret"
    ]

    struct AccessError: LocalizedError {
        let status: OSStatus
        var errorDescription: String? {
            "Could not read secret; click Read secret in Mihomo settings to authorize Keychain access"
        }
    }

    static func read(allowInteraction: Bool = false) throws -> String {
        if !allowInteraction, let result = self.cachedResult { return try result.get() }
        let result = Result { try self.load(allowInteraction: allowInteraction) }
        self.cachedResult = result
        return try result.get()
    }

    private static func load(allowInteraction: Bool) throws -> String {
        // SecItem targets the file-based macOS keychain; its UI must be disabled here.
        var previousInteraction: DarwinBoolean = false
        var status = SecKeychainGetUserInteractionAllowed(&previousInteraction)
        guard status == errSecSuccess else { throw AccessError(status: status) }
        status = SecKeychainSetUserInteractionAllowed(allowInteraction)
        guard status == errSecSuccess else { throw AccessError(status: status) }
        defer { SecKeychainSetUserInteractionAllowed(previousInteraction.boolValue) }

        var query = self.query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return "" }
        guard status == errSecSuccess else { throw AccessError(status: status) }
        guard let data = item as? Data, let secret = String(data: data, encoding: .utf8) else {
            throw AccessError(status: errSecDecode)
        }
        return secret
    }

    static func write(_ secret: String) -> OSStatus {
        var status: OSStatus
        if secret.isEmpty {
            status = SecItemDelete(self.query as CFDictionary)
            if status == errSecItemNotFound { status = errSecSuccess }
        } else {
            let attributes: [String: Any] = [kSecValueData as String: Data(secret.utf8)]
            status = SecItemUpdate(self.query as CFDictionary, attributes as CFDictionary)
            if status == errSecItemNotFound {
                status = SecItemAdd(self.query.merging(attributes) { _, new in new } as CFDictionary, nil)
            }
        }
        if status == errSecSuccess { self.cachedResult = .success(secret) }
        return status
    }
}
