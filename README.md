# SpoofDPI Menubar

Native macOS menubar app for [SpoofDPI](https://github.com/xvzc/SpoofDPI), inspired by [GoodbyeDPI-Turkey](https://github.com/cagritaskn/GoodbyeDPI-Turkey).

## Why native (SwiftUI)?

Rewritten from Electron to a native SwiftUI app for:

- A smaller footprint (no Chromium/Node) and faster launch
- First-class `MenuBarExtra` integration and standard macOS controls
- Privileged helper (`SMAppService`) for `pf` QUIC blocking instead of ad-hoc admin scripts
- Sparkle auto-update and a clear path to Developer ID notarization

## Features

- Start/stop bundled SpoofDPI on `127.0.0.1:8080`
- Optional system HTTP/HTTPS proxy + PAC (`127.0.0.1:8091/pac`) for Safari and other apps
- Privileged helper to install a `pf` rule that blocks UDP/443 (QUIC) so Safari cannot bypass the proxy
- Safari restart + connectivity checks, with Setup Safari / Network Settings actions
- Settings: system proxy toggle, start at login, Dock icon, update frequency, flush DNS, remove QUIC block
- Sparkle 2 auto-update (GitHub Releases appcast)

## Requirements

- macOS 26+
- Xcode 26+
- Apple Silicon (bundled `spoofdpi` is arm64)
- Apple Developer signing for Release (helper registration + notarization)

## Build & run

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodegen generate
open SpoofDPI.xcodeproj
```

Or:

```bash
xcodebuild -project SpoofDPI.xcodeproj -scheme SpoofDPI -configuration Debug build
```

The SpoofDPI binary lives at `SpoofDPIApp/Resources/spoofdpi`. The helper is copied into `SpoofDPI.app/Contents/MacOS/SpoofDPIHelper` with its launchd plist under `Contents/Library/LaunchDaemons/`.

### Debug notes

- Unsigned Debug builds may not register the LaunchDaemon. In **DEBUG**, QUIC install/remove can fall back to an AppleScript admin prompt so local testing still works.
- Release builds require a working signed helper (no AppleScript fallback).

## Privileged helper

Bundle IDs:

- App: `com.spoofdpi.menubar`
- Helper: `com.spoofdpi.menubar.helper`

On first Connect that needs QUIC blocking, the app calls `SMAppService.daemon(plistName:).register()`. Approve **SpoofDPI Helper** under **System Settings → General → Login Items & Extensions** if macOS asks.

Sign both the app and helper with the same Team ID for XPC to succeed in production.

## Sparkle updates

Sparkle is vendored at `Vendor/Sparkle/Sparkle.xcframework` (no Swift Package Manager resolution required).

The app embeds `SUPublicEDKey` in `SpoofDPIApp/Info.plist`. Keep the matching private seed offline (never commit it).

1. Sign update archives with Sparkle’s `sign_update` and that private key.
2. Host an `appcast.xml` at the URL in `SUFeedURL` (default: GitHub Releases latest download for `poxju/SpoofDPIMenubar`).

To rotate keys, generate a new Ed25519 pair, put the 32-byte public key (base64) in `SUPublicEDKey`, and keep the private seed offline.

To refresh the vendored framework, download a release XCFramework from [Sparkle releases](https://github.com/sparkle-project/Sparkle/releases) into `Vendor/Sparkle/`.

## Usage

1. Launch SpoofDPI — it appears in the menu bar (no Dock icon unless enabled in Settings).
2. Click **Connect**. With system proxy enabled (default), the app configures proxy + PAC, installs the QUIC block if needed, and restarts Safari on a probe URL.
3. Use **Setup Safari** if Safari still bypasses the proxy.
4. **Disconnect** or Quit restores previous proxy settings and stops SpoofDPI / PAC. The QUIC block stays until removed in Settings.

## Project layout

```
SpoofDPIApp/           # Main SwiftUI app
SpoofDPIHelper/        # Privileged LaunchDaemon (pf + DNS flush)
Vendor/Sparkle/        # Vendored Sparkle XCFramework
project.yml            # XcodeGen
SpoofDPI.xcodeproj/
```

## License

MIT

## Credits

- [SpoofDPI](https://github.com/xvzc/SpoofDPI) — DPI bypass proxy
- [GoodbyeDPI-Turkey](https://github.com/cagritaskn/GoodbyeDPI-Turkey) — configuration reference
- [Sparkle](https://sparkle-project.org) — macOS update framework
