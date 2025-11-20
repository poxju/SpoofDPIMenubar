# SpoofDPI Menubar App

This application provides a macOS menubar interface for [SpoofDPI](https://github.com/xvzc/SpoofDPI), based on the configuration from [GoodbyeDPI-Turkey](https://github.com/cagritaskn/GoodbyeDPI-Turkey). The app wraps the SpoofDPI executable with an easy-to-use toggle interface, eliminating the need to run terminal commands manually.

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

### macOS
If macOS blocks the app on first launch, you can:
- **Option 1**: Settings → Privacy & Security → Allow the application from the security section at the bottom

## Requirements

- macOS 10.12+
- Node.js 16+
- Electron 27+

## License

MIT

## Credits

- [SpoofDPI](https://github.com/xvzc/SpoofDPI) - The core DPI bypass tool
- [GoodbyeDPI-Turkey](https://github.com/cagritaskn/GoodbyeDPI-Turkey) - Configuration and implementation reference
