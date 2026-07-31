import AppKit
import ServiceManagement
import SwiftUI

private enum SettingsTab: String, CaseIterable, Identifiable {
    case connection
    case general
    case updates
    case tools

    var id: String { rawValue }

    var title: String {
        switch self {
        case .connection: return "Proxy"
        case .general: return "General"
        case .updates: return "Updates"
        case .tools: return "Tools"
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var settings = SettingsStore.shared
    @State private var tab: SettingsTab = .connection
    @State private var dnsMessage: String?
    @State private var quicMessage: String?
    @State private var isWorking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            UnderlineTabBar(selection: $tab, title: \.title)

            Group {
                switch tab {
                case .connection:
                    connectionTab
                case .general:
                    generalTab
                case .updates:
                    updatesTab
                case .tools:
                    toolsTab
                }
            }
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        }
        .padding(12)
        .onAppear {
            LoginItemManager.setEnabled(settings.startAtLogin)
            DockIconManager.setVisible(settings.showDockIcon)
        }
    }

    private var connectionTab: some View {
        panel {
            toggleRow(
                "System proxy",
                info: "Routes Safari and other apps through SpoofDPI automatically.",
                isOn: $settings.macSystemProxy
            )
        }
    }

    private var generalTab: some View {
        panel {
            toggleRow("Start at login", isOn: $settings.startAtLogin)
                .onChange(of: settings.startAtLogin) { _, enabled in
                    LoginItemManager.setEnabled(enabled)
                }

            rowDivider

            toggleRow("Show Dock icon", isOn: $settings.showDockIcon)
                .onChange(of: settings.showDockIcon) { _, enabled in
                    DockIconManager.setVisible(enabled)
                }
        }
    }

    private var updatesTab: some View {
        panel {
            HStack(spacing: 8) {
                Text("Frequency")
                    .font(.subheadline.weight(.medium))
                Spacer(minLength: 8)
                Picker("", selection: $settings.updateFrequency) {
                    ForEach(UpdateFrequency.allCases) { frequency in
                        Text(frequency.title).tag(frequency)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }
            .frame(minHeight: 28)

            rowDivider

            Button("Check Now") {
                UpdateController.shared.checkForUpdates()
            }
            .buttonStyle(.borderless)
            .font(.subheadline)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: 28)

            rowDivider

            HStack {
                Text("Version")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(appVersion)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(minHeight: 28)
        }
    }

    private var toolsTab: some View {
        panel {
            Button {
                Task {
                    isWorking = true
                    dnsMessage = await appState.flushDNS()
                    isWorking = false
                }
            } label: {
                actionRow("Flush DNS Cache", message: dnsMessage)
            }
            .buttonStyle(.borderless)
            .disabled(isWorking)
            .frame(minHeight: 28)

            rowDivider

            Button(role: .destructive) {
                Task {
                    isWorking = true
                    do {
                        try await appState.removeQuicBlock()
                        quicMessage = "Removed"
                    } catch {
                        quicMessage = error.localizedDescription
                    }
                    isWorking = false
                }
            } label: {
                actionRow(
                    "Remove QUIC Block",
                    info: "Removes the pf rule that blocks UDP/443 so Safari cannot bypass the proxy.",
                    message: quicMessage
                )
            }
            .buttonStyle(.borderless)
            .disabled(isWorking || !settings.quicBlockInstalled)
            .frame(minHeight: 28)
        }
    }

    private var rowDivider: some View {
        Divider().padding(.vertical, 2)
    }

    private func panel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func toggleRow(_ title: String, info: String? = nil, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.medium))
            if let info {
                HoverInfoIcon(text: info)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
        }
        .frame(minHeight: 28)
    }

    private func actionRow(_ title: String, info: String? = nil, message: String?) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
            if let info {
                HoverInfoIcon(text: info)
            }
            Spacer(minLength: 8)
            if let message {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var appVersion: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }
}

private struct HoverInfoIcon: View {
    let text: String
    @State private var isHovering = false

    var body: some View {
        Image(systemName: "info.circle")
            .font(.caption)
            .foregroundStyle(isHovering ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            .padding(4)
            .contentShape(Rectangle())
            .onHover { hovering in
                isHovering = hovering
            }
            .popover(isPresented: $isHovering, arrowEdge: .bottom) {
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 220, alignment: .leading)
                    .padding(10)
                    .onHover { hovering in
                        if hovering {
                            isHovering = true
                        }
                    }
            }
            .accessibilityLabel(text)
    }
}

enum LoginItemManager {
    static func setEnabled(_ enabled: Bool) {
        let service = SMAppService.mainApp
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            // Ignore registration errors in DEBUG/unsigned builds.
        }
    }
}

enum DockIconManager {
    @MainActor
    static func setVisible(_ visible: Bool) {
        NSApp.setActivationPolicy(visible ? .regular : .accessory)
    }
}
