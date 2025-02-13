var picture_dir = 'images/';
var externalDict = '';
var englishDict = '';

function stopSpinningCursor() {
    // Turn off spinning cursor
    var body = document.getElementsByTagName("BODY")[0];
    body.classList.remove("waiting");
}

window.addEventListener("load", function() {
  stopSpinningCursor();
  addListeners()

  if (!isElectron()) {
    var settings = document.getElementById('settings-non-electron')
    settings.innerHTML = 'View or change <a href="Settings.cgi">current settings</a>.<br/>'
  }

  var dio_form = document.getElementById("form");
  if (dio_form.externalDict) {
    externalDict = dio_form.externalDict.value    
  }
  if (dio_form.englishDict) {
    englishDict = dio_form.englishDict.value
  }
  
  // If we have jumped to a passage from a lexicon, show that entry again after loading.
  if (dio_form.JumpFromShowLexicon &&
      dio_form.JumpFromShowLexicon.value == 'yes') {
    jumpFrom();
  }
  // If we have stored a previous Perseus query, provide facility to show it again.
  else if (dio_form.JumpFromQuery.value &&
           dio_form.JumpFromQuery.value != '') {
    var restore = document.getElementById('header_restore');
    restore.classList.remove('invisible');
  }
})

function addListeners () {
  document.addEventListener('keydown', event => {
    if (event.key === 'Escape' || event.keyCode === 27) {
      sidebarDismiss();
    }
    if ((event.metaKey || event.ctrlKey) && event.code == 'Period') {
      document.getElementById('browser_forward_submit').click();
    }
    if ((event.metaKey || event.ctrlKey) && event.code == 'Comma') {
      document.getElementById('browser_back_submit').click();
    }
  })
}

function isElectron () {
    if (typeof navigator === 'object' && typeof navigator.userAgent === 'string' && navigator.userAgent.indexOf('Electron') >= 0) {
        return true;
    }
}

async function openPDF (path) {
  var dio_form = document.getElementById("form");
  var externalPdfViewer = dio_form.externalPdfViewer.value
  if (path) {
    if (isElectron()) {
      var retVal = await window.electron.showPDF(path, externalPdfViewer)
      // Always seems to return false
      // if (!retVal) {
      //   window.open(path)
      // }
    }
    else {
      window.open(path)
    }
  }
}


// Select All for the checkboxes
function setAll() {
    with (document.form) {
        for (i = 0; i < elements.length; i++) {
            if (elements[i].name == "word_list" ||
                elements[i].name == "author_list" ||
                elements[i].name == "works_list" ||
                elements[i].name == "lemma_list") {
                elements[i].checked = true;
                elements[i].selected = true;
            }
        }
    }
}

function PerseusURI (action, lang, query, popup, enc) {
  var uri = `Perseus.cgi?do=${action}&lang=${lang}&q=${query}`
  if (popup) {
    uri = uri + `&popup=${popup}`
  }
  if (enc) {
    uri = uri + `&inp_enc=${enc}`
  }
  if (externalDict) {
    encodedDict = encodeURIComponent(externalDict)
    uri = uri + `&dict=${encodedDict}`
  }
  return uri
}

// AJAX stuff
var req = null;

function new_page (action, lang, query){
  // Popup page
  window.location.href = PerseusURI(action, lang, query, 1) 
}

function sendRequest(action, lang, query, enc) {
  // Spinning cursor
  var body = document.getElementsByTagName("BODY")[0]
  body.classList.add("waiting")
  
  // Save the Perseus query in main page to reinstate it after JumpTo
  var dio_form = document.getElementById("form")
  dio_form.JumpFromQuery.value = query
  dio_form.JumpFromAction.value = action
  dio_form.JumpFromLang.value = lang
  
  /* If we just want a popup, skip the AJAX fancy stuff*/
  var sidebar = document.getElementById("sidebar")
  var sidebarClass = sidebar.getAttribute("class")
  if (sidebarClass == "sidebar-popup") {
    try {
      var perseusWin = window.open(PerseusURI(action, lang, query, 1),
                                   'Perseus Data')
    } catch(e) { alert('You have requested that Perseus data be displayed in a pop-up window, but you appear to have disallowed pop-ups from this web site. '
                       + e )
    }
  }
  else if (sidebarClass == "sidebar-newpage") {
    new_page(action, lang, query)
  }
  else {
    /* Check for running connections */
    if (req != null && req.readyState != 0 && req.readyState != 4) {
      req.abort()
    }
    if (window.XMLHttpRequest) {
      req = new XMLHttpRequest()     // Firefox, Safari, ...
    } else if (window.ActiveXObject) {
      req = new ActiveXObject("Microsoft.XMLHTTP")  // Internet Explorer
    }
    req.onreadystatechange = stateHandler
    // For safety, we should really use encodeURIComponent() to
    // encode these params and then decode them in Perseus.cgi.
    // Enc is to send utf8 from user input, as opposed to text links,
    // which use transliteration.
    var uri = PerseusURI(action, lang, query, false, enc)
    req.open("GET", uri);
    req.send();
    
    return true;
  }
  return true;
}

function stateHandler() {
    if (req.readyState == 4) {
        if (req.status && req.status == 200) {
            showPerseus();
        }
        /* IE returns a status code of 0 on some occasions, so ignore this case */
        else if (req.status != 0)
        {
            failedConnect();
        }
    }
    return true;
}

function failedConnect () {
    alert("Could not get Perseus data!");
}

function showPerseus () {
    var sidebar = document.getElementById("sidebar");
    if (sidebar == null) {
        alert("Error: no sidebar");
    }
    else {
        sidebar.innerHTML = req.responseText;
    }
    var sidebarClass = sidebar.getAttribute("class");
    if (sidebarClass == "sidebar-full") {
        var mainWindow = document.getElementById("main_window");
        mainWindow.setAttribute("class", "main-hidden");
    }
    var splash = document.getElementById("splash");
    if (splash) {
        sidebarFullscreen();
    }
    else {
        sidebarControl();
    }
    // Turn off spinning cursor
    var body = document.getElementsByTagName("BODY")[0];
    body.classList.remove("waiting");
}

function sidebarControl () {
    var sidebar = document.getElementById("sidebar");
    var sidebarClass = sidebar.getAttribute("class");
    var sidebarControl = document.getElementById("sidebar-control");
    var splash = document.getElementById("splash");

    if (splash) {
        // Do not show split screen control on splash.
        sidebarControl.innerHTML =
            '<a onClick="sidebarDismiss();">' +
            `<img id="dismiss" src="${picture_dir}dialog-close.png" srcset="${picture_dir}dialog-close.hidpi.png 2x" alt="Dismiss" /><div class="dismiss_button_text">Dismiss</div></a>`;
    }
    else {
        if (sidebarClass == 'sidebar-split') {
            sidebarControl.innerHTML =
                '<a onClick="sidebarFullscreen();">' +
                `<img id="fullscreen" src="${picture_dir}view-fullscreen.png" srcset="${picture_dir}view-fullscreen.hidpi.png 2x" alt="Fullscreen" /></a>`;
        } else if (sidebarClass == 'sidebar-full') {
            sidebarControl.innerHTML =
            '<a onClick="sidebarSplitscreen();">' +
            `<img id="splitscreen" src="${picture_dir}view-restore.png" srcset="${picture_dir}view-restore.hidpi.png 2x" alt="Split Screen" /></a>`;
        }
        sidebarControl.innerHTML +=
            '<a onClick="sidebarDismiss();">' +
            `<img id="dismiss" src="${picture_dir}dialog-close.png" srcset="${picture_dir}dialog-close.hidpi.png 2x" alt="Dismiss" /></a>`;
    }
}

function sidebarDismiss () {
    var sidebar = document.getElementById("sidebar");
    var mainWindow = document.getElementById("main_window");
    var sidebarControl = document.getElementById("sidebar-control");
    sidebar.innerHTML = "";
    sidebarControl.innerHTML = "";
    mainWindow.setAttribute("class", "main-full");
    if (current_parse) {
        current_parse.classList.remove("highlighted-word");
    }
}

function sidebarFullscreen () {
    var sidebar = document.getElementById("sidebar");
    var mainWindow = document.getElementById("main_window");
    sidebar.setAttribute("class", "sidebar-full");
    mainWindow.setAttribute("class", "main-hidden");
    sidebarControl();
}

function sidebarSplitscreen () {
    var sidebar = document.getElementById("sidebar");
    var mainWindow = document.getElementById("main_window");
    sidebar.setAttribute("class", "sidebar-split");
    mainWindow.setAttribute("class", "main-full");
    sidebarControl();
}

var current_parse
function highlight (element) {
    if (current_parse) {
        current_parse.classList.remove("highlighted-word");
    }
    current_parse = element
    current_parse.classList.add("highlighted-word");
}

// For historical reasons, element and its text content are passed
// separately; this also permits us to parse all of a hyphenated word
// while highlighting the part that was clicked.
function parse_grk (word, element) {
    if (typeof element !== 'undefined') { highlight(element) }
    sendRequest("parse", "grk", word);
}
function parse_lat (word, element) {
    if (typeof element !== 'undefined') { highlight(element) }
    sendRequest("parse", "lat", word);
}
function parse_eng (word, element) {
  if (typeof element !== 'undefined') { highlight(element) }
  var features = 'width=600,height=600,left=' + (window.screen.width - 600) + ',top=' + (window.screen.height - 600)
  if (englishDict == 'gcide') {
    try {
      var perseusWin = window.open(PerseusURI('parse', 'eng', word, true),
                                   'Gcide (Webster 1913)', features)
    } catch(e) {
      alert('Please enable pop-ups. '+ e )
    }
  }
  else {
    var href = englishDict + word
    window.open(href, 'English Dictionary', features)
  }
}

// These put the results in a new page
function parse_grk_page (word) {
    new_page("parse", "grk", word);
}
function parse_lat_page (word) {
    new_page("parse", "lat", word);
}
function parse_eng_page (word) {
    new_page("parse", "eng", word);
}

function getEntrygrk (loc) {
    sendRequest("get_entry", "grk", loc);
    window.scrollTo(0,0);
}
function getEntrylat (loc) {
    sendRequest("get_entry", "lat", loc);
    window.scrollTo(0,0);
}
function getEntryeng (loc) {
    sendRequest("get_entry", "eng", loc);
    window.scrollTo(0,0);
}

function prevEntrygrk (loc) {
    sendRequest("prev_entry", "grk", loc);
    window.scrollTo(0,0);
}
function prevEntrylat (loc) {
    sendRequest("prev_entry", "lat", loc);
    window.scrollTo(0,0);
}
function prevEntryeng (loc) {
    sendRequest("prev_entry", "eng", loc);
    window.scrollTo(0,0);
}

function nextEntrygrk (loc) {
    sendRequest("next_entry", "grk", loc);
    window.scrollTo(0,0);
}
function nextEntrylat (loc) {
    sendRequest("next_entry", "lat", loc);
    window.scrollTo(0,0);
}
function nextEntryeng (loc) {
    sendRequest("next_entry", "eng", loc);
    window.scrollTo(0,0);
}

function jumpTo (loc) {
    var dio_form = document.getElementById("form");
    dio_form.JumpToFromPerseus.value = loc;
    document.form.submit();
}

function jumpFrom (loc) {
    // After jumping to a new text passage, show the lexicon entry from whence we have jumped in sidebar.
    var dio_form = document.getElementById("form");
    var query = dio_form.JumpFromQuery.value;
    var action = dio_form.JumpFromAction.value;
    var lang = dio_form.JumpFromLang.value;
    sendRequest(action, lang, query);
}

function getFont () {
    var dio_form = document.getElementById("form");
    return dio_form.FontName.value;
}

function toggleLemma (num) {
    var img = document.getElementById("lemma_"+num);
    if (img.getAttribute("src") == picture_dir + "opened.png") {
        img.setAttribute("src",picture_dir + "closed.png");
        img.setAttribute("srcset",picture_dir + "closed.hidpi.png 2x");
        var span = document.getElementById("lemma_span_"+num);
        span.setAttribute("class", "lemma_span_invisible");

    }
    else if (img.getAttribute("src") == picture_dir + "closed.png") {
        img.setAttribute("src",picture_dir + "opened.png");
        img.setAttribute("srcset",picture_dir + "opened.hidpi.png");
        var span = document.getElementById("lemma_span_"+num);
        span.setAttribute("class", "lemma_span_visible");
    }
}

function selectVisible (bool) {
    var elements = document.form.getElementsByTagName("span");
    for (i = 0; i < elements.length; i++) {
        if (elements[i].className == "lemma_span_visible") {
            var subspan = elements[i].getElementsByTagName("span");
            for (j = 0; j < subspan.length; j++) {
                if (subspan[j].className == "form_span_visible") {
//                     alert(boxes[j].className);
                    var boxes = subspan[j].getElementsByTagName("input");
                    boxes[0].checked = bool;
                    boxes[0].selected = bool;
                }
            }
        }
    }
}

function formFilter () {
    var text = document.getElementById('form_filter').value;
    var re = /[\s,]/;
    var textList = text.split(re);
    var elements = document.form.getElementsByTagName("span");
    for (i = 0; i < elements.length; i++) {
        var myClass = elements[i].className;
        if (myClass == "form_span_visible" || myClass == "form_span_invisible") {
            var infl = elements[i].getAttribute("infl");
//              alert(infl);
            for (var j = 0; j < textList.length; j++) {
//                 if (textList[j] != "" && infl.indexOf(textList[j]) != -1) {
                if (infl.indexOf(textList[j]) != -1) {
//                     alert(infl);
                    elements[i].className = "form_span_visible";
                }
                else {
                    elements[i].className = "form_span_invisible";
                }
            }
        }
    }
}

