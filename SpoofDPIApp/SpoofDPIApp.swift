import AppKit
import SwiftUI

@main
struct SpoofDPIApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()
    @ObservedObject private var settings = SettingsStore.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarPopoverView()
                .environmentObject(appState)
                .onAppear {
                    appDelegate.appState = appState
                    UpdateController.shared.configure()
                    DockIconManager.setVisible(settings.showDockIcon)
                }
        } label: {
            Image("MenuBarIcon")
                .renderingMode(.template)
                .accessibilityLabel(appState.isRunning ? "SpoofDPI Connected" : "SpoofDPI")
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor weak var appState: AppState?

    @MainActor
    func applicationWillTerminate(_ notification: Notification) {
        appState?.cleanupForTermination()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        UpdateController.shared.configure()
    }
}
