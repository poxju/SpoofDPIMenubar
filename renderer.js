const { ipcRenderer } = require('electron');

const toggleSwitch = document.getElementById('toggleSwitch');
const statusText = document.getElementById('statusText');
const errorText = document.getElementById('errorText');
const messageEl = document.getElementById('message');

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

// Initialize on load
updateStatus();
