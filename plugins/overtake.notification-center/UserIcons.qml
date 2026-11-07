import QtQuick
import Quickshell
import Quickshell.Io
// An icon by name. Qt decodes the file a name resolves to in the shell every plugin
// shares, and the icons in your own folders aren't always yours: Omarchy's web-app
// installer saves a site's icon there unmodified. So a name from your folders is
// drawn only from a stripped copy a limited child made (`overtake icon-copies`), or
// not at all, and a name goes to Qt's lookup only once a scan has looked for it in
// your folders and found nothing. Until then it draws nothing. A path is never looked
// up: Qt opens it on the main thread, and a named pipe would hang the shell for good.
Scope {
  id: root
  readonly property string dir: (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache") + "/overtake/user-icons"
  property var copies: null                   // name -> its copy's file, or "" for none; null until a list has been read
  property var checked: Object.create(null)   // names a finished scan looked for and didn't find in your folders
  property int checkedCount: 0
  property var asked: Object.create(null)     // names for the next scan
  property var asking: Object.create(null)    // names the running scan will answer
  property var answering: Object.create(null) // names the list about to be read answers
  property double lastScan: 0
  property var lastNames: null                // the names the last list held, to see one change
  property bool pending: false                // a scan was wanted while one ran

  function safe(name) { return /^[A-Za-z0-9_][A-Za-z0-9_.+-]{0,127}$/.test(String(name || "")) }
  function source(name) {
    if (!safe(name) || !copies) return ""
    if (name in copies) return copies[name] ? "file://" + dir + "/" + copies[name] : ""
    // (Qt's icon loader can fall back from name-x to name; not through this lookup on
    // Qt 6.12, measured, but a name whose prefix is in your folders draws nothing anyway)
    for (var i = name.lastIndexOf("-"); i > 0; i = name.lastIndexOf("-", i - 1)) if (name.slice(0, i) in copies) return ""
    if (name in checked) return Quickshell.iconPath(name, true)
    if (!(name in asked || name in asking || name in answering)) { asked[name] = true; root.soon() }
    return ""
  }
  // One scan at a time, and not two within 3 s: a sender can name icons faster than that.
  function soon() {
    if (scan.running) { pending = true; return }
    var wait = 3000 - (Date.now() - lastScan)
    if (wait > 0) { later.interval = wait; later.restart() } else Qt.callLater(root.rescan)
  }
  Timer { id: later; onTriggered: root.rescan() }
  // A scan that failed (its lock busy for a minute, a full disk) answered nothing:
  // its names wait for another, and draw nothing meanwhile.
  Timer { id: retry; interval: 30000; onTriggered: root.soon() }
  function rescan() {
    if (scan.running) { pending = true; return }
    pending = false
    asking = asked
    asked = Object.create(null)
    lastScan = Date.now()
    scan.running = true
  }

  // The list is read as it is, from this start or an earlier one: a name in it is
  // drawn from its copy or not at all, and a name not in it waits for a scan.
  FileView {
    id: list
    path: root.dir + "/index"
    printErrors: false
    onLoaded: {
      var next = Object.create(null)
      String(text()).split("\n").forEach(function(line) {
        var at = line.indexOf("\t")
        if (at > 0) next[line.slice(0, at)] = line.slice(at + 1)
      })
      // (your folders changed since the last list: what a scan didn't find then is asked again;
      // bounded too, as a sender can name icons without end)
      var names = Object.keys(next).sort().join("\n")
      if ((root.lastNames !== null && root.lastNames !== names) || root.checkedCount > 4000) { root.checked = Object.create(null); root.checkedCount = 0 }
      root.lastNames = names
      for (var name in root.answering) if (!(name in next)) { root.checked[name] = true; root.checkedCount++ }
      root.answering = Object.create(null)
      root.copies = next   // (and what drew nothing looks again)
    }
  }
  Process {
    id: scan
    command: ["overtake", "icon-copies"]
    running: true   // (the start's scan: copies for what changed since the last one)
    onExited: function(code) {
      if (code === 0) {
        for (var name in root.asking) root.answering[name] = true
        root.asking = Object.create(null)
        list.reload()
        if (root.pending) root.soon()
      } else {
        for (var name in root.asking) root.asked[name] = true
        root.asking = Object.create(null)
        retry.restart()
      }
    }
  }
}
