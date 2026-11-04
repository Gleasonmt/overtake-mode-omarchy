import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons

// Name tags: a small tag on the top edge of every Claude Code window, and of
// any window given a name, so sessions spread over workspaces can be told
// apart. Loaded in every mode (Omarchy, Classic, Studio).
//
//  - The tag shows the window's name, else (a Claude Code window) its own
//    title, dimmed. Click it to name the window: Enter saves, Escape cancels,
//    an empty name goes back to the title. SUPER+ALT+N (`overtake rename`)
//    does the same for the focused window.
//  - Names are the ones the title bar and taskbar use (names.json via
//    `overtake name`); a Claude Code window's name follows its session, so it
//    comes back when the session is resumed after a reboot.
//  - Omarchy tiles windows with no title bars, so the tag sits across the
//    window's top border, in the gap and the terminal's padding. In Classic
//    and Studio the focused window's title bar shows the name instead.
Item {
  id: root

  property var shell: null

  readonly property string stateDir: Quickshell.env("HOME") + "/.local/state/overtake"
  readonly property int tagHeight: 18
  readonly property int titleBarHeight: 32   // WindowControls' barHeight

  function addressOf(t) {
    var value = t ? String(t.address || "") : ""
    return value && value.indexOf("0x") !== 0 ? "0x" + value : value
  }
  function toplevelFor(address) {
    var list = Hyprland.toplevels.values || []
    for (var i = 0; i < list.length; i++) if (addressOf(list[i]) === address) return list[i]
    return null
  }

  // ---------- Mode ----------
  // Overtake Mode on: the focused window has a title bar showing its name.
  property bool modeOn: false
  Timer {
    interval: 1500
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: flagCheck.running = true
  }
  Process {
    id: flagCheck
    command: ["test", "-f", root.stateDir + "/enabled"]
    onExited: function(code) { root.modeOn = code === 0 }
  }

  // ---------- Names and Claude Code windows ----------
  property var names: ({})
  FileView {
    path: root.stateDir + "/names.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: { try { root.names = JSON.parse(text() || "{}") } catch (e) {} }
    onLoadFailed: root.names = {}
  }

  // address -> session id, from `overtake sessions` (which also hands a
  // resumed session's name back to its new window).
  property var claude: ({})
  Process {
    id: sessions
    command: ["overtake", "sessions"]
    stdout: StdioCollector {
      onStreamFinished: { try { root.claude = JSON.parse(text || "{}") } catch (e) {} }
    }
  }
  function refreshSessions() { if (!sessions.running) sessions.running = true }
  // Claude Code can start in a terminal that's already open: poll.
  Timer {
    interval: 3000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refreshSessions()
  }
  Timer {
    id: sessionsSoon
    interval: 600
    onTriggered: root.refreshSessions()
  }

  // Windows with a tag: Claude Code windows, named windows, and the one being named.
  property string editing: ""
  readonly property var tagged: {
    var list = (Hyprland.toplevels.values || []).map(addressOf)
    return list.filter(function(a) { return !!root.claude[a] || !!root.names[a] || a === root.editing })
  }

  // A Claude Code title starts with its status glyph (✳ idle, a spinner while working).
  function cleanTitle(title) {
    return String(title || "").replace(/^[^\w\s~\/.]{1,2}\s+/, "")
  }

  // ---------- Where, and whether it shows ----------
  // Hyprland reports no resizes, and window geometry only arrives through IPC.
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (/window|workspace|fullscreen|floating|monitor|special|group/.test(event.name)) {
        Hyprland.refreshToplevels()
        Hyprland.refreshMonitors()
      }
      if (/^(openwindow|closewindow)$/.test(event.name)) sessionsSoon.restart()
      // Naming gives up when another window takes focus.
      if (event.name === "activewindowv2" && root.editing && "0x" + event.data !== root.editing) root.editing = ""
    }
  }
  Timer {
    interval: 700
    running: root.tagged.length > 0
    repeat: true
    onTriggered: {
      Hyprland.refreshToplevels()
      Hyprland.refreshMonitors()
    }
  }

  function monitorOf(info) {
    if (!info) return null
    var m = (Hyprland.monitors.values || []).find(function(m) { return m.id === info.monitor })
    return m ? m.lastIpcObject : null
  }

  // The focused window, which has a title bar while Overtake Mode is on.
  readonly property var focused: Hyprland.activeToplevel || (Hyprland.toplevels.values || []).find(function(t) {
    return t.lastIpcObject && t.lastIpcObject.focusHistoryID === 0
  }) || null
  readonly property string titleBarFor: {
    if (!modeOn || !focused || !focused.workspace || focused.workspace !== Hyprland.focusedWorkspace) return ""
    var info = focused.lastIpcObject
    return info && info.fullscreen !== 2 ? addressOf(focused) : ""
  }

  // The tag's rectangle (global logical pixels): across the top border, or
  // just inside the window when there's no room above it (under the bar).
  function tagRect(info, mon, width) {
    var top = mon.y + (mon.reserved ? mon.reserved[1] : 0)
    var y = info.at[1] - Math.round(tagHeight / 2)
    return { x: info.at[0] + 10, y: y >= top ? y : info.at[1] - 2, w: width, h: tagHeight }
  }

  function overlaps(a, b) {
    return a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h
  }

  // Shown when its workspace is on screen and nothing above it covers the tag.
  // Hyprland has no stacking order over IPC: fullscreen windows cover the
  // rest, floating ones cover tiled ones, and between floating windows the
  // more recently focused one is on top (Overtake raises on focus).
  function shows(address, rect) {
    var t = toplevelFor(address)
    var info = t ? t.lastIpcObject : null
    var mon = monitorOf(info)
    if (!info || !info.at || !info.size || !mon || !info.workspace || info.workspace.id <= 0) return false
    if (info.hidden || info.fullscreen === 2) return false
    if (!mon.activeWorkspace || mon.activeWorkspace.id !== info.workspace.id) return false
    if (mon.specialWorkspace && mon.specialWorkspace.id !== 0) return false
    if (address === root.editing) return true
    if (address === root.titleBarFor) return false
    var list = Hyprland.toplevels.values || []
    for (var i = 0; i < list.length; i++) {
      var o = list[i].lastIpcObject
      if (!o || !o.at || !o.size || o.hidden || addressOf(list[i]) === address) continue
      if (!o.workspace || o.workspace.id !== info.workspace.id) continue
      var above = (o.fullscreen > 0 && !info.fullscreen)
        || (o.floating && !info.floating)
        || (o.floating && info.floating && o.focusHistoryID < info.focusHistoryID)
      if (!above) continue
      var r = { x: o.at[0], y: o.at[1], w: o.size[0], h: o.size[1] }
      // the focused window's title bar sits above it
      if (addressOf(list[i]) === root.titleBarFor) { r.y -= root.titleBarHeight; r.h += root.titleBarHeight }
      if (overlaps(r, rect)) return false
    }
    return true
  }

  function name(address, value) {
    var next = Object.assign({}, root.names)
    value = String(value || "").trim()
    if (value) next[address] = value
    else delete next[address]
    root.names = next
    Quickshell.execDetached(["overtake", "name", address, value])
  }

  // `overtake rename [address]` writes "<address> <time>" after focusing the
  // window. While Overtake Mode is on the title bar takes it; the first value
  // seen is just startup.
  property string lastRenameRequest: ""
  property bool renameRequestSeen: false
  FileView {
    path: root.stateDir + "/rename-request"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      var value = text().trim()
      if (value && value !== root.lastRenameRequest && root.renameRequestSeen && !root.modeOn)
        root.editing = value.split(" ")[0]
      if (value) root.lastRenameRequest = value
      root.renameRequestSeen = true
    }
    onLoadFailed: root.renameRequestSeen = true
  }

  // ---------- The tags ----------
  Variants {
    model: root.tagged

    PanelWindow {
      id: tag

      required property var modelData
      readonly property string address: String(modelData)
      readonly property var toplevel: root.toplevelFor(address)
      readonly property var info: toplevel ? toplevel.lastIpcObject : null
      readonly property var mon: root.monitorOf(info)
      readonly property bool editing: root.editing === address
      readonly property string given: root.names[address] || ""
      readonly property string label: given || root.cleanTitle(toplevel ? toplevel.title : "")
      readonly property real maxWidth: info && info.size ? Math.max(80, Math.min(480, info.size[0] - 20)) : 80
      readonly property real wanted: editing ? Math.max(240, labelText.implicitWidth + 40)
        : labelText.implicitWidth + 26 + pencil.implicitWidth   // room for the pencil shown on hover
      readonly property var rect: info && info.at && mon ? root.tagRect(info, mon, Math.min(maxWidth, wanted)) : null

      readonly property var onScreen: mon ? Quickshell.screens.find(function(s) { return s.name === mon.name }) || null : null

      screen: onScreen
      visible: !!rect && !!onScreen && (label.length > 0 || editing) && root.shows(address, rect)
      color: "transparent"
      exclusionMode: ExclusionMode.Ignore
      WlrLayershell.namespace: "overtake-name-tag"
      // Top: above windows, under notifications, menus and the bar's panels.
      WlrLayershell.layer: WlrLayer.Top
      WlrLayershell.keyboardFocus: editing ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

      anchors { top: true; left: true }
      implicitWidth: rect ? rect.w : 80
      implicitHeight: root.tagHeight
      margins {
        left: rect && onScreen ? Math.round(rect.x - onScreen.x) : 0
        top: rect && onScreen ? Math.round(rect.y - onScreen.y) : 0
      }

      Rectangle {
        anchors.fill: parent
        color: Commons.Color.background
        border.width: 1
        border.color: tag.given || tag.editing ? Commons.Color.accent
          : Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.25)

        // accent edge, like the start of a tab
        Rectangle {
          anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
          width: 3
          color: Commons.Color.accent
          opacity: tag.given || tag.editing ? 1 : 0.4
        }

        Text {
          id: labelText
          anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
          width: Math.min(implicitWidth, tag.maxWidth - 26 - pencil.implicitWidth)
          visible: !tag.editing
          textFormat: Text.PlainText
          text: tag.label
          elide: Text.ElideRight
          color: Commons.Color.foreground
          opacity: tag.given ? 1 : 0.6
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          font.bold: !!tag.given
        }
        Text {
          id: pencil
          anchors { left: labelText.right; leftMargin: 6; verticalCenter: parent.verticalCenter }
          visible: tagArea.containsMouse && !tag.editing
          text: ""
          color: Commons.Color.accent
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
        }

        TextInput {
          id: edit
          anchors { fill: parent; leftMargin: 10; rightMargin: 8 }
          visible: tag.editing
          verticalAlignment: Text.AlignVCenter
          color: Commons.Color.foreground
          selectionColor: Commons.Color.accent
          selectedTextColor: Commons.Color.background
          selectByMouse: true
          clip: true
          maximumLength: 80
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          onVisibleChanged: if (visible) { text = tag.given || tag.label; selectAll(); forceActiveFocus() }
          Keys.onReturnPressed: { root.name(tag.address, text); root.editing = "" }
          Keys.onEnterPressed: { root.name(tag.address, text); root.editing = "" }
          Keys.onEscapePressed: root.editing = ""
        }

        MouseArea {
          id: tagArea
          anchors.fill: parent
          enabled: !tag.editing
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.editing = tag.address
        }
      }
    }
  }
}
