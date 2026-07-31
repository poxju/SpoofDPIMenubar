import SwiftUI

struct SetupBannerView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.subheadline)
                Text("Safari setup needed")
                    .font(.subheadline.weight(.semibold))
            }

            Text("Safari may be bypassing the proxy (often via QUIC). Retry setup or open Network settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button("Setup Safari") {
                    Task { await appState.setupSafari() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(appState.isBusy)

                Button("Network Settings") {
                    appState.openNetworkSettings()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.25), lineWidth: 1)
        )
    }
}
