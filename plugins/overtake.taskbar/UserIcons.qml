import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
// An icon by name. Qt decodes the file a name resolves to here, in the shell every
// plugin shares, and a small PNG with compressed text takes gigabytes. System icons
// are the system's; the ones in your own icon folder aren't always yours (Omarchy's
// web-app installer saves a site's icon there unmodified), so those are drawn
// from stripped copies a limited child made (`overtake icon-copies`), or not at all.
// A name that isn't known yet draws nothing until a scan has looked for it.
Scope {
  id: root
  readonly property string home: Quickshell.env("HOME")
  readonly property string dir: (Quickshell.env("XDG_CACHE_HOME") || home + "/.cache") + "/overtake/user-icons"
  readonly property string watched: "file://" + (Quickshell.env("XDG_DATA_HOME") || home + "/.local/share") + "/icons/hicolor/256x256/apps"
  property bool scanned: false   // the first scan has finished, so the folder exists
  property bool ready: false     // and its list has been read
  property var copies: Object.create(null)   // name -> its copy's file, or "" if it has none
  property var incoming: Object.create(null)  // names just saved, not yet copied
  property var checked: Object.create(null)   // names a scan looked for and didn't find in your folder
  property var asked: Object.create(null)     // for the next scan
  property var asking: Object.create(null)    // for the one running
  property var answering: Object.create(null) // for the list about to be read
  property var lastNames: null

  // A name, never a path: Qt's lookup opens a path on the main thread, and a named
  // pipe hangs the shell for good.
  function safe(name) { return /^[A-Za-z0-9_][A-Za-z0-9_.+-]{0,127}$/.test(String(name || "")) }
  function source(name) {
    if (!safe(name) || !ready) return ""
    if (name in copies) return copies[name] ? "file://" + dir + "/" + copies[name] : ""
    if (name in incoming) return ""
    if (name in checked) return Quickshell.iconPath(name, true)
    if (!(name in asked || name in asking || name in answering)) {
      asked[name] = true
      Qt.callLater(root.rescan)
    }
    return ""
  }
  function rescan() {
    if (scan.running) { scan.again = true; return }
    asking = asked
    asked = Object.create(null)
    scan.running = true
  }

  FileView {
    id: list
    path: root.dir + "/index"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      if (!root.scanned) return   // (one from before this scan may name less than the folder holds)
      var next = Object.create(null)
      String(text()).split("\n").forEach(function(line) {
        var at = line.indexOf("\t")
        if (at > 0) next[line.slice(0, at)] = line.slice(at + 1)
      })
      for (var name in root.answering) if (!(name in next)) root.checked[name] = true
      root.answering = Object.create(null)
      root.copies = next   // (and what drew nothing looks again)
      if (!root.ready) {   // (a folder made after the watcher looked would go unseen, so not before)
        saved.folder = root.watched
        saved.nameFilters = ["*.png", "*.svg", "*.svgz", "*.jpg", "*.jpeg", "*.xpm"]
      }
      root.ready = true
    }
  }
  // (a file that isn't there yet can't be watched)
  Timer { interval: 2000; repeat: true; running: root.scanned && !root.ready; onTriggered: list.reload() }
  // A download writes in place, and may try a few addresses, with no sign here that
  // it has finished: another look, once it's likely to have.
  Timer { id: settled; interval: 15000; onTriggered: root.rescan() }
  // Where the installer saves: known as soon as a file lands, before it's copied.
  FolderListModel {
    id: saved
    folder: "file://" + root.dir
    showDirs: false
    nameFilters: ["no-such-file"]
    onCountChanged: {
      var next = Object.create(null)
      for (var i = 0; i < count; i++) next[String(get(i, "fileName")).replace(/\.[^.]*$/, "")] = true
      root.incoming = next
      noticed.restart()
    }
  }
  // (a listing can come in more than one step: what it comes to is what counts)
  Timer {
    id: noticed
    interval: 300
    onTriggered: {
      var names = Object.keys(root.incoming).sort().join("\n"), changed = root.lastNames !== null && root.lastNames !== names
      for (var name in root.incoming) if (!(name in root.copies)) changed = true
      root.lastNames = names
      if (!changed) return   // (the first listing, of what the scan just copied)
      settled.restart()
      root.rescan()
    }
  }
  Process {
    id: scan
    property bool again: false
    command: ["overtake", "icon-copies"]
    running: true
    onExited: {
      for (var name in root.asking) root.answering[name] = true
      root.asking = Object.create(null)
      root.scanned = true
      list.reload()
      if (again) { again = false; root.rescan() }
    }
  }
}
