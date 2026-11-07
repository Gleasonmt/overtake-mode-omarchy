import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
// An icon by name. Qt decodes the file a name resolves to here, in the shell every
// plugin shares, and a small PNG with compressed text takes gigabytes. System icons
// are the system's; the ones in your own icon folder aren't always yours (Omarchy's
// web-app installer saves a site's icon there unmodified), so those are drawn
// from stripped copies a limited child made (`overtake icon-copies`), or not at all.
Scope {
  id: root
  readonly property string home: Quickshell.env("HOME")
  readonly property string dir: (Quickshell.env("XDG_CACHE_HOME") || home + "/.cache") + "/overtake/user-icons"
  property bool scanned: false   // the first scan has finished, so the folder exists
  property bool ready: false     // and its list has been read
  property var copies: Object.create(null)   // name -> its copy's file, or "" if it has none
  property var incoming: Object.create(null)  // names just saved, not yet copied
  property int lastCount: -1

  // A name, never a path: Qt's lookup opens a path on the main thread, and a named
  // pipe hangs the shell for good.
  function safe(name) { return /^[A-Za-z0-9_][A-Za-z0-9_.+-]{0,127}$/.test(String(name || "")) }
  function source(name) {
    if (!safe(name) || !ready) return ""
    if (name in copies) return copies[name] ? "file://" + dir + "/" + copies[name] : ""
    if (name in incoming) return ""
    return Quickshell.iconPath(name, true)
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
      root.copies = next
      root.ready = true
    }
  }
  // (a file that isn't there yet can't be watched)
  Timer { interval: 2000; repeat: true; running: root.scanned && !root.ready; onTriggered: list.reload() }
  // Where the installer saves: known as soon as a file lands, before it's copied.
  // This model never notices a folder made after it looked, so it waits for the
  // scan, which makes the folder. Nothing is looked up until then.
  FolderListModel {
    id: saved
    folder: root.ready ? "file://" + (Quickshell.env("XDG_DATA_HOME") || root.home + "/.local/share") + "/icons/hicolor/256x256/apps" : ""
    showDirs: false
    nameFilters: root.ready ? ["*.png", "*.svg", "*.svgz", "*.jpg", "*.jpeg", "*.xpm"] : ["no-such-file"]
    onCountChanged: {
      var next = Object.create(null), changed = root.lastCount >= 0
      for (var i = 0; i < count; i++) {
        var name = String(get(i, "fileName")).replace(/\.[^.]*$/, "")
        next[name] = true
        if (!(name in root.copies)) changed = true
      }
      root.incoming = next
      root.lastCount = count
      if (!changed) return   // (the first listing, of what the scan just copied)
      if (scan.running) scan.again = true
      else scan.running = true
    }
  }
  Process {
    id: scan
    property bool again: false
    command: ["overtake", "icon-copies"]
    running: true
    onExited: {
      root.scanned = true
      list.reload()
      if (again) { again = false; running = true }
    }
  }
}
