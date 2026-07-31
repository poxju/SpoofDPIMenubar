import Foundation

struct ProxyTestResult: Equatable {
    var ok: Bool
    var httpCode: Int
    var url: String
    var message: String
}

enum ProxyHealth {
    static func test(
        url: URL = URL(string: "https://discord.com")!,
        proxyHost: String = "127.0.0.1",
        proxyPort: UInt16 = 8080
    ) async -> ProxyTestResult {
        let config = URLSessionConfiguration.ephemeral
        config.connectionProxyDictionary = [
            kCFNetworkProxiesHTTPEnable as String: true,
            kCFNetworkProxiesHTTPProxy as String: proxyHost,
            kCFNetworkProxiesHTTPPort as String: NSNumber(value: proxyPort),
            kCFNetworkProxiesHTTPSEnable as String: true,
            kCFNetworkProxiesHTTPSProxy as String: proxyHost,
            kCFNetworkProxiesHTTPSPort as String: NSNumber(value: proxyPort)
        ]
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 20

        let session = URLSession(configuration: config)
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"

        do {
            let (_, response) = try await session.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let ok = (200...399).contains(code)
            return ProxyTestResult(
                ok: ok,
                httpCode: code,
                url: url.absoluteString,
                message: ok ? "\(url.host ?? url.absoluteString) OK (\(code))" : "\(url.host ?? url.absoluteString) failed (\(code))"
            )
        } catch {
            let out = (try? await Shell.runAsync("/usr/bin/curl", arguments: [
                "-s", "-o", "/dev/null", "-w", "%{http_code}",
                "-x", "http://\(proxyHost):\(proxyPort)",
                "--max-time", "20",
                url.absoluteString
            ], throwOnError: false)) ?? "000"
            let code = Int(out.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            let ok = (200...399).contains(code)
            return ProxyTestResult(
                ok: ok,
                httpCode: code,
                url: url.absoluteString,
                message: ok
                    ? "\(url.host ?? url.absoluteString) OK (\(code))"
                    : "\(url.host ?? url.absoluteString) failed (\(code == 0 ? "no response" : String(code)))"
            )
        }
    }
}
