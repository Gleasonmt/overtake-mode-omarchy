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

  function safe(name) { return /^[A-Za-z0-9_][A-Za-z0-9_.+-]{0,127}$/.test(String(name || "")) }
  function source(name) {
    if (!safe(name) || !copies) return ""
    if (name in copies) return copies[name] ? "file://" + dir + "/" + copies[name] : ""
    if (name in checked) return Quickshell.iconPath(name, true)
    if (!(name in asked || name in asking || name in answering)) { asked[name] = true; later.restart() }
    return ""
  }
  // One scan at a time, and not more often than this: a sender can name icons faster.
  Timer { id: later; interval: 3000; onTriggered: root.rescan() }
  // A scan that failed (its lock busy for a minute, a full disk) answered nothing:
  // its names wait for another, and draw nothing meanwhile.
  Timer { id: retry; interval: 30000; onTriggered: root.rescan() }
  function rescan() {
    if (scan.running) { later.restart(); return }
    asking = asked
    asked = Object.create(null)
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
      if (root.checkedCount > 4000) { root.checked = Object.create(null); root.checkedCount = 0 }   // (bounded: a sender can name icons without end)
      for (var name in root.answering) if (!(name in next)) { root.checked[name] = true; root.checkedCount++ }
      root.answering = Object.create(null)
      root.copies = next   // (and what drew nothing looks again)
    }
  }
  Process {
    id: scan
    command: ["overtake", "icon-copies"]
    running: true
    onExited: function(code) {
      if (code === 0) {
        for (var name in root.asking) root.answering[name] = true
        root.asking = Object.create(null)
        list.reload()
      } else {
        for (var name in root.asking) root.asked[name] = true
        root.asking = Object.create(null)
        retry.restart()
      }
    }
  }
}
