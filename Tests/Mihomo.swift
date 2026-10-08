import Foundation

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
}

private final class ProviderProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data))!
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, data) = try Self.handler(self.request)
            let response = HTTPURLResponse(url: self.request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: data)
            self.client?.urlProtocolDidFinishLoading(self)
        } catch {
            self.client?.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() {}
}

@main
struct MihomoTests {
    static func main() async throws {
        let fixture = Data(#"""
        {"providers": {
            "subscription": {"vehicleType":"HTTP","proxies":[{"name":"node 1"},{"name":"node 2"}],
                "subscriptionInfo":{"Upload":1073741824,"Download":2147483648,"Total":4294967296,"Expire":1793593429}},
            "same-subscription": {"vehicleType":"HTTP","proxies":[{"name":"node 1"}],
                "subscriptionInfo":{"Upload":1073741824,"Download":2147483648,"Total":4294967296,"Expire":1793593429}},
            "inline": {"vehicleType":"Inline","proxies":[]},
            "local-file": {"vehicleType":"File","proxies":[]},
            "without-quota": {"vehicleType":"HTTP","proxies":[]},
            "unknown-quota": {"vehicleType":"HTTP","proxies":[],
                "subscriptionInfo":{"Upload":0,"Download":0,"Total":0,"Expire":0}},
            "default": {"vehicleType":"Compatible","proxies":[{"name":"DIRECT"}]},
            "strategy-group": {"vehicleType":"Compatible","proxies":[{"name":"node 1"}]}
        }}
        """#.utf8)
        let providers = try MihomoAPI.decode(fixture)
        expect(providers.count == 6, "Only configured providers must remain in the list")
        expect(!providers.contains { $0.vehicleType == "Compatible" }, "Internal default and strategy-group collections must be excluded")
        expect(providers.contains { $0.name == "same-subscription" }, "Distinct provider names must remain separate even when they share subscription metadata")
        let subscription = providers.first { $0.name == "subscription" }!
        expect(subscription.proxyCount == 2, "Proxy count comes from the API list")
        expect(subscription.subscriptionInfo?.used == 3221225472, "Used quota includes upload and download")
        expect(subscription.subscriptionInfo?.usage == 0.75, "Used quota is divided by total")
        expect(subscription.subscriptionInfo?.menuBarPercentage() == 25, "Menu bar defaults to remaining quota")
        expect(subscription.subscriptionInfo?.menuBarPercentage(showUsed: true) == 75, "Inversion displays used quota")
        expect(subscription.subscriptionInfo?.expirationDate?.timeIntervalSince1970 == 1793593429, "Expire is a Unix timestamp in seconds")
        expect(providers.first { $0.name == "inline" }?.subscriptionInfo == nil, "Missing subscription is not zero usage")
        expect(providers.contains { $0.name == "local-file" }, "Configured File providers must remain visible")
        expect(providers.contains { $0.name == "without-quota" }, "HTTP providers without subscription metadata must remain visible")
        let unknown = providers.first { $0.name == "unknown-quota" }!.subscriptionInfo!
        expect(unknown.usage == nil && unknown.expirationDate == nil, "Zero total/expiry must be shown as unavailable")
        expect(unknown.menuBarPercentage() == nil && unknown.menuBarPercentage(showUsed: true) == nil,
               "Unknown total must not appear as 100% remaining or 0% used")
        for (download, remaining, used) in [(Int64(0), 100, 0), (1024, 0, 100), (1280, 0, 125)] {
            let quota = try JSONDecoder().decode(MihomoSubscription.self, from: Data("{\"Upload\":0,\"Download\":\(download),\"Total\":1024,\"Expire\":0}".utf8))
            expect(quota.menuBarPercentage() == remaining, "Remaining quota handles unused and exhausted subscriptions")
            expect(quota.menuBarPercentage(showUsed: true) == used, "Used quota preserves actual consumption including overages")
        }
        let empty = try MihomoAPI.decode(Data(#"{"providers":{}}"#.utf8))
        expect(empty.isEmpty, "An empty provider list is valid")
        let compatibleOnly = try MihomoAPI.decode(Data(#"{"providers":{"default":{"vehicleType":"Compatible","proxies":[]}}}"#.utf8))
        expect(compatibleOnly.isEmpty, "An API containing only internal collections has no configured providers")
        expect(MihomoAPI.defaultInterval == 1800, "Default polling is thirty minutes")

        let request = try MihomoAPI.request(address: "http://localhost:9090/", secret: "test-secret")
        expect(request.url?.path == "/providers/proxies", "Trailing slash must not change the endpoint")
        expect(request.httpMethod == "GET", "Provider reads must use GET")
        expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-secret", "Secret uses Bearer authentication")
        let anonymous = try MihomoAPI.request(address: "https://localhost:9090", secret: "")
        expect(anonymous.value(forHTTPHeaderField: "Authorization") == nil, "Secretless APIs omit the authorization header")
        do {
            _ = try MihomoAPI.request(address: "localhost:9090", secret: "")
            preconditionFailure("An invalid address must fail")
        } catch MihomoAPI.APIError.invalidAddress {}

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ProviderProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        ProviderProtocol.handler = { request in
            expect(request.url?.path == "/providers/proxies", "Fetch must use the provider endpoint")
            expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-secret", "Fetch must authenticate")
            return (200, fixture)
        }
        let fetched = try await MihomoAPI.fetch(address: "http://localhost:9090", secret: "test-secret", session: session)
        expect(fetched.count == 6,
               "A successful response must expose providers")
        ProviderProtocol.handler = { _ in (401, Data(#"{"message":"Unauthorized"}"#.utf8)) }
        do {
            _ = try await MihomoAPI.fetch(address: "http://localhost:9090", secret: "test-secret", session: session)
            preconditionFailure("Unauthorized responses must fail")
        } catch MihomoAPI.APIError.http(let status) { expect(status == 401, "HTTP status must be retained") }
        ProviderProtocol.handler = { _ in throw URLError(.timedOut) }
        do {
            _ = try await MihomoAPI.fetch(address: "http://localhost:9090", secret: "test-secret", session: session)
            preconditionFailure("Network failures must not appear as empty provider lists")
        } catch let error as URLError { expect(error.code == .timedOut, "Network errors must be retained") }

        if let path = CommandLine.arguments.dropFirst().first {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            let actual = try MihomoAPI.decode(data)
            let raw = (try JSONSerialization.jsonObject(with: data) as! [String: Any])["providers"] as! [String: [String: Any]]
            let configured = raw.filter { $0.value["vehicleType"] as? String != "Compatible" }
            expect(!actual.isEmpty, "The live response must decode")
            expect(Set(actual.map(\.name)) == Set(configured.keys), "Live response must expose configured provider names only")
            for provider in actual {
                if let info = configured[provider.name]?["subscriptionInfo"] as? [String: Any],
                   let expire = info["Expire"] as? NSNumber {
                    expect(provider.subscriptionInfo?.expire == expire.int64Value, "Live expiration must match the provider's API value")
                }
            }
            print("Live response: \(raw.count) API entries -> \(actual.count) configured providers, \(actual.filter { $0.subscriptionInfo?.expirationDate != nil }.count) expiration dates")
        }
        print("Mihomo API contract tests passed")
    }
}
