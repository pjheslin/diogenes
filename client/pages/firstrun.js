const dbs = ['PHI', 'TLG', 'DDP', 'TLL_PDF', 'OLD_PDF', 'XML_EXPORT']

async function firstrunSetup () {
  data = await window.electron.firstrunSetupMain()
  for (let i = 0; i < dbs.length; i++) {
    let db = dbs[i]
    bindClickEvent(db)
    if (data === null) {
      continue
    }
    let db_l = db.toLowerCase()
    let re = new RegExp(`^${db_l}_dir\\s+"?(.*?)"?$`, 'm')
    let ar = re.exec(data)
    if (ar) {
      showPath(db, ar[1])
    }
  }
  port = await window.electron.getport()
  document.getElementById('done').addEventListener('click', () => {
    window.location.href = `http://localhost:` + port
  })
  readyDoneButton()
}

function readyDoneButton() {
  let anyset = 0
  for(let i = 0; i < dbs.length; i++) {
    let d = `${dbs[i]}path`
    if(document.getElementById(d).innerHTML.length > 0) {
      anyset = 1
    }
  }
  if(anyset) {
    document.getElementById('donesection').style.display = 'block'
  }
}

function bindClickEvent(dbName) {
  var prop
  if (dbName == 'OLD_PDF') {
    prop = 'openFile';
  }
  else {
    prop = 'openDirectory';
  }
  
  document.getElementById(`${dbName}button`).addEventListener('click', async () => {
    folderPath = await window.electron.dbOpenDialog(prop, dbName)
    showPath(dbName, folderPath)
  })
}

async function showPath(dbName, folderPath) {
  authtabExists = await window.electron.authtabExists(folderPath)
  document.getElementById(`${dbName}path`).innerHTML = folderPath
  checkmark = document.getElementById(`${dbName}ok`)
  
  if (authtabExists || dbName == 'TLL_PDF' || dbName == 'OLD_PDF' ||
      dbName == 'XML_EXPORT') {
    checkmark.innerHTML = '✓'
    checkmark.classList.remove('warn')
    checkmark.classList.add('valid')
  } else {
    checkmark.innerHTML = '✕ No authtab.dir found; this doesn\'t look like a correct database location'
    checkmark.classList.remove('valid')
    checkmark.classList.add('warn')
  }
}

firstrunSetup()
