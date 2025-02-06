// Dynamic splash-page with sticky choices.  Requires html5
var corpus, query, author;

// Is localStorage available?
var lsTest = function(){
    var test = 'test';
    try {
        localStorage.setItem(test, test);
        localStorage.removeItem(test);
        return true;
    } catch(e) {
        return false;
    }
}();

function save_values () {
    if(lsTest === true){
        if (document.getElementById("corpus_menu")) {
            corpus = document.getElementById("corpus_menu").value;
            localStorage.setItem("corpus", corpus);
        }
        if (document.getElementById("query_text")) {
            query = document.getElementById("query_text").value;
            localStorage.setItem("query", query);
        }
        if (document.getElementById("author_text")) {
            author = document.getElementById("author_text").value;
            localStorage.setItem("author", author);
        }
        // We just use temp storage for splash page state
        if (document.getElementById("action")) {
            action = document.getElementById("action").value;
            sessionStorage.setItem("action", action);
        }

    }
}

window.addEventListener("load", function() {
  // Set up submit handler
  var form = document.getElementById('form');
  if (form.attachEvent) {
    form.attachEvent("submit", processForm)
  }
  else {
    form.addEventListener("submit", processForm)
  }
  // Turn off spinning cursor
  var body = document.getElementsByTagName("BODY")[0]
  body.classList.remove("waiting")
  
  // Set up choices for splash page
  splash_setup()

})
  
function processForm (e) {
    save_values();
    // Stop submit
    if (e.preventDefault) e.preventDefault();
    // Wait cursor
    var body = document.getElementsByTagName("BODY")[0];
    body.classList.add("waiting");

    // Catch and block submission of form for Perseus lookup
    var action = document.getElementById("action").value;
    if (action == 'parse' || action == 'lookup') {
        splashPerseus(action);
        return false;
    }
    else {
        // Submit form
        var form = document.getElementById('form');
        form.submit();
    }
}

function dropdown (menu) {
    document.getElementById(menu).style.display = "block";
}
function dropup (menu) {
    document.getElementById(menu).style.display = "none";
}
function droptoggle (menu) {
    var state = document.getElementById(menu).style.display;
    if (state === "none") {
        dropdown(menu)
    } else {
        dropup(menu)
    }
}

function splashPerseus (action) {
    if (document.getElementById("query_text")) {
        query = document.getElementById("query_text").value;
        const grk = /[\u0370-\u03FF\u1F00-\u1FFF]/;
        if (grk.test(query)) {
            sendRequest(action, "grk", query, 'utf8');
        } else {
            sendRequest(action, "lat", query);
        }
    }
}

var infoText = {};
var exportText1, exportText2

function info (choice) {
    // Hide all submenus
    dropup('submenu1');
    dropup('submenu2');

    if (document.getElementById("corpus_menu")) {
        corpus = document.getElementById("corpus_menu").value
    }
    if (document.getElementById("query_text")) {
        query = document.getElementById("query_text").value
    }
    if (document.getElementById("author_text")) {
        author = document.getElementById("author_text").value
    }
    if (choice == 'export') {
      exportDir = document.getElementById("xml-export-dir").value
        if (exportDir && exportDir != "null") {
            infoText['export'] = exportText1 +
                '<p class="info-field">Output Folder: ' + exportDir + '</p>' +
                exportText2 + '<p align="center"><input class="info-button" type="submit" name="go" value="Export Texts"></p>'
        }
        else {
            infoText['export'] = exportText1 + '<p class="info-text">You must first specify in your settings the location of the folder into which the directory with the XML files will be placed.</p>' +                 
            exportText2
        }
    }

    document.getElementById("info").innerHTML = infoText[choice];

    if (corpus && document.getElementById("corpus_menu")) {
        document.getElementById("corpus_menu").value = corpus;
    }
    if (query && document.getElementById("query_text")) {
        document.getElementById("query_text").value = query;
    }
    if (author && document.getElementById("author_text")) {
        document.getElementById("author_text").value = author;
    }

    if (document.getElementById("query_text")) {
        document.getElementById("query_text").focus();
    }
    if (document.getElementById("author_text")) {
        document.getElementById("author_text").focus();
    }
    document.getElementById("action").value = choice;
}

var searchTooltip =
    '<div class="tooltip-container">'+
    '<div class="tooltip">Note on Greek input'+
    '<span class="tooltiptext">'+
    'Use your computer\'s Unicode Greek keyboard. '+
    'There are two Greek input modes for searching: loose and strict. '+
    'In loose mode, just enter Greek lowercase letters and (optionally) '+
    'breathings. You can do this in the Greek or Latin alphabet ' +
    '(using Beta code transliteration). ' +
    'This will search for both upper and lowercase letters '+
    'and will permit accents to appear anywhere in the search term. '+
    'If your search term is entered in Greek letters ' +
    'with accents or uppercase, '+
    'it will be interpreted in strict mode and Diogenes will only match words '+
    'with your exact accentuation and capitalization. '+
    'In other words, if you specify one accent or capital letter in your search pattern, '+
    'you must specify them all. '+
    '</span></div></div>';

// Set up content for user choices on load.
function splash_setup () {
    if(lsTest === true){
        corpus = localStorage.getItem("corpus");
        query = localStorage.getItem("query");
        author = localStorage.getItem("author");
        action = sessionStorage.getItem("action");
    }
    var corpora1 = document.getElementById("corpora-list1").innerHTML;
    var corpora2 = document.getElementById("corpora-list2").innerHTML;
    var corporaAll = '<select name="corpus" id="corpus_menu" class="info-field">' +
        '<optgroup label="Databases">' + corpora1 +
        '</optgroup><optgroup label="User-defined corpora">' +
        corpora2 + '</optgroup></select>';
    var corporaCore = '<select name="corpus" id="corpus_menu" class="info-field">' +
        corpora1 +
        '</select>';

    infoText['browse'] = '<h2 class="info-h2">Read a Text</h2>' +
        '<p class="info-field">Corpus: ' + corporaCore +
        '<p class="info-field">Author:<input type="text" name="author" size="30" id="author_text" class="info-field" spellcheck="false"><input type="submit" name="go" value="Go" class="info-field"></p>' +
        '<p class="info-text">Choose the relevant corpus, and then enter the name of an author (or part of the name, or the author\'s number or nickname).  Leave the space blank to choose from a list of all authors in the corpus.</p>';

    infoText['search'] = '<h2 class="info-h2">Simple Search</h2>' +
        '<p class="info-field">Corpus: ' + corporaAll + '</p>' +
        '<p class="info-field">Pattern:<input type="text" name="query" size="40" id="query_text" class="info-field" spellcheck="false"><input type="submit" name="go" value="Go" class="info-field"></p>' +
        '<p class="info-text">Choose the relevant corpus, and then enter a pattern (word or sequence of words) to search for.  <b>NB.</b> To restrict a search to the beginning or end of a word, enter a space before or after the letters in your pattern.' + searchTooltip + '</p>';

    infoText['author'] = '<h2 class="info-h2">Search within Author(s)</h2>' +
        '<p class="info-field">Corpus: ' + corporaCore + '</p>' +
        '<p class="info-field">Author: <input type="text" name="author" size="20" id="author_text" class="info-field" spellcheck="false"></p>' +
        '<p class="info-field">Pattern:<input type="text" name="query" size="40" id="query_text" class="info-field" spellcheck="false"><input type="submit" name="go" value="Go" class="info-field"></p>' +
        '<p class="info-text">This is a simple search within the texts of selected author(s). Choose the relevant corpus, enter part of an author\'s name (all matching authors will be searched), and enter a pattern to search for.</p> <p>For finer-grained control over which authors and texts to search in and many more ways to select them, choose the <b>Filter</b> option above.' + searchTooltip + '</p>';

    infoText['multiple'] = '<h2 class="info-h2">Multiple Pattern Search</h2>' +
        '<p class="info-field">Corpus: ' + corporaAll + '</p>' +
        '<p class="info-field">Pattern:<input type="text" name="query" size="40" id="query_text" class="info-field" spellcheck="false"><input type="submit" name="go" value="Go" class="info-field"></p>' +
        '<p class="info-text">Search for multiple terms in arbitrary order within a certain scope.  Enter the corpus to search in and the first of your search terms.  You will be able to add further terms in subsequent pages.' + searchTooltip + '</p>';

    infoText['lemma'] = '<h2 class="info-h2">Morphological Search</h2>' +
        '<p class="info-field">Corpus: ' + corporaAll + '</p>' +
        '<p class="info-field">Pattern:<input type="text" name="query" size="40" id="query_text" class="info-field" spellcheck="false"><input type="submit" name="go" value="Go" class="info-field"></p>' +
        '<p class="info-text">Search for particular inflected forms of a given word.  Enter the corpus and (part of) a word in its dictionary form.</p>';

    infoText['word_list'] = '<h2 class="info-h2">TLG Word List Search</h2>' +
        '<p class="info-field">Corpus: ' + corporaAll + '</p>' +
        '<p class="info-field">Pattern:<input type="text" name="query" size="40" id="query_text" class="info-field" spellcheck="false"><input type="submit" name="go" value="Go" class="info-field"></p>' +
        '<p class="info-text">The <i>TLG</i> has a word-list that serves as an index.  For narrow searches, using the word list can be faster; for big searches, it may be much slower.  Enter a word (without diacritics) to see matches from the word-list.  Put a space in front to match only at the beginning of words.</p>';

    infoText['lookup'] = '<h2 class="info-h2">Dictionary Lookup</h2>' +
        '<p class="info-field">Word:<input type="text" name="query" size="40" id="query_text" class="info-field" spellcheck="false"><input type="submit" name="go" value="Go" class="info-field"></p>' +
        '<p class="info-text">Look up a word in the Greek lexicon of Liddel, Scott and Jones or in the Latin lexicon of Lewis and Short.  Use Greek letters to look up a Greek word and use Latin for Latin.</p>';

    infoText['parse'] = '<h2 class="info-h2">Parse an Inflected Form</h2>' +
        '<p class="info-field">Word:<input type="text" name="query" size="40" id="query_text" class="info-field" spellcheck="false"><input type="submit" name="go" value="Go" class="info-field"></p>' +
        '<p class="info-text">Parse the morphology of an inflected word in Latin or Greek (using Greek letters to enter a Greek word).</p>';

    infoText['headwords'] = '<h2 class="info-h2">Search TLG Lexica Headwords</h2>' +
        '<p class="info-field">Word:<input type="text" name="query" size="40" id="query_text" class="info-field" spellcheck="false"><input type="submit" name="go" value="Go" class="info-field"></p>' +
    '<p class="info-text">Search the headwords (and phrases) of the entries in various ancient Greek lexica from the TLG: Suda, Hesychius, etc.</p>';
  
    infoText['filters'] = '<h2 class="info-h2">Select subsets of texts</h2>' +
        '<p class="info-text">In order to perform delimited, targeted searches, you can create lists of particular authors and/or texts and save them for later reuse.  These personalized subsets of texts can be created for any database.  Furthermore, the <i>TLG</i> database categorizes texts by genre, date and so on, and these can be used as the basis for user-defined subsets.</p>' +
        '<p align="center"><input class="info-button" type="submit" name="go" value="Create and Manage Subsets"></p>';

    exportText1 = '<h2 class="info-h2">Export texts as XML</h2>' +
        '<p class="info-field">Corpus: ' + corporaAll + '</p>'+
        '<p class="info-field">Optionally, select author(s): <input type="text" name="author" size="20" id="author_text" class="info-field" spellcheck="false"></p>'
    ;
    exportText2 = '<p class="info-text">' +
        'Export texts as TEI-compliant XML for use with other applications.  Choose your author(s) or the (sub)corpus to convert. This is a slow process, so you may wish to go first to <b>Filter</b> and define a subset of the authors you want to convert.</p>';

    infoText['help'] = '<h2 class="info-h2">Help and Support</h2>' +
        '<p class="info-text">For information about using Diogenes, see the <a target="_blank" href="https://d.iogen.es/d/faqs.html">website</a>.</p>' +
        '<p class="info-text">If are a student, a schoolteacher or a member of the general public who uses Diogenes, or if you are a university teacher who uses it in your undergraduate teaching, you can help to support its continuing development by sending a quick message describing the benefits it has brought to you to:  <a href="mailto:p.j.heslin@durham.ac.uk?subject=Diogenes Impact">p.j.heslin@durham.ac.uk</a>.</p>';

  if (action) {
    info(action)
  }
}
