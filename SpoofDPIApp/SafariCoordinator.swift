import AppKit
import Foundation

struct SafariConnectResult: Equatable {
    var usingProxy: Bool
    var pageLoaded: Bool
    var message: String
}

@MainActor
final class SafariCoordinator {
    func hardResetNetworking() async {
        _ = try? await Shell.runAsync("/usr/bin/osascript", arguments: [
            "-e", "tell application \"Safari\" to quit"
        ], throwOnError: false)
        try? await Task.sleep(nanoseconds: 400_000_000)

        for name in ["com.apple.WebKit.Networking", "com.apple.WebKit.WebContent", "com.apple.WebKit.GPU"] {
            _ = try? await Shell.runAsync("/usr/bin/killall", arguments: ["-9", name], throwOnError: false)
        }
        _ = try? await Shell.runAsync("/usr/bin/killall", arguments: ["-9", "Safari"], throwOnError: false)
        await flushDNS()
        _ = try? await Shell.runAsync("/usr/bin/killall", arguments: ["-HUP", "configd"], throwOnError: false)
        try? await Task.sleep(nanoseconds: 300_000_000)
    }

    func restartForConnect(url: URL, proxyPort: UInt16) async -> SafariConnectResult {
        await hardResetNetworking()

        _ = try? await Shell.runAsync("/usr/bin/open", arguments: ["-a", "Safari", url.absoluteString], throwOnError: false)
        try? await Task.sleep(nanoseconds: 2_500_000_000)

        let usingProxy = await isWebKitUsingProxy(port: proxyPort)
        let pageLoaded = await !hasFailedPageHeuristic()

        let message: String
        if usingProxy && pageLoaded {
            message = "Safari loaded via proxy"
        } else if usingProxy && !pageLoaded {
            message = "Safari connected to proxy but the page may have failed"
        } else {
            message = "Safari is not using the proxy"
        }

        return SafariConnectResult(usingProxy: usingProxy, pageLoaded: pageLoaded, message: message)
    }

    func openNetworkSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Network-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    func flushDNS() async {
        _ = try? await Shell.runAsync("/usr/bin/dscacheutil", arguments: ["-flushcache"], throwOnError: false)
        _ = try? await Shell.runAsync("/usr/bin/killall", arguments: ["-HUP", "mDNSResponder"], throwOnError: false)
    }

    private func isWebKitUsingProxy(port: UInt16) async -> Bool {
        let out = (try? await Shell.runAsync("/usr/sbin/lsof", arguments: [
            "-nP", "-iTCP:\(port)", "-sTCP:ESTABLISHED"
        ], throwOnError: false)) ?? ""
        let lower = out.lowercased()
        return lower.contains("webkit") || lower.contains("safari") || lower.contains("com.apple.webkit")
    }

    private func hasFailedPageHeuristic() async -> Bool {
        let script = """
        tell application "Safari"
            if (count of windows) is 0 then return "empty"
            set t to name of current tab of front window
            set u to URL of current tab of front window
            return t & "||" & u
        end tell
        """
        let out = ((try? await Shell.runAsync("/usr/bin/osascript", arguments: ["-e", script], throwOnError: false)) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if out.isEmpty || out == "empty" { return true }
        let failTokens = ["fail", "error", "cannot", "can't", "not found", "offline", "safari can’t open", "safari can't open"]
        return failTokens.contains { out.contains($0) }
    }
}
