import Foundation

enum UpdateFrequency: String, CaseIterable, Identifiable {
    case daily
    case weekly
    case monthly
    case never

    var id: String { rawValue }

    var title: String {
        switch self {
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        case .never: return "Never"
        }
    }

    var interval: TimeInterval? {
        switch self {
        case .daily: return 60 * 60 * 24
        case .weekly: return 60 * 60 * 24 * 7
        case .monthly: return 60 * 60 * 24 * 30
        case .never: return nil
        }
    }
}

@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @Published var macSystemProxy: Bool {
        didSet { defaults.set(macSystemProxy, forKey: Keys.macSystemProxy) }
    }

    @Published var startAtLogin: Bool {
        didSet { defaults.set(startAtLogin, forKey: Keys.startAtLogin) }
    }

    @Published var showDockIcon: Bool {
        didSet { defaults.set(showDockIcon, forKey: Keys.showDockIcon) }
    }

    @Published var updateFrequency: UpdateFrequency {
        didSet { defaults.set(updateFrequency.rawValue, forKey: Keys.updateFrequency) }
    }

    @Published var quicBlockInstalled: Bool {
        didSet { defaults.set(quicBlockInstalled, forKey: Keys.quicBlockInstalled) }
    }

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let macSystemProxy = "macSystemProxy"
        static let startAtLogin = "startAtLogin"
        static let showDockIcon = "showDockIcon"
        static let updateFrequency = "updateFrequency"
        static let quicBlockInstalled = "quicBlockInstalled"
    }

    private init() {
        defaults.register(defaults: [
            Keys.macSystemProxy: true,
            Keys.startAtLogin: false,
            Keys.showDockIcon: false,
            Keys.updateFrequency: UpdateFrequency.never.rawValue,
            Keys.quicBlockInstalled: false
        ])
        macSystemProxy = defaults.bool(forKey: Keys.macSystemProxy)
        startAtLogin = defaults.bool(forKey: Keys.startAtLogin)
        showDockIcon = defaults.bool(forKey: Keys.showDockIcon)
        quicBlockInstalled = defaults.bool(forKey: Keys.quicBlockInstalled)
        let raw = defaults.string(forKey: Keys.updateFrequency) ?? UpdateFrequency.weekly.rawValue
        updateFrequency = UpdateFrequency(rawValue: raw) ?? .weekly
    }
}
