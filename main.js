const { app, BrowserWindow, Tray, Menu, ipcMain, nativeImage } = require('electron');
const path = require('path');
const fs = require('fs');
const { spawn } = require('child_process');

let tray = null;
let window = null;
let spoofdpiProcess = null;
let isRunning = false;

// Resolve path to the spoofdpi executable for dev and packaged builds
function resolveSpoofDpiPath() {
  if (app.isPackaged) {
    return path.join(process.resourcesPath, 'spoofdpi');
  }
  return path.join(__dirname, 'spoofdpi');
}

// Create tray icon - will use template image that adapts to light/dark mode
function createTrayIcon() {
  const iconPath = path.join(__dirname, 'assets', 'tray-icon.png');
  const icon = nativeImage.createFromPath(iconPath);
  icon.setTemplateImage(true); // Template images automatically adapt to menubar theme
  return icon;
}

function createWindow() {
  window = new BrowserWindow({
    width: 280,
    height: 240,
    show: false,
    frame: false,
    resizable: false,
    transparent: true,
    backgroundColor: '#00000000',
    vibrancy: 'menu',
    visualEffectState: 'active',
    webPreferences: {
      nodeIntegration: true,
      contextIsolation: false
    }
  });

  window.loadFile('index.html');

  // Hide window when it loses focus
  window.on('blur', () => {
    if (!window.webContents.isDevToolsOpened()) {
      hideWindow();
    }
  });
}

function createTray() {
  const icon = createTrayIcon();
  tray = new Tray(icon);
  
  tray.setToolTip('SpoofDPI');
  
  tray.on('click', () => {
    toggleWindow();
  });

  tray.on('right-click', () => {
    const contextMenu = Menu.buildFromTemplate([
      {
        label: 'Quit',
        click: () => {
          app.quit();
        }
      }
    ]);
    tray.popUpContextMenu(contextMenu);
  });
}

function toggleWindow() {
  if (window.isVisible()) {
    hideWindow();
  } else {
    showWindow();
  }
}

function hideWindow() {
  // Smooth fade-out animation
  let opacity = 1;
  const fadeOut = setInterval(() => {
    opacity -= 0.1;
    if (opacity <= 0) {
      window.setOpacity(0);
      window.hide();
      clearInterval(fadeOut);
    } else {
      window.setOpacity(opacity);
    }
  }, 15);
}

function showWindow() {
  const trayBounds = tray.getBounds();
  const windowBounds = window.getBounds();
  
  // Position window below tray icon
  const x = Math.round(trayBounds.x + (trayBounds.width / 2) - (windowBounds.width / 2));
  const y = Math.round(trayBounds.y + trayBounds.height);
  
  window.setPosition(x, y, false);
  
  // Smooth fade-in animation
  window.setOpacity(0);
  window.show();
  
  // Animate opacity from 0 to 1
  let opacity = 0;
  const fadeIn = setInterval(() => {
    opacity += 0.1;
    if (opacity >= 1) {
      window.setOpacity(1);
      clearInterval(fadeIn);
    } else {
      window.setOpacity(opacity);
    }
  }, 15);
  
  window.focus();
}

function startSpoofdpi() {
  if (isRunning) {
    return { success: false, message: 'SpoofDPI is already running' };
  }

  try {
    const spoofdpiPath = resolveSpoofDpiPath();

    // Ensure executable permission (especially after packaging)
    try {
      fs.accessSync(spoofdpiPath, fs.constants.X_OK);
    } catch {
      try {
        fs.chmodSync(spoofdpiPath, 0o755);
      } catch (e) {
        console.warn('Could not set execute permission on spoofdpi:', e.message);
      }
    }

    spoofdpiProcess = spawn(spoofdpiPath, [], {
      detached: false
    });

    // Capture stderr for error messages
    let errorOutput = '';
    
    if (spoofdpiProcess.stderr) {
      spoofdpiProcess.stderr.on('data', (data) => {
        errorOutput += data.toString();
        console.error('spoofdpi stderr:', data.toString());
      });
    }

    if (spoofdpiProcess.stdout) {
      spoofdpiProcess.stdout.on('data', (data) => {
        console.log('spoofdpi stdout:', data.toString());
      });
    }

    spoofdpiProcess.on('error', (error) => {
      console.error('Failed to start spoofdpi:', error);
      isRunning = false;
      if (window) {
        window.webContents.send('status-changed', { running: false, error: error.message });
      }
    });

    spoofdpiProcess.on('exit', (code) => {
      console.log(`spoofdpi exited with code ${code}`);
      isRunning = false;
      const exitError = code !== 0 ? (errorOutput || `Process exited with code ${code}`) : null;
      if (window) {
        window.webContents.send('status-changed', { running: false, error: exitError });
      }
    });

    isRunning = true;
    return { success: true, message: 'SpoofDPI started successfully' };
  } catch (error) {
    console.error('Error starting spoofdpi:', error);
    return { success: false, message: error.message };
  }
}

function stopSpoofdpi() {
  if (!isRunning || !spoofdpiProcess) {
    return { success: false, message: 'SpoofDPI is not running' };
  }

  try {
    spoofdpiProcess.kill();
    spoofdpiProcess = null;
    isRunning = false;
    return { success: true, message: 'SpoofDPI stopped successfully' };
  } catch (error) {
    console.error('Error stopping spoofdpi:', error);
    return { success: false, message: error.message };
  }
}

// IPC handlers
ipcMain.handle('start-spoofdpi', () => {
  const result = startSpoofdpi();
  if (result.success) {
    window.webContents.send('status-changed', { running: true });
  }
  return result;
});

ipcMain.handle('stop-spoofdpi', () => {
  const result = stopSpoofdpi();
  if (result.success) {
    window.webContents.send('status-changed', { running: false });
  }
  return result;
});

ipcMain.handle('get-status', () => {
  return { running: isRunning };
});

app.whenReady().then(() => {
  createTray();
  createWindow();
});

app.on('window-all-closed', (e) => {
  e.preventDefault();
});

app.on('before-quit', () => {
  // Stop spoofdpi when app quits
  if (isRunning) {
    stopSpoofdpi();
  }
});

// Don't show app in dock on macOS
if (process.platform === 'darwin') {
  app.dock.hide();
}
