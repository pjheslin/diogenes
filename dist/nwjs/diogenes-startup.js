// Kill any stale server process, then start the new server, then wait
// for server to have started, then open a new window and load the
// splash page from the cgi script.  This window stays open and
// hidden, because node-webkit gets upset if it disappears.

var gui = require('nw.gui');
var fs = require('fs');
var path = require('path');
var mainWin = gui.Window.get();
var console = require('console');

// Config for new windows
var winConfig = {
    "title": "Diogenes",
    "frame": true,
    "icon": "diogenes.ico",
    "id": "Diogenes"
};

//////////////////////// Set up environment and launch server

var osName = process.platform.toLowerCase();

// For Mac and Unix, we assume perl is in the path
var perlName = 'perl';
if (osName == 'win32') { 
    // This is a version that runs without opening up a console
    // window.  For debugging, change to wperl perl.exe.
    perlName = path.join('strawberry', 'perl', 'bin', 'wperl.exe');
}

var settingsPath = gui.App.dataPath;
// window.alert(settingsPath);
process.env.Diogenes_Config_Dir = settingsPath;
console.log("Settings: " + settingsPath);
var lockFile = path.join(settingsPath, ".diogenes.run");

function readLockFile () {
    // Test for existence before calling this function
    var contents = fs.readFileSync(lockFile, {encoding: 'ascii'});
    var rePid  = /^pid (.*)$/m;
    var rePort = /^port (.*)$/m;
    var ar = rePid.exec(contents);
    var pid = ar[1];
    var ar = rePort.exec(contents);
    var port = ar[1];
    return [port, pid];
}

// First we delete any existing lock file and kill the associated process.  No need to wait, as the new server will choose a different port if the current one is still in use.
if (fs.existsSync(lockFile)) {
    var ar = readLockFile();
    var pid = ar[1];
    console.log("Lockfile exists. Killing pid: " + pid);
    try {
        process.kill(pid);
    } catch (e) {
        console.log("Failed to kill old server process (perhaps it no longer exists): " + e);
    }
    fs.unlinkSync(lockFile);
}

//////////////// Wait for server to start and then load splash page

// To avoid race condition, we set up fs.watch before trying to start server.  (NB: this callback may be triggered by the act of unlinking the lockfile above.) 

var startupDone = false;
var localURL, dio_port;

fs.watch(settingsPath, function (event, filename) {
    // NB. filename is not passed reliably
    if (!startupDone) {
        console.log("fs.watch: " + filename + ": " + event);
        if (fs.existsSync(lockFile) &&
            (event == 'change' || event == 'rename')) {
            var ar = readLockFile();
            dio_port = ar[0];
            if (!dio_port) {
                window.alert("ERROR: port unknown!");
                gui.App.quit();
            }
            localURL = 'http://127.0.0.1:' + dio_port;
            // Ignore further changes to the settings dir.
            startupDone = true;
            // Hide the mainWin, then open our real browser window.
            initMenu(mainWin);
            mainWin.hide();
            gui.Window.open(localURL, winConfig, function(newWin) {
                if (osName != "darwin") {
                    initMenu(newWin);
                }
            });
        }
        else {
            // Probably we caught our own act of unlinking
            console.log ("Lockfile not present.");
        }
    }
});

var curDir = process.cwd();
var serverPath = path.join(curDir, '../../diogenes-browser/perl/', 'diogenes-server.pl');
var spawn = require('child_process').spawn;
var server = spawn(perlName, [serverPath]);

// Capture server output
server.stdout.on('data', function (data) {
  console.log('server stdout: ' + data);
});
server.stderr.on('data', function (data) {
  console.log('server stderr: ' + data);
});
server.on('close', function (code) {
  console.log('Diogenes server exited with code ' + code);
});

// Just in case of unexpected exit, try to clean up server
process.on('exit', function () {
    server.kill();
    fs.unlinkSync(lockFile);
});

function dbPopup() {
    var popupConfig = {
        "focus" : true,
        "show" : true };
    gui.Window.open('dbPopup.html', popupConfig);
}

function initMenu(mywin){
    var menu = new gui.Menu({type:"menubar"});
    var submenu;
    modkey = osName == "darwin" ? "cmd" : "ctrl";

    if (osName == "darwin") {
        menu.createMacBuiltin("Diogenes", false, false);

	for(i in menu.items) {
		if(menu.items[i].label == "Diogenes") {
                    menu.items[i].submenu.insert(new gui.MenuItem({ label: "New Search", key: "n", modifiers: modkey, click: function() {mywin.window.location.href = "http://127.0.0.1:" + dio_port} }), 0);
		}
	}
    } else {
        submenu = new gui.Menu();
        submenu.append(new gui.MenuItem({ label: "New Search", key: "n", modifiers: modkey, click: function() {mywin.window.location.href = "http://127.0.0.1:" + dio_port} }));
        submenu.append(new gui.MenuItem({ label: "Quit", key: "q", modifiers: modkey, click: function() {mywin.close()} }));
        menu.append(new gui.MenuItem({ label: "File", submenu: submenu }));

        // We already get an Edit menu by default on Mac
        submenu = new gui.Menu();
        // We don't set keys for these, as they intefere with the default clipboard functions, which are more robust
        submenu.append(new gui.MenuItem({ label: "Cut", click: function() {mywin.window.document.execCommand("cut")} }));
        submenu.append(new gui.MenuItem({ label: "Copy", click: function() {mywin.window.document.execCommand("copy")} }));
        // BUG: paste isn't working at the moment
        submenu.append(new gui.MenuItem({ label: "Paste", click: function() {mywin.window.document.execCommand("paste")} }));
        menu.append(new gui.MenuItem({ label: 'Edit', submenu: submenu }));
    }
    
    submenu = new gui.Menu();
    submenu.append(new gui.MenuItem({ label: "Back", key: "left", modifiers: modkey, click: function() {mywin.window.history.back()} }));
    submenu.append(new gui.MenuItem({ label: "Forward", key: "right", modifiers: modkey, click: function() {mywin.window.history.forward()} }));
    menu.append(new gui.MenuItem({ label: "Go", submenu: submenu }));

    submenu = new gui.Menu();
    submenu.append(new gui.MenuItem
                   ({ label: "Databases",
                      click: function (){
                          dbPopup();
                      }}));
    submenu.append(new gui.MenuItem
                   ({ label: "All Settings",
                      click: function (){
                          var settingsURL = localURL + "/Settings.cgi"; 
                          gui.Window.open(settingsURL);
                      }}));
    menu.append(new gui.MenuItem({ label: 'Settings', submenu: submenu }));
        
    submenu = new gui.Menu();
    submenu.append(new gui.MenuItem({ label: "Website", click: function() {nw.Shell.openExternal("https://community.dur.ac.uk/p.j.heslin/Software/Diogenes/")} }));
    menu.append(new gui.MenuItem({ label: 'Help', submenu: submenu }));

    mywin.menu = menu;
}

