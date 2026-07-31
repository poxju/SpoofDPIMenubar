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
        do {
            try await registerHelperIfNeeded()
            let (ok, message) = try await call { remote, reply in
                remote.installQuicBlock(reply: reply)
            }
            if ok { return }
            throw QuicBlockError.installFailed(message)
        } catch {
            // Unsigned / non–Developer ID builds can't register the LaunchDaemon; fall back to admin prompt.
            try await installViaAppleScriptFallback()
        }
    }

    func remove() async throws {
        do {
            try await registerHelperIfNeeded()
            let (ok, message) = try await call { remote, reply in
                remote.removeQuicBlock(reply: reply)
            }
            if ok { return }
            throw QuicBlockError.removeFailed(message)
        } catch {
            try await removeViaAppleScriptFallback()
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
            return await pfStatusProbe()
        }
    }

    func flushDNSPrivileged() async throws {
        do {
            try await registerHelperIfNeeded()
            let (ok, message) = try await call { remote, reply in
                remote.flushDNS(reply: reply)
            }
            if ok { return }
            throw QuicBlockError.installFailed(message)
        } catch {
            try await flushDNSViaAppleScriptFallback()
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
            try service.register()
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

    private func installViaAppleScriptFallback() async throws {
        try await runAdminShell(Self.pfInstallShellScript())
    }

    private func removeViaAppleScriptFallback() async throws {
        try await runAdminShell(Self.pfRemoveShellScript())
    }

    private func flushDNSViaAppleScriptFallback() async throws {
        try await runAdminShell("dscacheutil -flushcache; killall -HUP mDNSResponder")
    }

    private func runAdminShell(_ script: String) async throws {
        let escaped = script
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let apple = "do shell script \"\(escaped)\" with administrator privileges"
        _ = try await Shell.runAsync("/usr/bin/osascript", arguments: ["-e", apple])
    }

    private func pfStatusProbe() async -> Bool {
        let out = (try? await Shell.runAsync("/sbin/pfctl", arguments: ["-sr"], throwOnError: false)) ?? ""
        return out.contains("com.spoofdpi") || (out.contains("port 443") && out.lowercased().contains("block"))
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
}
