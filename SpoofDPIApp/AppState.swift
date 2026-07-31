import AppKit
import Foundation
import SwiftUI

struct SessionDiagnostics: Equatable {
    var proxyTest: ProxyTestResult?
    var safariUsingProxy: Bool?
    var safariPageLoaded: Bool?
    var systemProxyOk: Bool?
    var quicBlocked: Bool?
    var needsSafariSetup: Bool
    var phaseMessage: String?

    static let empty = SessionDiagnostics(
        proxyTest: nil,
        safariUsingProxy: nil,
        safariPageLoaded: nil,
        systemProxyOk: nil,
        quicBlocked: nil,
        needsSafariSetup: false,
        phaseMessage: nil
    )
}

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var isBusy = false
    @Published private(set) var statusText = "Not connected"
    @Published private(set) var detailText = "Start SpoofDPI to listen on 127.0.0.1:8080"
    @Published private(set) var lastError: String?
    @Published private(set) var diagnostics = SessionDiagnostics.empty
    @Published var settings = SettingsStore.shared

    private let process = SpoofDPIProcess()
    private let proxyManager = SystemProxyManager()
    private let pacServer = PACServer()
    private let safari = SafariCoordinator()
    private let quicBlock = QuicBlockClient()

    func toggle() {
        if isRunning {
            Task { await disconnect() }
        } else {
            Task { await connect() }
        }
    }

    func connect() async {
        guard !isBusy else { return }
        isBusy = true
        lastError = nil
        diagnostics = SessionDiagnostics.empty
        statusText = "Connecting…"

        do {
            try await withPhase("Starting SpoofDPI…", detail: "Starting SpoofDPI") {
                try await process.start()
            }

            if settings.macSystemProxy {
                try await withPhase("Configuring system proxy…", detail: "Configuring system proxy") {
                    _ = try await proxyManager.capture()
                    try await pacServer.start()
                    try await proxyManager.apply(
                        address: SpoofDPIProcess.address,
                        port: SpoofDPIProcess.port,
                        pacURL: PACServer.pacURL
                    )
                }

                var quicBlocked = settings.quicBlockInstalled
                if !settings.quicBlockInstalled {
                    do {
                        try await withPhase("Installing QUIC block…", detail: "Installing QUIC block") {
                            try await quicBlock.ensureInstalled()
                        }
                        settings.quicBlockInstalled = true
                        quicBlocked = true
                    } catch {
                        quicBlocked = false
                        diagnostics.phaseMessage = error.localizedDescription
                        await dwell(1.2)
                    }
                } else {
                    quicBlocked = await quicBlock.status()
                }

                var safariResult = SafariConnectResult(usingProxy: false, pageLoaded: false, message: "")
                await withPhase("Restarting Safari…", detail: "Restarting Safari") {
                    safariResult = await safari.restartForConnect(
                        url: URL(string: "https://discord.com")!,
                        proxyPort: SpoofDPIProcess.port
                    )
                }
                if !safariResult.pageLoaded {
                    await withPhase("Retrying Safari…", detail: "Retrying Safari") {
                        try? await proxyManager.apply(
                            address: SpoofDPIProcess.address,
                            port: SpoofDPIProcess.port,
                            pacURL: PACServer.pacURL
                        )
                        safariResult = await safari.restartForConnect(
                            url: URL(string: "https://discord.com")!,
                            proxyPort: SpoofDPIProcess.port
                        )
                    }
                }

                var proxyTest = ProxyTestResult(ok: false, httpCode: 0, url: "", message: "")
                var systemProxyOk = false
                await withPhase("Checking connection…", detail: "Verifying proxy") {
                    proxyTest = await ProxyHealth.test()
                    systemProxyOk = await proxyManager.verifyOurProxy(
                        address: SpoofDPIProcess.address,
                        port: SpoofDPIProcess.port,
                        pacURL: PACServer.pacURL
                    )
                }
                let needsSetup = !safariResult.usingProxy || !safariResult.pageLoaded || !quicBlocked

                isRunning = true
                statusText = "Connected"
                if proxyTest.ok && safariResult.usingProxy {
                    detailText = "\(SpoofDPIProcess.address):\(SpoofDPIProcess.port) · Safari OK"
                } else if proxyTest.ok {
                    detailText = "\(SpoofDPIProcess.address):\(SpoofDPIProcess.port) · \(safariResult.message)"
                } else {
                    detailText = proxyTest.message
                }

                diagnostics = SessionDiagnostics(
                    proxyTest: proxyTest,
                    safariUsingProxy: safariResult.usingProxy,
                    safariPageLoaded: safariResult.pageLoaded,
                    systemProxyOk: systemProxyOk,
                    quicBlocked: quicBlocked,
                    needsSafariSetup: needsSetup,
                    phaseMessage: "Connected"
                )
                await dwell(1.6)
                if diagnostics.phaseMessage == "Connected" {
                    diagnostics.phaseMessage = nil
                }
            } else {
                isRunning = true
                statusText = "Connected"
                detailText = "\(SpoofDPIProcess.address):\(SpoofDPIProcess.port)"
                diagnostics.phaseMessage = "Connected"
                await dwell(1.2)
                diagnostics.phaseMessage = nil
            }
        } catch {
            await teardownRouting()
            process.stop()
            isRunning = false
            let message = error.localizedDescription
            lastError = message
            statusText = "Not connected"
            detailText = message
            diagnostics.phaseMessage = message
            await dwell(1.6)
            if diagnostics.phaseMessage == message {
                diagnostics.phaseMessage = nil
            }
        }

        isBusy = false
    }

    func disconnect() async {
        isBusy = true
        statusText = "Disconnecting…"
        await withPhase("Disconnecting…", detail: "Restoring system settings") {
            await teardownRouting()
            process.stop()
        }
        isRunning = false
        lastError = nil
        statusText = "Not connected"
        detailText = "Disconnected"
        diagnostics = SessionDiagnostics(
            proxyTest: nil,
            safariUsingProxy: nil,
            safariPageLoaded: nil,
            systemProxyOk: nil,
            quicBlocked: nil,
            needsSafariSetup: false,
            phaseMessage: "Disconnected"
        )
        await dwell(1.4)
        diagnostics = SessionDiagnostics.empty
        detailText = "Start SpoofDPI to listen on 127.0.0.1:8080"
        isBusy = false
    }

    /// Best-effort cleanup for app termination.
    func cleanupForTermination() {
        pacServer.stop()
        process.stop()
        proxyManager.restoreSync()
        isRunning = false
    }

    func setupSafari() async {
        guard isRunning, !isBusy else { return }
        isBusy = true
        diagnostics.phaseMessage = "Setting up Safari…"
        do {
            if !settings.quicBlockInstalled || diagnostics.quicBlocked != true {
                try await quicBlock.ensureInstalled()
                settings.quicBlockInstalled = true
                diagnostics.quicBlocked = true
            }
            try await proxyManager.apply(
                address: SpoofDPIProcess.address,
                port: SpoofDPIProcess.port,
                pacURL: PACServer.pacURL
            )
            let safariResult = await safari.restartForConnect(
                url: URL(string: "https://discord.com")!,
                proxyPort: SpoofDPIProcess.port
            )
            let proxyTest = await ProxyHealth.test()
            let systemProxyOk = await proxyManager.verifyOurProxy(
                address: SpoofDPIProcess.address,
                port: SpoofDPIProcess.port,
                pacURL: PACServer.pacURL
            )
            diagnostics = SessionDiagnostics(
                proxyTest: proxyTest,
                safariUsingProxy: safariResult.usingProxy,
                safariPageLoaded: safariResult.pageLoaded,
                systemProxyOk: systemProxyOk,
                quicBlocked: diagnostics.quicBlocked,
                needsSafariSetup: !safariResult.usingProxy || !safariResult.pageLoaded,
                phaseMessage: nil
            )
            detailText = safariResult.message
        } catch {
            lastError = error.localizedDescription
            diagnostics.phaseMessage = error.localizedDescription
            diagnostics.needsSafariSetup = true
        }
        isBusy = false
    }

    func openNetworkSettings() {
        safari.openNetworkSettings()
    }

    func flushDNS() async -> String {
        do {
            try await quicBlock.flushDNSPrivileged()
            return "DNS cache flushed"
        } catch {
            await safari.flushDNS()
            return "DNS flush requested"
        }
    }

    func removeQuicBlock() async throws {
        try await quicBlock.remove()
        settings.quicBlockInstalled = false
        diagnostics.quicBlocked = false
    }

    func quitApp() {
        Task {
            await disconnect()
            NSApplication.shared.terminate(nil)
        }
    }

    private func teardownRouting() async {
        pacServer.stop()
        await proxyManager.restore()
    }

    private func withPhase(
        _ message: String,
        detail: String,
        minimum: Double = 0.9,
        operation: () async throws -> Void
    ) async rethrows {
        let started = ContinuousClock.now
        diagnostics.phaseMessage = message
        detailText = detail
        try await operation()
        let elapsed = ContinuousClock.now - started
        let remaining = Duration.seconds(minimum) - elapsed
        if remaining > .zero {
            try? await Task.sleep(for: remaining)
        }
    }

    private func dwell(_ seconds: Double = 0.9) async {
        try? await Task.sleep(for: .seconds(seconds))
    }
}
