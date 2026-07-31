import Foundation
import ServiceManagement

enum QuicBlockError: LocalizedError {
    case registrationFailed(String)
    case installFailed(String)
    case removeFailed(String)
    case unavailable

    var errorDescription: String? {
        switch self {
        case .registrationFailed(let message):
            return "Could not register privileged helper: \(message)"
        case .installFailed(let message):
            return "Could not install QUIC block: \(message)"
        case .removeFailed(let message):
            return "Could not remove QUIC block: \(message)"
        case .unavailable:
            return "Privileged helper is unavailable."
        }
    }
}

/// XPC protocol shared with SpoofDPIHelper.
@objc protocol SpoofDPIHelperProtocol {
    func installQuicBlock(reply: @escaping (Bool, String) -> Void)
    func removeQuicBlock(reply: @escaping (Bool, String) -> Void)
    func quicBlockStatus(reply: @escaping (Bool, String) -> Void)
    func flushDNS(reply: @escaping (Bool, String) -> Void)
}

@MainActor
final class QuicBlockClient {
    static let machServiceName = "com.spoofdpi.menubar.helper"
    static let plistName = "com.spoofdpi.menubar.helper.plist"

    private var connection: NSXPCConnection?

    func ensureInstalled() async throws {
        try await registerHelperIfNeeded()
        let (ok, message) = try await call { remote, reply in
            remote.installQuicBlock(reply: reply)
        }
        if !ok {
            #if DEBUG
            try await installViaAppleScriptFallback()
            #else
            throw QuicBlockError.installFailed(message)
            #endif
        }
    }

    func remove() async throws {
        try await registerHelperIfNeeded()
        let (ok, message) = try await call { remote, reply in
            remote.removeQuicBlock(reply: reply)
        }
        if !ok {
            #if DEBUG
            try await removeViaAppleScriptFallback()
            #else
            throw QuicBlockError.removeFailed(message)
            #endif
        }
    }

    func status() async -> Bool {
        do {
            try await registerHelperIfNeeded()
            let (ok, _) = try await call { remote, reply in
                remote.quicBlockStatus(reply: reply)
            }
            return ok
        } catch {
            #if DEBUG
            return await debugPfStatus()
            #else
            return false
            #endif
        }
    }

    func flushDNSPrivileged() async throws {
        try await registerHelperIfNeeded()
        let (ok, message) = try await call { remote, reply in
            remote.flushDNS(reply: reply)
        }
        if !ok {
            throw QuicBlockError.installFailed(message)
        }
    }

    private func registerHelperIfNeeded() async throws {
        let service = SMAppService.daemon(plistName: Self.plistName)
        switch service.status {
        case .enabled:
            return
        case .requiresApproval:
            throw QuicBlockError.registrationFailed(
                "Enable SpoofDPI Helper in System Settings → General → Login Items & Extensions."
            )
        case .notFound:
            throw QuicBlockError.registrationFailed("Helper launchd plist was not found in the app bundle.")
        case .notRegistered:
            do {
                try service.register()
            } catch {
                #if DEBUG
                // Allow DEBUG osascript fallback without a signed helper.
                return
                #else
                throw QuicBlockError.registrationFailed(error.localizedDescription)
                #endif
            }
        @unknown default:
            return
        }
    }

    private func call(
        _ body: @escaping (SpoofDPIHelperProtocol, @escaping (Bool, String) -> Void) -> Void
    ) async throws -> (Bool, String) {
        let connection = try makeConnection()
        return try await withCheckedThrowingContinuation { continuation in
            guard let remote = connection.remoteObjectProxyWithErrorHandler({ error in
                continuation.resume(throwing: QuicBlockError.unavailable)
                _ = error
            }) as? SpoofDPIHelperProtocol else {
                continuation.resume(throwing: QuicBlockError.unavailable)
                return
            }
            body(remote) { ok, message in
                continuation.resume(returning: (ok, message))
            }
        }
    }

    private func makeConnection() throws -> NSXPCConnection {
        if let connection {
            return connection
        }
        let connection = NSXPCConnection(machServiceName: Self.machServiceName, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: SpoofDPIHelperProtocol.self)
        connection.resume()
        self.connection = connection
        return connection
    }

    #if DEBUG
    private func installViaAppleScriptFallback() async throws {
        let script = Self.pfInstallShellScript()
        let escaped = script.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let apple = "do shell script \"\(escaped)\" with administrator privileges"
        _ = try await Shell.runAsync("/usr/bin/osascript", arguments: ["-e", apple])
    }

    private func removeViaAppleScriptFallback() async throws {
        let script = Self.pfRemoveShellScript()
        let escaped = script.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let apple = "do shell script \"\(escaped)\" with administrator privileges"
        _ = try await Shell.runAsync("/usr/bin/osascript", arguments: ["-e", apple])
    }

    private func debugPfStatus() async -> Bool {
        let out = (try? await Shell.runAsync("/sbin/pfctl", arguments: ["-sr"], throwOnError: false)) ?? ""
        return out.contains("com.spoofdpi") || out.contains("port 443") && out.lowercased().contains("block")
    }

    private static func pfInstallShellScript() -> String {
        """
        mkdir -p /etc/pf.anchors
        printf '%s\\n' 'block drop quick proto udp from any to any port 443' > /etc/pf.anchors/com.spoofdpi.menubar
        if ! grep -q 'com.spoofdpi.quic' /etc/pf.conf; then
          printf '\\n# com.spoofdpi.quic\\nanchor \"com.spoofdpi.quic\"\\nload anchor \"com.spoofdpi.quic\" from \"/etc/pf.anchors/com.spoofdpi.menubar\"\\n' >> /etc/pf.conf
        fi
        pfctl -f /etc/pf.conf
        pfctl -e || true
        """
    }

    private static func pfRemoveShellScript() -> String {
        """
        rm -f /etc/pf.anchors/com.spoofdpi.menubar
        if [ -f /etc/pf.conf ]; then
          tmp=$(mktemp)
          awk 'BEGIN{skip=0} /# com.spoofdpi.quic/{skip=1} skip && /^load anchor \"com.spoofdpi.quic\"/{skip=0; next} skip && /^anchor \"com.spoofdpi.quic\"/{next} skip{next} {print}' /etc/pf.conf > \"$tmp\" && mv \"$tmp\" /etc/pf.conf
        fi
        pfctl -f /etc/pf.conf || true
        """
    }
    #endif
}
