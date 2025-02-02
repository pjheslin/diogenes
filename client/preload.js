const { contextBridge, ipcRenderer } = require('electron')

contextBridge.exposeInMainWorld('electron', {
  firstrunSetupMain: () => ipcRenderer.invoke('firstrunSetupMain'),
  getport: () => ipcRenderer.invoke('getport'),
  dbOpenDialog: (prop, dbName) => ipcRenderer.invoke('dbOpenDialog', prop, dbName),
  authtabExists: (folderPath) => ipcRenderer.invoke('authtabExists', folderPath),
  exportPathPick: () => ipcRenderer.invoke('exportPathPick'),
  findText: (string, direction) => ipcRenderer.invoke('findText', string, direction),
  cssWriteFont: (font) => ipcRenderer.invoke('cssWriteFont', font),
  cssReadFont: () => ipcRenderer.invoke('cssReadFont'),
  cssRevertFont: () => ipcRenderer.invoke('cssRevertFont'),
  getFonts: () => ipcRenderer.invoke('getFonts'),
  showPDF: (path, external) => ipcRenderer.invoke('showPDF', path, external),
  // Not used yet, but might be useful 
  saveFile: () => ipcRenderer.invoke('saveFile'),
  printToPDF: () => ipcRenderer.invoke('printToPDF')
})
