const { contextBridge, ipcRenderer } = require('electron');
contextBridge.exposeInMainWorld('desktop', {
  close: () => ipcRenderer.send('window:close'),
  minimize: () => ipcRenderer.send('window:minimize'),
  pin: value => ipcRenderer.invoke('window:pin', value),
  resize: value => ipcRenderer.invoke('window:resize', value),
  corner: value => ipcRenderer.invoke('window:corner', value),
  palette: rect => ipcRenderer.invoke('video:palette', rect),
  frame: rect => ipcRenderer.invoke('video:frame', rect),
  preferences: () => ipcRenderer.sendSync('preferences:get'),
  savePreferences: value => ipcRenderer.send('preferences:save', value)
});
