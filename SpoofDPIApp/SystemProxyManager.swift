import Foundation

struct ProxyServiceState: Equatable {
    var enabled: Bool
    var server: String
    var port: Int
}

struct AutoProxyState: Equatable {
    var enabled: Bool
    var url: String
}

struct NetworkServiceProxySnapshot: Equatable {
    var service: String
    var web: ProxyServiceState
    var secure: ProxyServiceState
    var auto: AutoProxyState
    var bypass: String
}

enum SystemProxyError: LocalizedError {
    case noActiveService
    case applyFailed(String)

    var errorDescription: String? {
        switch self {
        case .noActiveService:
            return "Could not determine the active network service."
        case .applyFailed(let message):
            return message
        }
    }
}

@MainActor
final class SystemProxyManager {
    private let networksetup = "/usr/sbin/networksetup"
    private var snapshot: [NetworkServiceProxySnapshot] = []

    var hasSnapshot: Bool { !snapshot.isEmpty }

    func capture() async throws -> [NetworkServiceProxySnapshot] {
        let services = try await listNetworkServices()
        var result: [NetworkServiceProxySnapshot] = []
        for service in services {
            let web = try await getWebProxy(service: service)
            let secure = try await getSecureProxy(service: service)
            let auto = try await getAutoProxy(service: service)
            let bypass = try await getBypass(service: service)
            result.append(
                NetworkServiceProxySnapshot(
                    service: service,
                    web: web,
                    secure: secure,
                    auto: auto,
                    bypass: bypass
                )
            )
        }
        snapshot = result
        return result
    }

    func apply(
        address: String,
        port: UInt16,
        pacURL: URL
    ) async throws {
        let active = try await activeNetworkService()
        if snapshot.isEmpty {
            _ = try await capture()
        }

        // Clear stale SpoofDPI proxies on inactive services.
        for entry in snapshot where entry.service != active {
            if isOurProxy(entry.web, address: address, port: port)
                || isOurProxy(entry.secure, address: address, port: port)
                || isOurPAC(entry.auto, pacURL: pacURL)
            {
                try await restore(entry)
            }
        }

        let bypass = "localhost,127.0.0.1,*.local,169.254/16"
        try await Shell.runAsync(networksetup, arguments: [
            "-setwebproxy", active, address, String(port)
        ])
        try await Shell.runAsync(networksetup, arguments: [
            "-setwebproxystate", active, "on"
        ])
        try await Shell.runAsync(networksetup, arguments: [
            "-setsecurewebproxy", active, address, String(port)
        ])
        try await Shell.runAsync(networksetup, arguments: [
            "-setsecurewebproxystate", active, "on"
        ])
        try await Shell.runAsync(networksetup, arguments: [
            "-setproxybypassdomains", active, bypass
        ])
        try await Shell.runAsync(networksetup, arguments: [
            "-setautoproxyurl", active, pacURL.absoluteString
        ])
        try await Shell.runAsync(networksetup, arguments: [
            "-setautoproxystate", active, "on"
        ])
        _ = try? await Shell.runAsync("/usr/bin/killall", arguments: ["-HUP", "configd"], throwOnError: false)
    }

    func restore() async {
        let copies = snapshot
        snapshot = []
        for entry in copies {
            try? await restore(entry)
        }
        _ = try? await Shell.runAsync("/usr/bin/killall", arguments: ["-HUP", "configd"], throwOnError: false)
    }

    /// Blocking restore for app termination paths.
    func restoreSync() {
        let copies = snapshot
        snapshot = []
        for entry in copies {
            try? restoreBlocking(entry)
        }
        _ = try? Shell.run("/usr/bin/killall", arguments: ["-HUP", "configd"], throwOnError: false)
    }

    func verifyOurProxy(address: String, port: UInt16, pacURL: URL) async -> Bool {
        guard let active = try? await activeNetworkService() else { return false }
        let web = (try? await getWebProxy(service: active)) ?? ProxyServiceState(enabled: false, server: "", port: 0)
        let secure = (try? await getSecureProxy(service: active)) ?? ProxyServiceState(enabled: false, server: "", port: 0)
        let auto = (try? await getAutoProxy(service: active)) ?? AutoProxyState(enabled: false, url: "")
        let manualOK = isOurProxy(web, address: address, port: port) || isOurProxy(secure, address: address, port: port)
        let pacOK = isOurPAC(auto, pacURL: pacURL)
        return manualOK || pacOK
    }

    private func restore(_ entry: NetworkServiceProxySnapshot) async throws {
        try restoreBlocking(entry)
    }

    private func restoreBlocking(_ entry: NetworkServiceProxySnapshot) throws {
        let service = entry.service
        if entry.web.enabled, !entry.web.server.isEmpty {
            try Shell.run(networksetup, arguments: [
                "-setwebproxy", service, entry.web.server, String(entry.web.port)
            ])
            try Shell.run(networksetup, arguments: ["-setwebproxystate", service, "on"])
        } else {
            try Shell.run(networksetup, arguments: ["-setwebproxystate", service, "off"])
        }

        if entry.secure.enabled, !entry.secure.server.isEmpty {
            try Shell.run(networksetup, arguments: [
                "-setsecurewebproxy", service, entry.secure.server, String(entry.secure.port)
            ])
            try Shell.run(networksetup, arguments: ["-setsecurewebproxystate", service, "on"])
        } else {
            try Shell.run(networksetup, arguments: ["-setsecurewebproxystate", service, "off"])
        }

        if entry.auto.enabled, !entry.auto.url.isEmpty {
            try Shell.run(networksetup, arguments: [
                "-setautoproxyurl", service, entry.auto.url
            ])
            try Shell.run(networksetup, arguments: ["-setautoproxystate", service, "on"])
        } else {
            try Shell.run(networksetup, arguments: ["-setautoproxystate", service, "off"])
        }

        if !entry.bypass.isEmpty {
            let domains = entry.bypass
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if !domains.isEmpty {
                try Shell.run(networksetup, arguments: ["-setproxybypassdomains", service] + domains)
            }
        }
    }

    private func listNetworkServices() async throws -> [String] {
        let out = try await Shell.runAsync(networksetup, arguments: ["-listallnetworkservices"])
        return out
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.isEmpty && !$0.hasPrefix("An asterisk") && !$0.hasPrefix("*") }
            .map { line in
                if line.hasPrefix("*") {
                    return String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
                }
                return line
            }
    }

    private func activeNetworkService() async throws -> String {
        let route = try await Shell.runAsync("/sbin/route", arguments: ["-n", "get", "default"], throwOnError: false)
        var interface: String?
        for line in route.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("interface:") {
                interface = trimmed.replacingOccurrences(of: "interface:", with: "")
                    .trimmingCharacters(in: .whitespaces)
            }
        }
        guard let interface else { throw SystemProxyError.noActiveService }

        let ports = try await Shell.runAsync(networksetup, arguments: ["-listallhardwareports"])
        var currentPort: String?
        var hardwarePortToDevice: [String: String] = [:]
        for line in ports.split(separator: "\n").map(String.init) {
            if line.hasPrefix("Hardware Port:") {
                currentPort = line.replacingOccurrences(of: "Hardware Port:", with: "")
                    .trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("Device:"), let currentPort {
                let device = line.replacingOccurrences(of: "Device:", with: "")
                    .trimmingCharacters(in: .whitespaces)
                hardwarePortToDevice[currentPort] = device
            }
        }

        if let match = hardwarePortToDevice.first(where: { $0.value == interface })?.key {
            let services = try await listNetworkServices()
            if services.contains(match) { return match }
            // Sometimes service name equals hardware port name.
            return match
        }

        let services = try await listNetworkServices()
        if let first = services.first { return first }
        throw SystemProxyError.noActiveService
    }

    private func getWebProxy(service: String) async throws -> ProxyServiceState {
        let out = try await Shell.runAsync(networksetup, arguments: ["-getwebproxy", service])
        return parseProxyState(out)
    }

    private func getSecureProxy(service: String) async throws -> ProxyServiceState {
        let out = try await Shell.runAsync(networksetup, arguments: ["-getsecurewebproxy", service])
        return parseProxyState(out)
    }

    private func getAutoProxy(service: String) async throws -> AutoProxyState {
        let out = try await Shell.runAsync(networksetup, arguments: ["-getautoproxyurl", service])
        var enabled = false
        var url = ""
        for line in out.split(separator: "\n").map(String.init) {
            if line.hasPrefix("Enabled:") {
                enabled = line.lowercased().contains("yes")
            } else if line.hasPrefix("URL:") {
                url = line.replacingOccurrences(of: "URL:", with: "").trimmingCharacters(in: .whitespaces)
            }
        }
        return AutoProxyState(enabled: enabled, url: url)
    }

    private func getBypass(service: String) async throws -> String {
        let out = try await Shell.runAsync(networksetup, arguments: ["-getproxybypassdomains", service], throwOnError: false)
        let lines = out
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.lowercased().contains("there aren't any") }
        return lines.joined(separator: ",")
    }

    private func parseProxyState(_ output: String) -> ProxyServiceState {
        var enabled = false
        var server = ""
        var port = 0
        for line in output.split(separator: "\n").map(String.init) {
            if line.hasPrefix("Enabled:") {
                enabled = line.lowercased().contains("yes")
            } else if line.hasPrefix("Server:") {
                server = line.replacingOccurrences(of: "Server:", with: "").trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("Port:") {
                port = Int(line.replacingOccurrences(of: "Port:", with: "").trimmingCharacters(in: .whitespaces)) ?? 0
            }
        }
        return ProxyServiceState(enabled: enabled, server: server, port: port)
    }

    private func isOurProxy(_ state: ProxyServiceState, address: String, port: UInt16) -> Bool {
        state.enabled && state.server == address && state.port == Int(port)
    }

    private func isOurPAC(_ state: AutoProxyState, pacURL: URL) -> Bool {
        guard state.enabled else { return false }
        return state.url.contains("\(PACServer.host):\(PACServer.port)") || state.url == pacURL.absoluteString
    }
}
