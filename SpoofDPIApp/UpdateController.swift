import AppKit
import Foundation
import Sparkle
import UserNotifications

@MainActor
final class UpdateController: NSObject, ObservableObject {
    static let shared = UpdateController()

    private var updaterController: SPUStandardUpdaterController?
    private var scheduleTimer: Timer?

    private var hasValidPublicKey: Bool {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String else {
            return false
        }
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.hasPrefix("REPLACE_"),
              let data = Data(base64Encoded: trimmed),
              data.count == 32
        else {
            return false
        }
        return true
    }

    func configure() {
        guard updaterController == nil else { return }
        guard hasValidPublicKey else {
            NSLog("Sparkle disabled: SUPublicEDKey is missing or invalid")
            return
        }
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: self
        )
        // Avoid probing a missing appcast on every launch.
        updaterController?.updater.automaticallyChecksForUpdates = false
        applyFrequency(SettingsStore.shared.updateFrequency)
        requestNotificationAuthorizationIfNeeded()
    }

    func checkForUpdates() {
        guard updaterController != nil else {
            NSLog("Sparkle is not configured")
            return
        }
        updaterController?.checkForUpdates(nil)
    }

    func applyFrequency(_ frequency: UpdateFrequency) {
        scheduleTimer?.invalidate()
        scheduleTimer = nil
        guard let updaterController else { return }
        guard let interval = frequency.interval else {
            updaterController.updater.automaticallyChecksForUpdates = false
            return
        }
        updaterController.updater.automaticallyChecksForUpdates = true
        updaterController.updater.updateCheckInterval = interval
    }

    private func requestNotificationAuthorizationIfNeeded() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
}

extension UpdateController: SPUUpdaterDelegate {
    nonisolated func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        ["release"]
    }
}

extension UpdateController: SPUStandardUserDriverDelegate {
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        // Focused checks (manual "Check Now") show Sparkle UI; background ones use a notification.
        immediateFocus
    }

    nonisolated func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        guard !handleShowingUpdate else { return }
        guard !state.userInitiated else { return }

        let content = UNMutableNotificationContent()
        content.title = "SpoofDPI Update Available"
        content.body = "Version \(update.displayVersionString) is ready to install."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "spoofdpi.sparkle.update.\(update.versionString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
}
