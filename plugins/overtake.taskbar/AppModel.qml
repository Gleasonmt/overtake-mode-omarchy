import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

// Apps and their windows, for Studio's Dock, App Switcher and Force Quit:
// the same matching the taskbar does (desktop entries, Omarchy web apps by
// their URL), across every workspace. Dock pins live in
// ~/.config/overtake/dock-pinned.txt, one desktop entry id per line;
// "browser" and "terminal" stand for your default ones.
Item {
  id: root

  // ---------- Pins ----------
  readonly property string pinsPath: Quickshell.env("HOME") + "/.config/overtake/dock-pinned.txt"
  property var pinLines: []
  readonly property var pinned: pinLines.map(resolveId).filter(function(id, i, all) { return id && all.indexOf(id) === i })
  FileView {
    id: pinsFile
    path: root.pinsPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.pinLines = root.parsePins(text())
    onLoadFailed: root.pinLines = ["org.gnome.Nautilus", "browser", "terminal"]
  }
  function parsePins(text) {
    return String(text || "").split("\n").map(function(l) { return l.trim() })
      .filter(function(l) { return l && l.charAt(0) !== "#" })
  }

  // Default browser and terminal (as the desktop icons resolve them).
  property string browserId: ""
  property string terminalId: ""
  Process {
    running: true
    command: ["sh", "-c", "omarchy-cmd-default-browser 2>/dev/null || echo; xdg-terminal-exec --print-id 2>/dev/null"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var lines = text.split("\n").map(function(l) { return l.trim().replace(/\.desktop$/, "") })
        root.browserId = lines[0] || "chromium"
        root.terminalId = lines[1] || "Alacritty"
      }
    }
  }
  function resolveId(id) {
    if (id === "browser") return root.browserId
    if (id === "terminal") return root.terminalId
    return id
  }

  function isPinned(id) { return root.pinned.indexOf(String(id)) !== -1 }

  // Pin or unpin; keeps the file's comments, writes "browser"/"terminal"
  // entries back as they were.
  function setPinned(id, pin) {
    id = String(id || "")
    if (!id || pin === isPinned(id)) return
    var lines = root.pinLines.slice()
    if (pin) lines.push(id)
    else lines = lines.filter(function(l) { return resolveId(l) !== id })
    writePins(lines)
  }

  // Move a pinned app to position `to` among the pins.
  function movePin(id, to) {
    var lines = root.pinLines.slice()
    var from = -1
    for (var i = 0; i < lines.length; i++) if (resolveId(lines[i]) === id) from = i
    if (from === -1) { lines.splice(Math.max(0, Math.min(to, lines.length)), 0, id) }
    else {
      var line = lines.splice(from, 1)[0]
      lines.splice(Math.max(0, Math.min(to, lines.length)), 0, line)
    }
    writePins(lines)
  }

  function writePins(lines) {
    root.pinLines = lines
    pinsFile.setText("# Dock pins, one desktop entry id per line (managed by the Dock: right-click an app).\n"
      + "# \"browser\" and \"terminal\" stand for your default browser and terminal.\n" + lines.join("\n") + "\n")
  }

  // ---------- Windows ----------
  property var windowNames: ({})
  FileView {
    path: Quickshell.env("HOME") + "/.local/state/overtake/names.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: { try { root.windowNames = JSON.parse(text() || "{}") } catch (e) { root.windowNames = {} } }
    onLoadFailed: root.windowNames = {}
  }

  function addressOf(t) {
    var value = t ? String(t.address || "") : ""
    return value && value.indexOf("0x") !== 0 ? "0x" + value : value
  }
  function titleOf(t) { return t ? (root.windowNames[addressOf(t)] || t.title || "") : "" }
  function isMinimized(t) { return !!(t && t.workspace && t.workspace.name === "special:minimized") }
  function windowAppId(t) {
    if (t.wayland && t.wayland.appId) return String(t.wayland.appId)
    var ipc = t.lastIpcObject
    return ipc && ipc.class ? String(ipc.class) : ""
  }

  function entryForAppId(appId) {
    if (!appId) return null
    return webappEntry(appId) || DesktopEntries.heuristicLookup(appId) || DesktopEntries.byId(appId)
  }
  // Omarchy web apps run as chrome-<host>__<path>-Default windows, and their
  // .desktop files carry no StartupWMClass, so match on the URL they launch.
  function webappEntry(appId) {
    var match = appId.match(/^chrome-(.+)-Default$/)
    if (!match) return null
    var url = match[1].replace("__", "/").replace(/_/g, "/")
    var apps = DesktopEntries.applications.values || []
    for (var i = 0; i < apps.length; i++) {
      if (String(apps[i].execString || "").indexOf(url) !== -1) return apps[i]
    }
    return null
  }

  function iconFor(entry, appId) {
    if (appId === "org.quickshell") return Quickshell.iconPath("preferences-system", true)  // Overtake Settings
    var source = entry && entry.icon ? Quickshell.iconPath(entry.icon, true) : ""
    if (!source && appId) source = Quickshell.iconPath(appId.toLowerCase(), true)
    return source || Quickshell.iconPath("application-x-executable", true)
  }
  function nameOf(group) { return group ? (group.entry ? group.entry.name : group.appId) : "" }

  // Every app window on a normal workspace or minimized, oldest focus last.
  readonly property var windows: (Hyprland.toplevels.values || []).filter(function(t) {
    if (!t || !t.workspace || !(t.workspace.id > 0 || isMinimized(t))) return false
    var id = windowAppId(t)
    return id !== "org.omarchy.screensaver"
  })

  // Pinned apps first (in pin order), then running apps in the order they
  // were opened. Each: { key, entry, appId, pinned, windows }.
  readonly property var groups: {
    var order = [], byKey = {}
    for (var i = 0; i < root.pinned.length; i++) {
      var id = String(root.pinned[i])
      if (byKey[id]) continue
      var entry = DesktopEntries.byId(id)
      if (!entry && id !== "overtake-apps") continue   // not installed
      byKey[id] = { key: id, entry: entry, appId: id, pinned: true, windows: [] }
      order.push(id)
    }
    var list = root.windows.slice().sort(function(a, b) {
      return (a.workspace.id > 0 ? a.workspace.id : 100) - (b.workspace.id > 0 ? b.workspace.id : 100)
    })
    for (var j = 0; j < list.length; j++) {
      var appId = windowAppId(list[j])
      var e = entryForAppId(appId)
      var key = e ? String(e.id) : appId
      if (!key) continue
      if (!byKey[key]) {
        byKey[key] = { key: key, entry: e, appId: appId, pinned: false, windows: [] }
        order.push(key)
      }
      byKey[key].windows.push(list[j])
    }
    return order.map(function(k) { return byKey[k] })
  }

  readonly property var runningGroups: groups.filter(function(g) { return g.windows.length > 0 })

  // Apps by how recently one of their windows had focus (App Switcher order).
  readonly property var recentGroups: runningGroups.slice().sort(function(a, b) {
    return recency(a) - recency(b)
  })
  function recency(group) {
    var best = 100000
    group.windows.forEach(function(t) {
      var h = t.lastIpcObject && t.lastIpcObject.focusHistoryID !== undefined ? t.lastIpcObject.focusHistoryID : 99999
      if (h < best) best = h
    })
    return best
  }
  // The window to bring up for an app: its most recently focused one,
  // visible ones before minimized ones.
  function frontWindow(group) {
    var list = group.windows.slice().sort(function(a, b) {
      var ma = isMinimized(a) ? 1 : 0, mb = isMinimized(b) ? 1 : 0
      if (ma !== mb) return ma - mb
      var ha = a.lastIpcObject ? a.lastIpcObject.focusHistoryID : 99999
      var hb = b.lastIpcObject ? b.lastIpcObject.focusHistoryID : 99999
      return ha - hb
    })
    return list[0] || null
  }

  function run(args) { Quickshell.execDetached(["overtake"].concat(args)) }
  function launch(group) {
    var id = group && group.entry ? String(group.entry.id) : ""
    if (id) Quickshell.execDetached(["uwsm-app", "--", "gtk-launch", id + ".desktop"])
  }
  function show(t) {
    if (!t) return
    if (isMinimized(t)) run(["restore", addressOf(t)])
    else run(["show", addressOf(t)])   // switches to its workspace and raises it
  }
}
