const {app, BrowserWindow, Menu, MenuItem, ipcMain, session, dialog} = require('electron')
const {spawn} = require('child_process')
const path = require('path')
const process = require('process')
const fs = require('fs')
const console = require('console')
const fontList = require('./node-font-list/index.js')

// We don't use this and it causes crashes on Windows/Linux machines
// with glitchy drivers.
app.disableHardwareAcceleration()

// Keep a global reference of the window objects, to ensure they won't
// be closed automatically when the JavaScript object is garbage collected.
let windows = []

// Same for server, keep it globally to ensure it isn't garbage collected.
let server

let dioSettings = {}
let lockFile

let startupDone = false

let currentLinkURL = null

//const webprefs = {contextIsolation: true, nodeIntegration: false, preload: path.join(app.getAppPath(), 'preload.js')}
const webprefs = {contextIsolation: true, nodeIntegration: false, preload: path.resolve(__dirname, 'preload.js')}
// const webprefs = {contextIsolation: true, nodeIntegration: false}
const winopts = {icon: path.join(app.getAppPath(), 'assets', 'icon.png')}

const settingsPath = app.getPath('userData')
const winStatePath = path.join(settingsPath, 'windowstate.json')
const prefsFile = path.join(settingsPath, 'diogenes.prefs')
const cssConfigFile = path.join(settingsPath, 'config.css')



const versionFile = path.resolve(__dirname, 'version.js')
var currentVersion = "0.0"
if (fs.existsSync(versionFile)) {
  currentVersion = settingsFromFile(versionFile).version
}

// Ensure the app is single-instance (see 'second-instance' event
// handler below)
function initialise() {
  const gotTheLock = app.requestSingleInstanceLock()

  if (!gotTheLock) {
    return app.quit()
  }
}

initialise()

// Set up Open Link context menu
// TODO: there is probably a better way to open links than using the
//       currentLinkURL global variable
const linkContextMenu = new Menu()
linkContextMenu.append(new MenuItem({label: 'Open', click: (item, win) => {
  if(currentLinkURL) {
    win.loadURL(currentLinkURL)
    currentLinkURL = null
  }
}}))
linkContextMenu.append(new MenuItem({label: 'Open in New Window', click: (item, win) => {
  if(currentLinkURL) {
    let newwin = createWindow(win, 20, 20)
    newwin.loadURL(currentLinkURL)
    currentLinkURL = null
  }
}}))

// Create a new window (either the first or an additional one)
function createWindow (oldWin, offset_x, offset_y, defaultPos) {
  var winstate = getWindowState(winStatePath)

  if (defaultPos) {
    // These values can get messed up when swapping displays so
    // that all windows are put off-screen, so we need to provide
    // an emergency way for the user to reset them.
    x = 0
    y = 0
    w = 800
    h = 600
  }
  else if (oldWin == null) {
    // Use saved window state if available
    if(winstate && winstate.bounds) {
      x = winstate.bounds.x + offset_x
      y = winstate.bounds.y + offset_y
      w = winstate.bounds.width
      h = winstate.bounds.height
    } else {
      x = undefined
      y = undefined
      w = 800
      h = 600
    }
  }
  else {
    const pos = oldWin.getPosition()
    x = pos[0]
    y = pos[1]
    // Add desired offset from existing window.
    x = x + offset_x
    y = y + offset_y
    if(winstate && winstate.bounds) {
      w = winstate.bounds.width
      h = winstate.bounds.height
    } else {
      w = 800
      h = 600
    }
  }

  let win = new BrowserWindow({x: x, y: y, width: w, height: h, spellcheck: false,
	                       show: false, webPreferences: webprefs, winopts})

  if(winstate && winstate.maximzed) {
    win.maximize()
  }

  // Hide window until everything has loaded
  win.on('ready-to-show', function() {
    win.show()
    win.focus()
    saveWindowState(win, winStatePath)
  })

  // Save window state whenever it changes
  let changestates = ['resize', 'move', 'close']
  changestates.forEach(function(e) {
    win.on(e, function() {
      saveWindowState(win, winStatePath)
    })
  })

  return win
}

function checkVersion (win) {
  // Retrieve previous version and compare with current.  If this is
  // a new version of Diogenes, we have to clear the HTTP cache, or
  // we may continue to use the js, css, etc. files from the
  // obsolete version.
  win.webContents.executeJavaScript('localStorage.getItem("diogenesVersion")')
    .then( (oldVersion) => {
      if (oldVersion != currentVersion) {
        console.log('Old version: '+oldVersion+'; Current version: '+currentVersion)
        win.webContents.session.clearCache()
          .then( () => {
            console.log('Deleted stale cache')
            win.webContents.reload()
          } )
          .catch( (e) => {console.log('Failed to delete stale cache: '+e)} )
        win.webContents.reload()
        win.webContents.executeJavaScript('localStorage.setItem("diogenesVersion", '+'"'+currentVersion+'")')
          .then( () => {console.log('New version number saved')} )
          .catch( (e) => {console.log('Failed to save new version number: '+e)} )
      }})
}

// Create the initial window and start the diogenes server
function createFirstWindow () {
  lockFile = path.join(settingsPath, 'diogenes-lock.json')
  process.env.Diogenes_Config_Dir = settingsPath

  // Set the Content Security Policy headers
  // const csp = "default-src 'self' *.uchicago.edu *.logeion.org 'unsafe-inline' localhost:*"
  const csp = "default-src 'self' localhost:* *.uchicago.edu *.logeion.org 'unsafe-inline'"
  session.defaultSession.webRequest.onHeadersReceived((details, callback) => {
    callback({ responseHeaders: Object.assign({
      "Content-Security-Policy": [ csp ]
    }, details.responseHeaders)})
  })

  win = createWindow(null, 0, 0);

  win.webContents.on("dom-ready", () => {
    checkVersion(win)
  })

  // Remove any stale lockfile
  if (fs.existsSync(lockFile)) {
    fs.unlinkSync(lockFile)
  }

  loadWhenLocked(lockFile, prefsFile, win)
  server = startServer()

  const menu = Menu.buildFromTemplate(initializeMenuTemplate())
  Menu.setApplicationMenu(menu)
}

// Track each window in a global 'windows' array, and set up the
// context menu
app.on('browser-window-created', (event, win) => {
  // Track window in global windows object
  windows.push(win)

  win.on('closed', () => {
    // Delete window id from list of windows
    windows.splice(windows.indexOf(win), 1)
  })

  // Intercept and handle new-window requests (e.g. from shift-click), to
  // prevent child windows being created which would die if the parent was
  // killed. This was something to do with the new window being a "guest"
  // window, which I am intentionally setting here, to fix the issue. The
  // Electron documentation states that it should be set for "failing to
  // do so may result in unexpected behavior" but I haven't seen any yet.
  win.webContents.setWindowOpenHandler(({ url }) => {
    let newWin = createWindow(win, 20, 20)
    newWin.once('ready-to-show', () => newWin.show())
    newWin.loadURL(url)
    return { action: 'deny' };
  })
  
  // Load context menu
  win.webContents.on('context-menu', (e, params) => {
    // Only load on links, which aren't javascript links
    if(params.linkURL != "" && params.linkURL.indexOf("javascript:") != 0) {
      currentLinkURL = params.linkURL
      linkContextMenu.popup(win, params.x, params.y)
    } else {
      currentLinkURL = null
    }
  })

  // Clear "find" highlighting when we navigate to a new page
  win.webContents.on('did-start-loading', (event, result) => {
    win.webContents.stopFindInPage('clearSelection')
  })
  
})

// This method will be called when Electron has finished
// initialization and is ready to create browser windows.
// Some APIs can only be used after this event occurs.
app.on('ready', createFirstWindow)

// Quit when all windows are closed.
app.on('window-all-closed', () => {
  // On macOS it is common for applications and their menu bar
  // to stay active until the user quits explicitly with Cmd + Q
  if (process.platform !== 'darwin') {
    app.quit()
  }
})

// Try to kill the server when the app being closed
app.on('will-quit', () => {
  if(server) {
    try {
      server.kill()
    } catch(e) {
      console.log("Couldn't kill server")
    }
  }
  fs.unlinkSync(lockFile)
})


// If a user tries to open a second instance of diogenes, catch that
// and focus an existing window instead
app.on('second-instance', () => {
  if(windows.length == 0) {
    return false
  }
  if(windows[0].isMinimized()) {
    windows[0].restore()
  }
  windows[0].focus()
})

// Only allow loading content from localhost
app.on('web-contents-created', (event, contents) => {
  contents.on('will-navigate', (event, navigationUrl) => {
    const url = new URL(navigationUrl)
    if (url.hostname !== 'localhost') {
      event.preventDefault()
    }
  })
})

// Start diogenes-server.pl
function startServer () {
  // For Mac and Unix, we assume perl is in the path
  let perlName = 'perl'
  if (process.platform == 'win32') {
    perlName = path.join(app.getAppPath(), '..', '..', 'strawberry', 'perl', 'bin', 'perl.exe')
  }

  // server/ can be either at ../server or ../../server depending on whether
  // we're running a packaged or development version, so try both
  let serverPath = path.join(app.getAppPath(), '..', 'server', 'diogenes-server.pl')
  if (!fs.existsSync(serverPath)) {
    serverPath = path.join(app.getAppPath(), '..', '..', 'server', 'diogenes-server.pl')
  }

  let server = spawn(perlName, [serverPath], {'windowsHide': true})
  server.stdout.on('data', (data) => {
    console.log('server stdout: ' + data)
  })
  server.stderr.on('data', (data) => {
    console.log('server stderr: ' + data)
  })
  server.on('close', (code) => {
    console.log('Diogenes server exited (or failed to start)')
  })
  return server
}

// Load settings in lockfile into an object
function settingsFromFile(fn) {
  let s = fs.readFileSync(fn, {'encoding': 'utf8'})
  return JSON.parse(s)
}

// Watch for the lockfile diogenes-server sets, and once it's there
// load the first page.
function loadWhenLocked(lockFile, prefsFile, win) {
  // TODO: consider setting a timeout for this, in case the server
  //       doesn't start correctly for some reason.
  fs.watch(path.dirname(lockFile), function(event, filename) {
    if(startupDone) {
      return
    }

    if(filename != path.basename(lockFile)) {
      return
    }

    if(!fs.existsSync(lockFile)) {
      return
    }

    dioSettings = settingsFromFile(lockFile)

    if(dioSettings.port === undefined || dioSettings.pid === undefined) {
      console.error("Error, no port or pid settings found in lockFile")
      app.quit()
    }

    loadFirstPage(prefsFile, win)

    startupDone = true
  })
}

// Check if a database folder has been set
function checkDbSet(prefsFile) {
  let s
  try {
    s = fs.readFileSync(prefsFile, 'utf8')
  } catch(e) {
    return false
  }
  let re = new RegExp('(phi|tlg|ddp)_dir .*')
  if(re.test(s)) {
    return true
  }
  return false
}

// Save window dimensions and state to a file
function saveWindowState(win, path) {
  let s = {}
  s.maximized = win.isMaximized()
  if(!s.maximized) {
    s.bounds = win.getBounds()
  }
  try {
    fs.writeFileSync(path, JSON.stringify(s))
  } catch(e) {
    return false
  }
  return true
}

// Load window dimensions and state from a file
function getWindowState(path) {
  let s
  let ret
  try {
    s = fs.readFileSync(path, {'encoding': 'utf8'})
  } catch(e) {
    return false
  }
  try {
    ret = JSON.parse(s)
  } catch(e) {
    return false
  }
  return ret
}

// Load either the Diogenes homepage or the firstrun page
function loadFirstPage(prefsFile, win) {
  if(!fs.existsSync(prefsFile) || !checkDbSet(prefsFile)) {
    win.loadFile("pages/firstrun.html")
  } else {
    win.loadURL('http://localhost:' + dioSettings.port)
  }
}

function makeFontWin (win) {
  return new BrowserWindow({
    parent: win,
    show: true,
    modal: true,
    width: 600,
    height: 400,
    resizable: false,
    movable: false,
    frame: true,
    transparent: false,
    fullscreen: false,
    spellcheck: false,
    webPreferences: webprefs
  })
}

function makeNewWin (win, defaultPos) {
  if (typeof win === 'undefined') {
    // No existing application window (for Mac only)
    return createWindow(null, 0, 0, defaultPos)
  } else {
    // Additional window
    return createWindow(win, 20, 20, defaultPos)
  }
}

// Menus
function initializeMenuTemplate () {
  const template = [
    {
      label: 'File',
      submenu: [
        {
          label: 'New Window',
          accelerator: 'CmdOrCtrl+N',
          click: (menu, win) => {
            let newWin = makeNewWin(win, false)
            newWin.loadURL('http://localhost:' + dioSettings.port)
          }
        },
        {
          label: 'New Win (reset position)',
          accelerator: 'CmdOrCtrl+!',
          click: (menu, win) => {
            let newWin = makeNewWin(win, true)
            newWin.loadURL('http://localhost:' + dioSettings.port)
          }
        },
        {
          label: 'Save File',
          accelerator: 'CmdOrCtrl+S',
          click: (menu, win) => {
            savePath = saveFile()
            console.log('Saving to: ' + savePath)
            win.webContents.savePage(savePath, 'HTMLOnly',
                                     function(error) {
                                       if (!error)
                                         console.log("Saved page successfully")
                                     })
          }
        },
        {
          label: 'Print to PDF',
          accelerator: 'CmdOrCtrl+P',
          click: (menu, win) => {
            pdfPath = printToPDF()
            console.log('Printing to: ' + printPath)
            win.webContents.printToPDF({}).then(data => {
              fs.writeFile(pdfPath, data, (error) => {
                if (error) throw error
                console.log(`Wrote PDF successfully to ${pdfPath}`)
              })
            }).catch(error => {
              console.log(`Failed to write PDF to ${pdfPath}: `, error)
            })
          }
        },
        {
          label: 'Set Folder Locations',
          accelerator: 'CmdOrCtrl+B',
          click: (menu, win) => {
            let newWin = createWindow(win, 20, 20)
            newWin.loadFile("pages/firstrun.html")
          }
        },
        {
          label: 'Change Font',
          accelerator: 'CmdOrCtrl+U',
          click: (menu, win) => {
            let newWin = makeFontWin()
            newWin.loadFile("pages/font.html")
          }
        },
        {
          label: 'Download TLL PDFs',
          click: (menu, win) => {
            if (tllConfirm()) {
              let newWin = createWindow(win, 20, 20)
              newWin.loadURL('http://localhost:' + dioSettings.port + '/tll-pdf-download.cgi')
            }
          }
        },
        {
          label: 'Other Settings',
          accelerator: 'CmdOrCtrl+T',
          click: (menu, win) => {
            let newWin = createWindow(win, 20, 20)
	    newWin.loadURL('http://localhost:' + dioSettings.port + '/Settings.cgi')
          }
        },
        {
          label: 'Close Window',
          accelerator: 'CmdOrCtrl+W',
          click: (menu, win) => {
            win.close()
          }
        }
      ]
    },

    {
      label: 'Edit',
      role: 'editMenu'
    },
    {
      label: 'Navigate',
      submenu: [
        {label: 'Stop/Kill',
         accelerator: 'CmdOrCtrl+K',
         click: (menu, win) => {
           let contents = win.webContents
           contents.stop()
           win.webContents.executeJavaScript('stopSpinningCursor()')
         }},
        {label: 'Back',
         accelerator: 'CmdOrCtrl+[',
         click: (menu, win) => {
           let contents = win.webContents
           contents.goBack()
         }},
        {label: 'Forward',
         accelerator: 'CmdOrCtrl+]',
         click: (menu, win) => {
           let contents = win.webContents
           contents.goForward()
         }},
        {label: 'Previous Text',
         accelerator: 'CmdOrCtrl+,',
         click: (menu, win) => {
           win.webContents.executeJavaScript("document.getElementById('browser_back_submit').click()")
         }},
        {label: 'Subsequent Text',
         accelerator: 'CmdOrCtrl+.',
         click: (menu, win) => {
           win.webContents.executeJavaScript("document.getElementById('browser_forward_submit').click()")
         }},
        {label: 'Home Page',
         accelerator: 'CmdOrCtrl+D',
         click: (menu, win) => {
           win.loadURL('http://localhost:' + dioSettings.port)
         }},
        {label: 'Top of Page',
         accelerator: 'Home',
         click: (menu, win) => {
           sendKeybinding(win, 'Home')
         }},
        {label: 'Bottom of Page',
         accelerator: 'End',
         click: (menu, win) => {
           sendKeybinding(win, 'End')
         }},
        {label: 'Reload App',
         click: (menu, win) => {
           win.webContents.reloadIgnoringCache()
         }},

        {type: 'separator'},

        {label: 'Find',
         accelerator: 'CmdOrCtrl+F',
         click: (menu, win) => {
           findText(win)
         }},
        {label: 'Find Next',
         accelerator: 'CmdOrCtrl+G',
         click: (menu, win) => {
           findTargetWin.webContents.findInPage( mySearchText )
         }},
        {label: 'Find Previous',
         accelerator: 'CmdOrCtrl+Shift+G',
         click: (menu, win) => {
           findTargetWin.webContents.findInPage( mySearchText, {'forward': false} )
         }},

      ]
    },
    {
      label: 'View',
      submenu: [
        {role: 'resetZoom',
         label: 'Original Zoom'},
        {role: 'zoomIn'},
        {role: 'zoomOut'},
        {type: 'separator'},
        {role: 'togglefullscreen'},
        {type: 'separator'},
        {role: 'toggleDevTools'}
      ]
    },
    {
      label: 'Window',
      role: 'windowMenu',
    },
    {
      role: 'help',
      submenu: [
        {
          label: 'Learn More',
          click () { require('electron').shell.openExternal('https://d.iogen.es/d') }
        }
      ]
    }
  ]

  if (process.platform === 'darwin') {
    template.unshift({
      label: "Diogenes",
      submenu: [
        {role: 'about'},
        {type: 'separator'},
        {role: 'services', submenu: []},
        {type: 'separator'},
        {role: 'hide'},
        {role: 'hideothers'},
        {role: 'unhide'},
        {type: 'separator'},
        {role: 'quit'}
      ]
    })
    // File menu
    template[1].submenu.push(
      {type: 'separator'},
      {
        label: 'Speak',
        submenu: [
          {role: 'startspeaking'},
          {role: 'stopspeaking'}
        ]
      }
    )
  }

  if (process.platform !== 'darwin') {
    template[0].submenu.push(
      {role: 'quit', accelerator: 'CmdOrCtrl+Q'}
    )
  }

  return template
}

function sendKeybinding (win, code) {
  win.webContents.sendInputEvent({ type: 'keyDown', keyCode: code })
  win.webContents.sendInputEvent({ type: 'char', keyCode: code })
  win.webContents.sendInputEvent({ type: 'keyUp', keyCode: code })
}

// Find-in-page mini-window

let findWin
let findTargetWin;
let mySearchText;

function findText (win) {

  if (win === findWin) {
    // Wrongly called find from active find window
    return
  }
  if (findWin && findWin.isVisible()) {
    // Find window present but unfocused
    findWin.focus()
    return
  }

  findTargetWin = win;
  let findWidth = 340
  let find_x = findTargetWin.getBounds().x + win.getContentBounds().width - findWidth
  let find_y = findTargetWin.getBounds().y

  findWin = new BrowserWindow({
    parent: win,
    show: false,
    modal: false,
    width: findWidth,
    height: 40,
    x: find_x,
    y: find_y,
    resizable: true,
    movable: true,
    frame: false,
    transparent: false,
    fullscreen: false,
    spellcheck: false,
    webPreferences: webprefs
  })
  findWin.once('ready-to-show', () => {
    findWin.show()
    findWin.focus()
  })
  findWin.on('closed', () => {
    win.webContents.stopFindInPage('clearSelection')
    findWin = null
  })

  findWin.loadFile("pages/find.html")
}

//////////// Moved from preload for new security model

app.whenReady().then( () => {
  ipcMain.handle('getport', async (event, arg) => {
    return dioSettings.port
  })
  ipcMain.handle('firstrunSetupMain', async (event, arg) => {
    return firstrunSetupMain()
  })
  ipcMain.handle('dbOpenDialog', async (event, prop, dbName) => {
    return dbOpenDialog(prop, dbName)
  })
  ipcMain.handle('authtabExists', async (event, folderPath) => {
    return authtabExists(folderPath)
  })
  ipcMain.handle('exportPathPick', async (event, arg) => {
    return exportPathPick()
  })
  ipcMain.handle('saveFile', async (event, arg) => {
    return saveFile()
  })
  ipcMain.handle('printToPDF', async (event, arg) => {
    return printToPDF()
  })
  ipcMain.handle('findText', async (event, string, direction) => {
    return findTextRemote(string, direction)
  })
  ipcMain.handle('cssWriteFont', async (event, font) => {
    return cssWriteFont(font)
  })
  ipcMain.handle('cssReadFont', async (event) => {
    return cssReadFont()
  })
  ipcMain.handle('cssRevertFont', async (event) => {
    return cssRevertFont()
  })
  ipcMain.handle('showPDF', async (event, path, external) => {
    return showPDF(path, external)
  })

  ipcMain.handle('getFonts', getFonts)
})

// Support for events arising from the find mini-window
function findTextRemote (string, direction) {
  if (string === "") {
    findTargetWin.webContents.stopFindInPage('clearSelection')
  }
  else {
    if (direction === "next") {
      findTargetWin.webContents.findInPage(string)
    } else {
      findTargetWin.webContents.findInPage(string, {'forward': false})
    }
    mySearchText = string
  }  
}

// Support for firstrun (db settings) page

const dbs = ['PHI', 'TLG', 'DDP', 'TLL_PDF', 'OLD_PDF', 'XML_EXPORT']

function firstrunSetupMain() {
  // Create settings dir, if necessary
  if (!fs.existsSync(settingsPath)) {
    fs.mkdirSync(settingsPath)
  }
  // Read existing db settings
  try {
    data = fs.readFileSync(prefsFile, 'utf8')
  } catch(e) {
    data = null
  }
  return data
}

function dbOpenDialog (prop, dbName) {
  folderPath = dialog.showOpenDialogSync(null, {
    title: `Set ${dbName} location`,
    properties: [prop] }
                                        )
  writeToSettings(dbName, folderPath)
  console.log(dbName + ' location set to: ' + folderPath)
  return folderPath
}

function writeToSettings (dbName, folderPath) {
  if( typeof folderPath === "undefined" ) {
    return
  }
  try {
    data = fs.readFileSync(prefsFile, 'utf8')
  } catch(e) {
    data = '# Created by Diogenes'
  }
  let db_l = dbName.toLowerCase()
  let newLine = `${db_l}_dir "${folderPath}"`
  let re = new RegExp(`^${db_l}_dir.*$`, 'm')
  let newData
  if(re.test(data)) {
    newData = data.replace(re, newLine)
  } else {
    newData = `${data}\n${newLine}`
  }
  fs.writeFileSync(prefsFile, newData)
}

function authtabExists (folderPath)  {
  if (fs.existsSync(`${folderPath}/authtab.dir`) || fs.existsSync(`${folderPath}/AUTHTAB.DIR`) ) {
    return true
  } else {
    return false
  }
}

// Support for setting output dir for XML export

function exportPathPick () {
  xmlPath = dialog.showOpenDialogSync(null, {
    title: 'Set location for XML directory',
    properties: ['openDirectory', 'createDirectory']})
  return xmlPath
}

// Support for File -> Save

function saveFile () {
  savePath = dialog.showSaveDialogSync(null, {
    title: 'Save File Location',
    defaultPath: 'diogenes-output.html',
    properties: ['createDirectory']})
  return savePath
}

// Support for print to PDF

function printToPDF () {
  printPath = dialog.showSaveDialogSync(null, {
    title: 'PDF File Location',
    defaultPath: 'diogenes-print.pdf',
    properties: ['createDirectory']})
  return printPath
}

// Support for confirming TLL downloads

function getTLLpath () {
  try {
    var data = fs.readFileSync(prefsFile, 'utf8')
  } catch(e) {
    dialog.showMessageBoxSync({
      type: 'error',
      message: 'Error. Settings file cannot be read.  Create one at File -> Database Locations'
    })
    return false
  }

  found = data.match(/^tll_pdf_dir\s+\"(.*)\"$/m)
  if (found && found[1]) {
    return found[1]
  } else {
    return false
  }
}

function tllConfirm () {
  // So as to have only one way to set this, we ask the user to
  // set it via DB settings page rather than having a dialog here
  // This needs to agree with value in tll-pdf-download.pl
  
  tllPath = getTLLpath ()
  if (!tllPath) {
    dialog.showMessageBoxSync({
      type: 'error',
      message: 'Error. Location for TLL PDFs has not yet been set.  Specify the location via File -> Database Locations.'
    })
    return false
  }

  var ok = dialog.showMessageBoxSync({
    type: 'question',
    buttons: ['Cancel', 'OK'],
    defaultId: 0,
    title: 'Continue?',
    message: 'Do you want to go ahead and download the PDFs of the Thesaurus Linguae Latinae? They will be saved to: ' + tllPath,
    detail: 'Warning: retrieving these very large files from the website of the Bayerische Akademie der Wissenschaften may take quite a long time. To change the folder where they will be saved, cancel and go to File -> Database Locations.  Click OK to proceed with downloads.'
  })
  if (ok == 1) {
    return true
  } else {
    return false
  }
}

// Support for font selection

// Must await return of promise here 
async function getFonts () {
  fonts = await fontList.getFonts()
  return fonts
}

function cssWriteFont (font) {
  try {
    fs.unlinkSync(cssConfigFile)
  } catch (e) {
    console.log('No existing CSS config.')
  }
  data = `body {
  font-family: '${font}';
}
`
  try {
    fs.writeFileSync(cssConfigFile, data)
  } catch (e) {
    console.log('Could not write CSS file. ', e)
    return e  
  }
  return 'done'
}

function cssReadFont () {
  // Read existing settings
  try {
    data = fs.readFileSync(cssConfigFile, 'utf8')
  } catch (e) {
    return ""
  }
  if (data) {
    let re = new RegExp('font-family:\\s*["\'](.*?)["\'];', 'm')
    let ar = re.exec(data)
    if (ar && ar[1]) {
      return ar[1]
    }
  }
  return ""
}

function cssRevertFont () {
  try {
    fs.unlinkSync(cssConfigFile)
  } catch(e) {
    return e
  }
  return 'done'
}

// Support for opening PDFs

var tllFileMap = {}
function tllFileMapRead () {
  // We just read the file once, if necessary
  if (Object.keys(tllFileMap).length === 0) {
    const tllListPath = path.resolve(__dirname, '..', '..', 'dependencies', 'data', 'tll-pdf-list.txt');
    const tllList = fs.readFileSync(tllListPath, {'encoding': 'utf8'})
    tllList.split("\n").forEach( line => {
      var m = line.match(/^([\d\.o]+)\t(.*)$/)
      if (m) {
        var vol = m[1]
        var filename = m[2]
        if (vol && filename) {
          tllFileMap[vol] = filename 
        } else {
          console.log('Error reading TLL file list:', line)
        }
      }
    })
  }
}

// Select type of PDF
function showPDF (pseudoUrl, external) {
  if (external == 'true') { // a string, not a boolean
    localURL = 'http://localhost:' + dioSettings.port + '/' + pseudoUrl
    require('electron').shell.openExternal(localURL)
    return
  }
  var m = pseudoUrl.match(/^tll-pdf\/(.*?)\.pdf/)
  if (m) {
    vol = m[1]
    return showTLL(vol, pseudoUrl)
  }
  else if (pseudoUrl.match(/^ox-lat-dict\.pdf/)) {
    return showOLD(pseudoUrl)
  }
  else {
    console.log('Bad PDF pseudo-URL:', pseudoUrl)
    return false
  }
}

// If PDF is already open, show existing window
function showTLL (vol, pseudoUrl) {

  var tllDirUntrimmed = getTLLpath()
  if (!tllDirUntrimmed) {
    console.log('Error: tll_pdf_dir not set.')
    dialog.showMessageBoxSync({
      type: 'error',
      message: 'Error. Location for TLL PDFs has not yet been set.  Specify the location via File -> Database Locations.'
    })
    return false
  }
  tllDir = tllDirUntrimmed.replace(/\/$/, '')
  tllFileMapRead()
  var filename = tllFileMap[vol]
  if (!filename) { console.log('Error: filename not found for', vol) }
  var filepath = tllDir + '/' + filename
  if (!fs.existsSync(filepath)) {
    console.log('Error: TLL PDF not found.')
    dialog.showMessageBoxSync({
      type: 'error',
      message: 'Error. TLL PDF not found: ' + filepath
    })
    return false
  }

  if (m = pseudoUrl.match(/page=(\d+)$/)) {
    var page = m[1]
  } else {
    console.log('Error. No page number:', pseudoUrl)
  }
  // We need to use loadURL, not loadFile, for #page= feature
  var tllURL = 'file://' + tllDir + '/' + filename + '#page=' + page
  
  for (const win of BrowserWindow.getAllWindows()){
    if (win.title == filename) {
      // This load fails intermittently, and in any case when it succeeds it reloads the PDF instead of scrolling to the new page, so we just close the window and then open a new one
      // console.log('Re-loading TLL: ', tllURL)
      // win.show()
      // return win.webContents.loadURL(tllURL)
      win.close()
    }
  }
  var win = createWindow(null, 20, 20)
  console.log('Loading TLL: ', tllURL)
  return win.webContents.loadURL(tllURL)
}

var OLDwindow = null

function showOLD (pseudoUrl) {
  oldDirUntrimmed = getOLDpath()
  if (!oldDirUntrimmed) {
    console.log('Error: old_pdf_dir not set.')
    dialog.showMessageBoxSync({
      type: 'error',
      message: 'Error. Location for OLD PDF has not yet been set.  Specify the location via File -> Database Locations.'
    })
    return false
  }
  oldDir = oldDirUntrimmed.replace(/\/$/, '')
  if (m = pseudoUrl.match(/page=(\d+)$/)) {
    var page = m[1]
  } else {
    console.log('Error. No page number:', pseudoUrl)
  }
  // We need to use loadURL, not loadFile, for #page= feature
  var oldURL = 'file://' + oldDir + '#page=' + page
  if (OLDwindow && !OLDwindow.isDestroyed()) {
    // As above
    OLDwindow.close()
  }
  OLDwindow = createWindow(null, 20, 20)
  console.log('Loading OLD: ', oldURL)
  return OLDwindow.webContents.loadURL(oldURL)
}

function getOLDpath () {
  try {
    var data = fs.readFileSync(prefsFile, 'utf8')
  } catch(e) {
    dialog.showMessageBoxSync({
      type: 'error',
      message: 'Error. Settings file cannot be read.  Create one at File -> Database Locations'
    })
    return false
  }

  found = data.match(/^old_pdf_dir\s+\"(.*)\"$/m)
  if (found && found[1]) {
    return found[1]
  } else {
    return false
  }
}
