import Foundation
import Network

@MainActor
final class PACServer {
    static let host = "127.0.0.1"
    static let port: UInt16 = 8091
    static var pacURL: URL {
        URL(string: "http://\(host):\(port)/pac")!
    }

    private var listener: NWListener?
    private let proxyHost: String
    private let proxyPort: UInt16

    init(proxyHost: String = "127.0.0.1", proxyPort: UInt16 = 8080) {
        self.proxyHost = proxyHost
        self.proxyPort = proxyPort
    }

    var isRunning: Bool { listener != nil }

    func start() async throws {
        if listener != nil { return }

        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        let listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: Self.port)!)

        let proxyHost = self.proxyHost
        let proxyPort = self.proxyPort
        listener.newConnectionHandler = { connection in
            Self.handleConnection(connection, proxyHost: proxyHost, proxyPort: proxyPort)
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let box = ResumeBox()
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    box.resumeIfNeeded { continuation.resume() }
                case .failed(let error):
                    box.resumeIfNeeded { continuation.resume(throwing: error) }
                default:
                    break
                }
            }
            listener.start(queue: .global(qos: .userInitiated))
        }

        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    nonisolated private static func handleConnection(
        _ connection: NWConnection,
        proxyHost: String,
        proxyPort: UInt16
    ) {
        connection.start(queue: .global(qos: .userInitiated))
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, _, _ in
            let request = String(data: data ?? Data(), encoding: .utf8) ?? ""
            let path = requestPath(from: request)
            let response: Data
            if path == "/pac" || path.hasPrefix("/pac?") {
                let body = pacScript(proxyHost: proxyHost, proxyPort: proxyPort)
                let header = """
                HTTP/1.1 200 OK\r
                Content-Type: application/x-ns-proxy-autoconfig\r
                Content-Length: \(body.utf8.count)\r
                Connection: close\r
                \r

                """
                response = Data((header + body).utf8)
            } else {
                let body = "Not Found"
                let header = """
                HTTP/1.1 404 Not Found\r
                Content-Type: text/plain\r
                Content-Length: \(body.utf8.count)\r
                Connection: close\r
                \r

                """
                response = Data((header + body).utf8)
            }
            connection.send(content: response, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }

    nonisolated private static func pacScript(proxyHost: String, proxyPort: UInt16) -> String {
        """
        function FindProxyForURL(url, host) {
            if (isPlainHostName(host) ||
                shExpMatch(host, "*.local") ||
                isInNet(dnsResolve(host), "127.0.0.0", "255.0.0.0") ||
                isInNet(dnsResolve(host), "10.0.0.0", "255.0.0.0") ||
                isInNet(dnsResolve(host), "172.16.0.0", "255.240.0.0") ||
                isInNet(dnsResolve(host), "192.168.0.0", "255.255.0.0") ||
                isInNet(dnsResolve(host), "169.254.0.0", "255.255.0.0")) {
                return "DIRECT";
            }
            return "PROXY \(proxyHost):\(proxyPort)";
        }
        """
    }

    nonisolated private static func requestPath(from request: String) -> String {
        let firstLine = request.split(separator: "\r\n", maxSplits: 1).first ?? Substring()
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2 else { return "/" }
        return String(parts[1])
    }
}

private final class ResumeBox: @unchecked Sendable {
    private let lock = NSLock()
    private var resumed = false

    func resumeIfNeeded(_ body: () -> Void) {
        lock.lock()
        let shouldRun = !resumed
        if shouldRun { resumed = true }
        lock.unlock()
        if shouldRun { body() }
    }
}
