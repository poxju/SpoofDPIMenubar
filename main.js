const { app, BrowserWindow, Tray, Menu, ipcMain, nativeImage, dialog } = require('electron');
const path = require('path');
const fs = require('fs');
const { spawn } = require('child_process');
const { autoUpdater } = require('electron-updater');
const Store = require('electron-store');

// Initialize settings store
const store = new Store({
  defaults: {
    updateFrequency: 'weekly',
    showDockIcon: false,
    startAtLogin: false
  }
});

let tray = null;
let window = null;
let spoofdpiProcess = null;
let isRunning = false;
let updateAvailable = false;
let updateDownloaded = false;
let updateInfo = null;
let manualUpdateCheck = false;
let updateCheckInterval = null;
let updateDialogWindow = null;

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
    alwaysOnTop: true,
    skipTaskbar: true,
    visibleOnAllWorkspaces: true,
    webPreferences: {
      nodeIntegration: true,
      contextIsolation: false
    }
  });

  // Prevent window from switching spaces
  window.setVisibleOnAllWorkspaces(true, { visibleOnFullScreen: true });

  window.loadFile('index.html');

  // Hide window when it loses focus
  window.on('blur', () => {
    if (!window.webContents.isDevToolsOpened()) {
      hideWindow();
    }
  });
}

// Create download progress window
function createDownloadProgressWindow() {
  if (downloadProgressWindow && !downloadProgressWindow.isDestroyed()) {
    downloadProgressWindow.focus();
    return;
  }

  downloadProgressWindow = new BrowserWindow({
    width: 400,
    height: 240,
    frame: false,
    resizable: false,
    transparent: true,
    backgroundColor: '#00000000',
    vibrancy: 'menu',
    visualEffectState: 'active',
    alwaysOnTop: true,
    skipTaskbar: true,
    webPreferences: {
      nodeIntegration: true,
      contextIsolation: false
    }
  });

  // Center the window
  const { screen } = require('electron');
  const primaryDisplay = screen.getPrimaryDisplay();
  const { width, height } = primaryDisplay.workAreaSize;
  downloadProgressWindow.setPosition(
    Math.round((width - 400) / 2),
    Math.round((height - 240) / 2)
  );

  downloadProgressWindow.loadURL(`data:text/html;charset=utf-8,
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="UTF-8">
      <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
          font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
          background: rgba(30, 30, 30, 0.98);
          backdrop-filter: blur(20px);
          border-radius: 12px;
          color: white;
          padding: 32px;
          width: 400px;
          height: 240px;
          display: flex;
          flex-direction: column;
          justify-content: space-between;
        }
        .header {
          text-align: center;
          margin-bottom: 20px;
        }
        h2 {
          font-size: 20px;
          font-weight: 600;
          color: white;
        }
        .progress-container {
          margin-bottom: 20px;
        }
        .progress-bar {
          width: 100%;
          height: 8px;
          background: #2a2a2a;
          border-radius: 4px;
          overflow: hidden;
          margin-bottom: 12px;
        }
        .progress-fill {
          height: 100%;
          background: #007AFF;
          border-radius: 4px;
          transition: width 0.3s ease;
          width: 0%;
        }
        .progress-text {
          text-align: center;
          font-size: 16px;
          color: white;
          font-weight: 500;
        }
        .speed-text {
          text-align: center;
          font-size: 13px;
          color: #999;
          margin-top: 8px;
          display: none;
        }
        .speed-text.show {
          display: block;
        }
        .buttons {
          display: flex;
          gap: 12px;
          justify-content: flex-end;
          margin-top: auto;
        }
        .buttons.hidden {
          display: none;
        }
        .btn {
          padding: 10px 24px;
          border: none;
          border-radius: 8px;
          font-size: 14px;
          font-weight: 500;
          cursor: pointer;
          transition: all 0.2s;
          min-width: 100px;
        }
        .btn-cancel {
          background: #2a2a2a;
          color: white;
        }
        .btn-cancel:hover {
          background: #3a3a3a;
        }
        .btn-install {
          background: #007AFF;
          color: white;
        }
        .btn-install:hover {
          background: #0051D5;
        }
        .btn:active {
          transform: scale(0.98);
        }
      </style>
    </head>
    <body>
      <div class="header">
        <h2 id="title">Downloading...</h2>
      </div>
      <div class="progress-container">
        <div class="progress-bar">
          <div class="progress-fill" id="progressFill"></div>
        </div>
        <div class="progress-text" id="progressText">0%</div>
        <div class="speed-text" id="speedText">Preparing download...</div>
      </div>
      <div class="buttons hidden" id="buttons">
        <button class="btn btn-cancel" onclick="cancelInstall()">Cancel</button>
        <button class="btn btn-install" onclick="installUpdate()">Install</button>
      </div>
    </body>
    <script>
      const { ipcRenderer } = require('electron');
      ipcRenderer.on('download-progress', (event, data) => {
        document.getElementById('progressFill').style.width = data.percent + '%';
        document.getElementById('progressText').textContent = data.percent + '%';
        const speedText = document.getElementById('speedText');
        speedText.textContent = data.transferred + ' MB / ' + data.total + ' MB • ' + data.speed + ' MB/s';
        speedText.classList.add('show');
      });
      ipcRenderer.on('download-complete', (event, data) => {
        document.getElementById('title').textContent = 'Download Complete';
        document.getElementById('progressFill').style.width = '100%';
        document.getElementById('progressText').textContent = '100%';
        document.getElementById('speedText').style.display = 'none';
        document.getElementById('buttons').classList.remove('hidden');
      });
      function cancelInstall() {
        ipcRenderer.send('download-cancel');
      }
      function installUpdate() {
        ipcRenderer.send('download-install');
      }
    </script>
    </html>
  `);

  downloadProgressWindow.on('closed', () => {
    downloadProgressWindow = null;
  });

  // Handle IPC messages from the download window
  ipcMain.on('download-cancel', () => {
    if (downloadProgressWindow && !downloadProgressWindow.isDestroyed()) {
      downloadProgressWindow.close();
    }
    isDownloading = false;
  });

  ipcMain.on('download-install', () => {
    if (downloadProgressWindow && !downloadProgressWindow.isDestroyed()) {
      downloadProgressWindow.close();
    }
    // quitAndInstall() automatically handles:
    // - Closing the app
    // - Installing the new version
    // - Removing the old version
    autoUpdater.quitAndInstall();
  });
}

// Create update available dialog window
function showUpdateAvailableDialog(info) {
  // Close existing dialog if open
  if (updateDialogWindow && !updateDialogWindow.isDestroyed()) {
    updateDialogWindow.focus();
    return;
  }

  // Calculate file size in MB
  const fileSizeMB = info.files && info.files.length > 0 
    ? (info.files.reduce((total, file) => total + (file.size || 0), 0) / (1024 * 1024)).toFixed(2)
    : 'Unknown';

  updateDialogWindow = new BrowserWindow({
    width: 500,
    height: 280,
    frame: false,
    resizable: false,
    transparent: true,
    backgroundColor: '#00000000',
    vibrancy: 'menu',
    visualEffectState: 'active',
    alwaysOnTop: true,
    skipTaskbar: true,
    webPreferences: {
      nodeIntegration: true,
      contextIsolation: false
    }
  });

  // Center the window
  const { screen } = require('electron');
  const primaryDisplay = screen.getPrimaryDisplay();
  const { width, height } = primaryDisplay.workAreaSize;
  updateDialogWindow.setPosition(
    Math.round((width - 500) / 2),
    Math.round((height - 280) / 2)
  );

  const currentVersion = app.getVersion();
  const newVersion = info.version;

  updateDialogWindow.loadURL(`data:text/html;charset=utf-8,
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="UTF-8">
      <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
          font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
          background: rgba(30, 30, 30, 0.98);
          backdrop-filter: blur(20px);
          border-radius: 12px;
          color: white;
          padding: 32px;
          width: 500px;
          height: 280px;
          display: flex;
          flex-direction: column;
          overflow: hidden;
        }
        .header {
          display: flex;
          align-items: center;
          margin-bottom: 24px;
        }
        .icon {
          width: 64px;
          height: 64px;
          background: linear-gradient(135deg, #4ade80 0%, #22c55e 100%);
          border-radius: 12px;
          display: flex;
          align-items: center;
          justify-content: center;
          font-size: 32px;
          margin-right: 20px;
          flex-shrink: 0;
        }
        .title {
          font-size: 24px;
          font-weight: 600;
          color: white;
        }
        .content {
          flex: 1;
          margin-bottom: 24px;
        }
        .version-info {
          display: flex;
          flex-direction: column;
          gap: 8px;
          margin-bottom: 20px;
        }
        .version-line {
          display: flex;
          align-items: center;
          font-size: 14px;
          color: #ccc;
        }
        .version-label {
          min-width: 120px;
          color: #999;
        }
        .version-value {
          color: white;
          font-weight: 500;
        }
        .size-info {
          font-size: 13px;
          color: #999;
          margin-top: 8px;
        }
        .buttons {
          display: flex;
          gap: 12px;
          justify-content: flex-end;
        }
        .btn {
          padding: 10px 24px;
          border: none;
          border-radius: 8px;
          font-size: 14px;
          font-weight: 500;
          cursor: pointer;
          transition: all 0.2s;
          min-width: 100px;
        }
        .btn-close {
          background: #2a2a2a;
          color: white;
        }
        .btn-close:hover {
          background: #3a3a3a;
        }
        .btn-download {
          background: #4ade80;
          color: white;
        }
        .btn-download:hover {
          background: #22c55e;
        }
        .btn:active {
          transform: scale(0.98);
        }
      </style>
    </head>
    <body>
      <div class="header">
        <div class="icon">📦</div>
        <div class="title">New version available</div>
      </div>
      <div class="content">
        <div class="version-info">
          <div class="version-line">
            <span class="version-label">Current version:</span>
            <span class="version-value">v${currentVersion}</span>
          </div>
          <div class="version-line">
            <span class="version-label">Latest version:</span>
            <span class="version-value">v${newVersion}</span>
          </div>
        </div>
        <div class="size-info">Update size: ${fileSizeMB} MB</div>
      </div>
      <div class="buttons">
        <button class="btn btn-close" onclick="closeDialog()">Close</button>
        <button class="btn btn-download" onclick="downloadUpdate()">Download</button>
      </div>
    </body>
    <script>
      const { ipcRenderer } = require('electron');
      function closeDialog() {
        ipcRenderer.send('update-dialog-close');
      }
      function downloadUpdate() {
        ipcRenderer.send('update-dialog-download');
      }
    </script>
    </html>
  `);

  updateDialogWindow.on('closed', () => {
    updateDialogWindow = null;
  });

  // Handle IPC messages from the dialog
  ipcMain.once('update-dialog-close', () => {
    if (updateDialogWindow && !updateDialogWindow.isDestroyed()) {
      updateDialogWindow.close();
    }
  });

  ipcMain.once('update-dialog-download', () => {
    if (updateDialogWindow && !updateDialogWindow.isDestroyed()) {
      updateDialogWindow.close();
    }
    // Start download
    isDownloading = true;
    createDownloadProgressWindow();
    autoUpdater.downloadUpdate();
  });
}

function updateTrayMenu() {
  const menuItems = [];
  
  if (updateDownloaded) {
    menuItems.push({
      label: `Update Available: ${updateInfo?.version}`,
      enabled: false
    });
    menuItems.push({
      label: 'Restart & Install Update',
      click: () => {
        autoUpdater.quitAndInstall();
      }
    });
    menuItems.push({ type: 'separator' });
  } else if (updateAvailable) {
    menuItems.push({
      label: 'Update Available - Downloading...',
      enabled: false
    });
    menuItems.push({ type: 'separator' });
  }
  
  menuItems.push({
    label: 'Check for Updates',
    click: () => {
      checkForUpdates(true);
    }
  });
  menuItems.push({ type: 'separator' });
  menuItems.push({
    label: 'Quit',
    click: () => {
      app.quit();
    }
  });
  
  return Menu.buildFromTemplate(menuItems);
}

function createTray() {
  const icon = createTrayIcon();
  tray = new Tray(icon);
  
  tray.setToolTip('SpoofDPI');
  
  tray.on('click', () => {
    toggleWindow();
  });

  tray.on('right-click', () => {
    tray.popUpContextMenu(updateTrayMenu());
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
  
  // Calculate position relative to tray icon (tray bounds are already in screen coordinates)
  const x = Math.round(trayBounds.x + (trayBounds.width / 2) - (windowBounds.width / 2));
  const y = Math.round(trayBounds.y + trayBounds.height);
  
  // Get current display to ensure window stays within bounds
  const { screen } = require('electron');
  const point = screen.getCursorScreenPoint();
  const currentDisplay = screen.getDisplayNearestPoint(point);
  const displayBounds = currentDisplay.bounds;
  
  // Ensure window stays within display bounds
  const maxX = displayBounds.x + displayBounds.width - windowBounds.width;
  const maxY = displayBounds.y + displayBounds.height - windowBounds.height;
  const finalX = Math.max(displayBounds.x, Math.min(x, maxX));
  const finalY = Math.max(displayBounds.y, Math.min(y, maxY));
  
  // Show window first, then set position to avoid space switching
  window.setOpacity(0);
  window.showInactive(); // Show without focusing to prevent space switch
  
  // Set position after showing
  window.setPosition(finalX, finalY, false);
  
  // Smooth fade-in animation
  let opacity = 0;
  const fadeIn = setInterval(() => {
    opacity += 0.1;
    if (opacity >= 1) {
      window.setOpacity(1);
      clearInterval(fadeIn);
      // Focus after animation completes
      window.focus();
    } else {
      window.setOpacity(opacity);
    }
  }, 15);
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

ipcMain.handle('check-for-updates', () => {
  checkForUpdates(true);
  return { success: true };
});

ipcMain.handle('get-app-version', () => {
  return app.getVersion();
});

// Auto-updater configuration
autoUpdater.autoDownload = false; // Ask user before downloading
autoUpdater.autoInstallOnAppQuit = true;

let downloadProgressWindow = null;
let isDownloading = false;

// Check for updates
function checkForUpdates(showDialog = false) {
  manualUpdateCheck = showDialog;
  
  if (!app.isPackaged) {
    if (showDialog) {
      dialog.showMessageBox(window, {
        type: 'info',
        title: 'Update Check',
        message: 'Updates are only available in the packaged application.',
        buttons: ['OK']
      });
    }
    return;
  }

  autoUpdater.checkForUpdates().catch(err => {
    console.error('Error checking for updates:', err);
    if (showDialog) {
      dialog.showErrorBox('Update Error', `Failed to check for updates: ${err.message}`);
    }
  });
}

// Auto-updater event handlers
autoUpdater.on('checking-for-update', () => {
  console.log('Checking for update...');
});

autoUpdater.on('update-available', (info) => {
  console.log('Update available:', info.version);
  updateAvailable = true;
  updateInfo = info;
  if (tray) {
    tray.setToolTip(`SpoofDPI - Update available: ${info.version}`);
  }
  
  // Show custom update dialog window
  showUpdateAvailableDialog(info);
  manualUpdateCheck = false;
});

autoUpdater.on('update-not-available', (info) => {
  console.log('Update not available');
  updateAvailable = false;
  updateInfo = null;
  if (tray) {
    tray.setToolTip('SpoofDPI');
  }
  // Only show dialog if user manually checked for updates
  if (manualUpdateCheck) {
    dialog.showMessageBox(window, {
      type: 'info',
      title: 'No Updates',
      message: 'You are using the latest version.',
      buttons: ['OK']
    }).catch(() => {}); // Ignore errors if window is closed
  }
  manualUpdateCheck = false;
});

autoUpdater.on('error', (err) => {
  console.error('Auto-updater error:', err);
  if (tray) {
    tray.setToolTip('SpoofDPI');
  }
  // Show error dialog if user manually checked for updates
  if (manualUpdateCheck) {
    dialog.showErrorBox('Update Error', `Failed to check for updates: ${err.message}`).catch(() => {});
    manualUpdateCheck = false;
  }
});

autoUpdater.on('download-progress', (progressObj) => {
  const message = `Download speed: ${progressObj.bytesPerSecond} - Downloaded ${progressObj.percent}% (${progressObj.transferred}/${progressObj.total})`;
  console.log(message);
  
  // Update tray tooltip
  if (tray) {
    const transferredMB = (progressObj.transferred / (1024 * 1024)).toFixed(2);
    const totalMB = (progressObj.total / (1024 * 1024)).toFixed(2);
    tray.setToolTip(`SpoofDPI - Downloading: ${Math.round(progressObj.percent)}% (${transferredMB} MB / ${totalMB} MB)`);
  }
  
  // Update progress window if it exists
  if (downloadProgressWindow && !downloadProgressWindow.isDestroyed()) {
    const transferredMB = (progressObj.transferred / (1024 * 1024)).toFixed(2);
    const totalMB = (progressObj.total / (1024 * 1024)).toFixed(2);
    const speedMBps = (progressObj.bytesPerSecond / (1024 * 1024)).toFixed(2);
    
    downloadProgressWindow.webContents.send('download-progress', {
      percent: Math.round(progressObj.percent),
      transferred: transferredMB,
      total: totalMB,
      speed: speedMBps
    });
  }
});

autoUpdater.on('update-downloaded', (info) => {
  console.log('Update downloaded:', info.version);
  updateDownloaded = true;
  updateAvailable = false;
  isDownloading = false;
  
  // Update progress window to show install option
  if (downloadProgressWindow && !downloadProgressWindow.isDestroyed()) {
    downloadProgressWindow.webContents.send('download-complete', {
      version: info.version
    });
  }
  
  if (tray) {
    tray.setToolTip(`SpoofDPI - Update ready: ${info.version}`);
  }
  
  // Reset manual check flag
  manualUpdateCheck = false;
});

app.whenReady().then(() => {
  createTray();
  createWindow();
  
  // Apply dock icon setting after app is ready (with small delay to ensure dock is available)
  setTimeout(() => {
    applyDockIconSetting();
  }, 100);
  
  // Check for updates on startup (only in packaged app, and if not set to 'never')
  if (app.isPackaged) {
    const frequency = store.get('updateFrequency', 'weekly');
    if (frequency !== 'never') {
      // Wait a bit before checking for updates to not slow down startup
      setTimeout(() => {
        checkForUpdates(false);
      }, 3000);
    }
  }
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

// Apply dock icon setting
function applyDockIconSetting() {
  if (process.platform === 'darwin' && app.dock) {
    const showDockIcon = store.get('showDockIcon', false);
    try {
      if (showDockIcon) {
        app.dock.show();
      } else {
        app.dock.hide();
      }
    } catch (error) {
      console.error('Error setting dock icon visibility:', error);
    }
  }
}

// Setup start at login
function setupStartAtLogin(enabled) {
  app.setLoginItemSettings({
    openAtLogin: enabled,
    name: 'SpoofDPI'
  });
}

// Apply start at login setting
const startAtLogin = store.get('startAtLogin', false);
setupStartAtLogin(startAtLogin);

// Setup update check interval based on frequency
function setupUpdateCheckInterval() {
  // Clear existing interval
  if (updateCheckInterval) {
    clearInterval(updateCheckInterval);
    updateCheckInterval = null;
  }

  const frequency = store.get('updateFrequency', 'weekly');
  
  if (frequency === 'never' || !app.isPackaged) {
    return;
  }

  let intervalMs;
  switch (frequency) {
    case 'daily':
      intervalMs = 24 * 60 * 60 * 1000; // 24 hours
      break;
    case 'weekly':
      intervalMs = 7 * 24 * 60 * 60 * 1000; // 7 days
      break;
    case 'monthly':
      intervalMs = 30 * 24 * 60 * 60 * 1000; // 30 days
      break;
    default:
      return;
  }

  updateCheckInterval = setInterval(() => {
    checkForUpdates(false);
  }, intervalMs);
}

// Setup initial update check interval
setupUpdateCheckInterval();

// IPC handlers for settings
ipcMain.handle('get-settings', () => {
  return {
    updateFrequency: store.get('updateFrequency', 'weekly'),
    showDockIcon: store.get('showDockIcon', false),
    startAtLogin: store.get('startAtLogin', false)
  };
});

ipcMain.handle('set-update-frequency', (event, frequency) => {
  store.set('updateFrequency', frequency);
  setupUpdateCheckInterval();
  return { success: true };
});

ipcMain.handle('set-show-dock-icon', (event, show) => {
  try {
    store.set('showDockIcon', show);
    // Apply immediately
    if (process.platform === 'darwin' && app.dock) {
      if (show) {
        app.dock.show();
      } else {
        app.dock.hide();
      }
    }
    return { success: true };
  } catch (error) {
    console.error('Error setting dock icon:', error);
    return { success: false, error: error.message };
  }
});

ipcMain.handle('set-start-at-login', (event, enabled) => {
  store.set('startAtLogin', enabled);
  setupStartAtLogin(enabled);
  return { success: true };
});
