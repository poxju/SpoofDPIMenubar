import AppKit
import SwiftUI

private enum MainTab: String, CaseIterable, Identifiable {
    case status
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .status: return "Status"
        case .settings: return "Settings"
        }
    }
}

struct MenuBarPopoverView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var settings = SettingsStore.shared
    @State private var mainTab: MainTab = .status
    @State private var layoutTick = 0

    var body: some View {
        let _ = layoutTick
        let width = PopoverLayout.width
        let contentHeight = PopoverLayout.contentHeight
        let padding = PopoverLayout.horizontalPadding

        VStack(spacing: 0) {
            header
                .padding(.horizontal, padding)
                .padding(.top, 14)
                .padding(.bottom, 10)

            PillTabBar(selection: $mainTab, title: \.title)
                .padding(.horizontal, padding)
                .padding(.bottom, 10)

            Divider().opacity(0.6)

            Group {
                switch mainTab {
                case .status:
                    statusTab(contentHeight: contentHeight, padding: padding)
                case .settings:
                    SettingsView()
                        .frame(maxWidth: .infinity, minHeight: contentHeight, maxHeight: contentHeight, alignment: .top)
                }
            }
            .frame(maxWidth: .infinity, minHeight: contentHeight, maxHeight: contentHeight, alignment: .top)

            Divider().opacity(0.6)

            footer
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
        .frame(width: width)
        .onAppear(perform: refreshLayout)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            refreshLayout()
        }
        .onChange(of: settings.updateFrequency) { _, frequency in
            UpdateController.shared.applyFrequency(frequency)
        }
    }

    private var header: some View {
        Text("SpoofDPI")
            .font(.system(size: PopoverLayout.titleSize, weight: .bold))
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
    }

    private func statusTab(contentHeight: CGFloat, padding: CGFloat) -> some View {
        VStack(spacing: contentHeight < 200 ? 12 : 16) {
            Spacer(minLength: 4)

            bigToggle

            statusInfo
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 4)

            if appState.diagnostics.needsSafariSetup {
                SetupBannerView()
            }

            Spacer(minLength: 4)
        }
        .frame(maxWidth: .infinity, minHeight: contentHeight, maxHeight: contentHeight)
        .padding(.horizontal, padding)
        .padding(.vertical, 12)
    }

    private var bigToggle: some View {
        Toggle(isOn: Binding(
            get: { appState.isRunning },
            set: { newValue in
                guard newValue != appState.isRunning, !appState.isBusy else { return }
                appState.toggle()
            }
        )) {
            EmptyView()
        }
        .labelsHidden()
        .toggleStyle(.switch)
        .controlSize(.large)
        .scaleEffect(PopoverLayout.toggleScale)
        .frame(maxWidth: .infinity)
        .padding(.vertical, PopoverLayout.contentHeight < 200 ? 8 : 12)
        .disabled(appState.isBusy)
        .tint(appState.isRunning ? .green : .secondary)
    }

    private var statusInfo: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                if appState.isBusy {
                    ProgressView()
                        .controlSize(.regular)
                } else {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 12, height: 12)
                }

                Text(appState.statusText)
                    .font(PopoverLayout.statusTitleFont)
                    .animation(.easeInOut(duration: 0.2), value: appState.statusText)
            }

            Text(appState.detailText)
                .font(PopoverLayout.statusDetailFont)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .animation(.easeInOut(duration: 0.2), value: appState.detailText)

            if hasSecondaryStatus {
                VStack(spacing: 6) {
                    if let phase = appState.diagnostics.phaseMessage {
                        Text(phase)
                            .font(PopoverLayout.statusSecondaryFont)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .transition(.opacity)
                    }

                    if let proxy = appState.diagnostics.proxyTest {
                        Text(proxy.message)
                            .font(PopoverLayout.statusSecondaryFont)
                            .foregroundStyle(proxy.ok ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.red))
                            .multilineTextAlignment(.center)
                    }

                    if let safari = appState.diagnostics.safariUsingProxy {
                        Text(safari ? "Safari is using the proxy" : "Safari is not using the proxy")
                            .font(PopoverLayout.statusSecondaryFont)
                            .foregroundStyle(safari ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.orange))
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .animation(.easeInOut(duration: 0.25), value: appState.diagnostics)
    }

    private var hasSecondaryStatus: Bool {
        appState.diagnostics.phaseMessage != nil
            || appState.diagnostics.proxyTest != nil
            || appState.diagnostics.safariUsingProxy != nil
    }

    private var footer: some View {
        HStack {
            Text("v\(appVersion)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Spacer()
            Button("Quit", role: .destructive) {
                appState.quitApp()
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .foregroundStyle(.secondary)
        }
    }

    private var statusColor: Color {
        if appState.lastError != nil {
            return .red
        }
        if appState.isBusy {
            return .orange
        }
        return appState.isRunning ? .green : .secondary
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private func refreshLayout() {
        layoutTick &+= 1
    }
}
