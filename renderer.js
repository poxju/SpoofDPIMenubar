const { ipcRenderer } = require('electron');

const toggleSwitch = document.getElementById('toggleSwitch');
const statusText = document.getElementById('statusText');
const errorText = document.getElementById('errorText');
const messageEl = document.getElementById('message');
const settingsIcon = document.getElementById('settingsIcon');
const settingsPanel = document.getElementById('settingsPanel');
const closeSettings = document.getElementById('closeSettings');
const checkUpdatesBtn = document.getElementById('checkUpdatesBtn');
const versionInfo = document.getElementById('versionInfo');
const updateFrequency = document.getElementById('updateFrequency');
const showDockIconToggle = document.getElementById('showDockIconToggle');
const startAtLoginToggle = document.getElementById('startAtLoginToggle');
const flushDnsBtn = document.getElementById('flushDnsBtn');

let isConnected = false;

// Initialize UI with current status
async function updateStatus() {
  const status = await ipcRenderer.invoke('get-status');
  updateUI(status.running);
}

function updateUI(running, error = null) {
  isConnected = running;
  
  if (running) {
    toggleSwitch.classList.add('active');
    statusText.textContent = 'Connected';
    errorText.textContent = '';
  } else {
    toggleSwitch.classList.remove('active');
    statusText.textContent = 'Not Connected';
    errorText.textContent = error || '';
  }
}

function showMessage(text, type = 'info') {
  messageEl.textContent = text;
  messageEl.className = 'message ' + type;
  
  setTimeout(() => {
    messageEl.textContent = '';
    messageEl.className = 'message';
  }, 3000);
}

toggleSwitch.addEventListener('click', async () => {
  if (isConnected) {
    // Stop
    const result = await ipcRenderer.invoke('stop-spoofdpi');
    if (result.success) {
      showMessage(result.message, 'success');
    } else {
      showMessage(result.message, 'error');
    }
  } else {
    // Start
    const result = await ipcRenderer.invoke('start-spoofdpi');
    if (result.success) {
      showMessage(result.message, 'success');
    } else {
      showMessage(result.message, 'error');
    }
  }
});

// Listen for status changes from main process
ipcRenderer.on('status-changed', (event, status) => {
  updateUI(status.running, status.error);
  if (status.error && status.running === false) {
    showMessage(status.error, 'error');
  }
});

// Settings panel toggle
function openSettings() {
  settingsPanel.classList.add('active');
}

function closeSettingsPanel() {
  settingsPanel.classList.remove('active');
}

settingsIcon.addEventListener('click', (e) => {
  e.stopPropagation();
  openSettings();
});

closeSettings.addEventListener('click', closeSettingsPanel);

// Close settings when clicking outside
settingsPanel.addEventListener('click', (e) => {
  if (e.target === settingsPanel) {
    closeSettingsPanel();
  }
});

// Check for updates button
checkUpdatesBtn.addEventListener('click', async () => {
  checkUpdatesBtn.disabled = true;
  checkUpdatesBtn.textContent = 'Checking...';
  
  try {
    await ipcRenderer.invoke('check-for-updates');
    // The main process will show dialogs, so we just reset the button
    setTimeout(() => {
      checkUpdatesBtn.disabled = false;
      checkUpdatesBtn.innerHTML = `
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
          <path d="M21.5 2v6h-6M2.5 22v-6h6M2 11.5a10 10 0 0 1 18.8-4.3M22 12.5a10 10 0 0 1-18.8 4.3"></path>
        </svg>
        Check for Updates
      `;
    }, 2000);
  } catch (error) {
    checkUpdatesBtn.disabled = false;
    checkUpdatesBtn.innerHTML = `
      <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
        <path d="M21.5 2v6h-6M2.5 22v-6h6M2 11.5a10 10 0 0 1 18.8-4.3M22 12.5a10 10 0 0 1-18.8 4.3"></path>
      </svg>
      Check for Updates
    `;
    showMessage('Failed to check for updates', 'error');
  }
});

// Get app version and display it
async function loadVersionInfo() {
  try {
    const version = await ipcRenderer.invoke('get-app-version');
    versionInfo.textContent = `Version ${version}`;
  } catch (error) {
    console.error('Failed to get version:', error);
  }
}

// Load settings
async function loadSettings() {
  try {
    const settings = await ipcRenderer.invoke('get-settings');
    
    // Update frequency
    if (settings.updateFrequency) {
      updateFrequency.value = settings.updateFrequency;
    }
    
    // Show dock icon
    if (settings.showDockIcon !== undefined) {
      if (settings.showDockIcon) {
        showDockIconToggle.classList.add('active');
      } else {
        showDockIconToggle.classList.remove('active');
      }
    }
    
    // Start at login
    if (settings.startAtLogin !== undefined) {
      if (settings.startAtLogin) {
        startAtLoginToggle.classList.add('active');
      } else {
        startAtLoginToggle.classList.remove('active');
      }
    }
  } catch (error) {
    console.error('Failed to load settings:', error);
  }
}

// Update frequency change
updateFrequency.addEventListener('change', async (e) => {
  try {
    await ipcRenderer.invoke('set-update-frequency', e.target.value);
    showMessage('Update frequency saved', 'success');
  } catch (error) {
    showMessage('Failed to save update frequency', 'error');
  }
});

// Show dock icon toggle
showDockIconToggle.addEventListener('click', async () => {
  const isActive = showDockIconToggle.classList.contains('active');
  const newValue = !isActive;
  
  // Update UI immediately for better UX
  if (newValue) {
    showDockIconToggle.classList.add('active');
  } else {
    showDockIconToggle.classList.remove('active');
  }
  
  try {
    const result = await ipcRenderer.invoke('set-show-dock-icon', newValue);
    if (result.success) {
      showMessage('Setting saved', 'success');
    } else {
      // Revert UI if failed
      if (newValue) {
        showDockIconToggle.classList.remove('active');
      } else {
        showDockIconToggle.classList.add('active');
      }
      showMessage('Failed to save setting', 'error');
    }
  } catch (error) {
    // Revert UI if error
    if (newValue) {
      showDockIconToggle.classList.remove('active');
    } else {
      showDockIconToggle.classList.add('active');
    }
    showMessage('Failed to save setting', 'error');
  }
});

// Start at login toggle
startAtLoginToggle.addEventListener('click', async () => {
  const isActive = startAtLoginToggle.classList.contains('active');
  try {
    await ipcRenderer.invoke('set-start-at-login', !isActive);
    if (!isActive) {
      startAtLoginToggle.classList.add('active');
    } else {
      startAtLoginToggle.classList.remove('active');
    }
    showMessage('Setting saved', 'success');
  } catch (error) {
    showMessage('Failed to save setting', 'error');
  }
});

// Flush DNS button
flushDnsBtn.addEventListener('click', async () => {
  // Reset any previous state
  flushDnsBtn.classList.remove('success', 'error');
  flushDnsBtn.disabled = true;
  flushDnsBtn.classList.add('loading');
  flushDnsBtn.innerHTML = 'Flushing DNS Cache...';
  
  try {
    const result = await ipcRenderer.invoke('flush-dns');
    
    // Remove loading state
    flushDnsBtn.classList.remove('loading');
    
    if (result.success) {
      // Show success state
      flushDnsBtn.classList.add('success');
      flushDnsBtn.innerHTML = `
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
          <path d="M20 6L9 17l-5-5"></path>
        </svg>
        DNS Cache Flushed
      `;
      showMessage('DNS cache flushed successfully', 'success');
      
      // Reset to normal state after 2 seconds
      setTimeout(() => {
        flushDnsBtn.classList.remove('success');
        flushDnsBtn.innerHTML = `
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
            <path d="M21.5 2v6h-6M2.5 22v-6h6M2 11.5a10 10 0 0 1 18.8-4.3M22 12.5a10 10 0 0 1-18.8 4.3"></path>
          </svg>
          Flush DNS Cache
        `;
        flushDnsBtn.disabled = false;
      }, 2000);
    } else {
      // Show error state
      flushDnsBtn.classList.add('error');
      flushDnsBtn.innerHTML = `
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
          <circle cx="12" cy="12" r="10"></circle>
          <line x1="12" y1="8" x2="12" y2="12"></line>
          <line x1="12" y1="16" x2="12.01" y2="16"></line>
        </svg>
        Failed
      `;
      showMessage(result.message || 'Failed to flush DNS cache', 'error');
      
      // Reset to normal state after 2 seconds
      setTimeout(() => {
        flushDnsBtn.classList.remove('error');
        flushDnsBtn.innerHTML = `
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
            <path d="M21.5 2v6h-6M2.5 22v-6h6M2 11.5a10 10 0 0 1 18.8-4.3M22 12.5a10 10 0 0 1-18.8 4.3"></path>
          </svg>
          Flush DNS Cache
        `;
        flushDnsBtn.disabled = false;
      }, 2000);
    }
  } catch (error) {
    // Remove loading state
    flushDnsBtn.classList.remove('loading');
    
    // Show error state
    flushDnsBtn.classList.add('error');
    flushDnsBtn.innerHTML = `
      <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
        <circle cx="12" cy="12" r="10"></circle>
        <line x1="12" y1="8" x2="12" y2="12"></line>
        <line x1="12" y1="16" x2="12.01" y2="16"></line>
      </svg>
      Failed
    `;
    showMessage('Failed to flush DNS cache', 'error');
    
    // Reset to normal state after 2 seconds
    setTimeout(() => {
      flushDnsBtn.classList.remove('error');
      flushDnsBtn.innerHTML = `
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
          <path d="M21.5 2v6h-6M2.5 22v-6h6M2 11.5a10 10 0 0 1 18.8-4.3M22 12.5a10 10 0 0 1-18.8 4.3"></path>
        </svg>
        Flush DNS Cache
      `;
      flushDnsBtn.disabled = false;
    }, 2000);
  }
});

// Initialize on load
updateStatus();
loadVersionInfo();
loadSettings();
