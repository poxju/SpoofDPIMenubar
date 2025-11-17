# SpoofDPI Menubar App

A minimalist macOS menubar application to control SpoofDPI with a modern transparent interface.

## Features

- ✅ One-click start/stop toggle rather than one-click terminal

## Installation

1. Install dependencies:
```bash
npm install
```

2. Ensure `spoofdpi` executable is in the root directory with execute permissions:
```bash
chmod +x spoofdpi
```

## Usage

### Development
```bash
npm start
```

### Build for Distribution
```bash
npm run build
```

The DMG installer will be created in the `dist/` folder as `SpoofDPI-1.0.0-mac.dmg`.

## Distribution

### For Users
1. Download the DMG file
2. Open it and drag `SpoofDPI.app` to Applications
3. Launch the app - it will appear in your menubar

### macOS Gatekeeper
If macOS blocks the app on first launch, you can:
- **Option 1**: Right-click the app → Open → Open
- **Option 2**: Remove quarantine attribute:
```bash
xattr -dr com.apple.quarantine /Applications/SpoofDPI.app
```

## Requirements

- macOS 10.12+
- Node.js 16+
- Electron 27+

## License

MIT
