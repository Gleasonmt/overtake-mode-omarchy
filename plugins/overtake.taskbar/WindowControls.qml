import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons

// Overtake Mode's title bar for the focused window, with Snap
// Layouts. Omarchy 4.0.6 has no title bars, so this floats as a layer-shell
// surface just above the window (inside its top edge when there's no room).
//
//  - Drag the bar to move the window. Dragging near the top of the screen
//    shows the snap bar; drop on a zone to snap there (via `overtake snap`).
//  - Up to 3 windows can share a zone; the bar then shows a tab per window.
//  - Double-click maximizes. Super+Z, or hovering maximize, opens the snap bar
//    for clicking.
//
// Hyprland reports no drag events, but this bar receives its own press and
// release, so drags it starts are tracked exactly.
Item {
  id: root

  property bool modeOn: false
  readonly property int barHeight: 32  // matches SNAP_TITLE_BAR in overtake

  // The focused window. Quickshell only learns it from focus changes, so right
  // after the shell (re)starts it's unknown until one: fall back to the
  // window Hyprland lists as focused most recently.
  readonly property var toplevel: Hyprland.activeToplevel || (Hyprland.toplevels.values || []).find(function(t) {
    return t.lastIpcObject && t.lastIpcObject.focusHistoryID === 0
  }) || null
  readonly property var info: toplevel ? toplevel.lastIpcObject : null
  readonly property string address: addressOf(toplevel)
  readonly property bool maximized: info ? info.fullscreen === 1 : false

  function addressOf(t) {
    var value = t ? String(t.address || "") : ""
    return value && value.indexOf("0x") !== 0 ? "0x" + value : value
  }

  function run(args) {
    Quickshell.execDetached(["overtake"].concat(args))
  }

  // ---------- Config and state files ----------
  property var skipPatterns: []
  FileView {
    path: Quickshell.env("HOME") + "/.config/overtake/no-controls.txt"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      root.skipPatterns = text().split("\n").map(function(line) { return line.trim() })
        .filter(function(line) { return line && line.charAt(0) !== "#" })
        .map(function(line) { try { return new RegExp(line) } catch (e) { return null } })
        .filter(function(re) { return re !== null })
    }
  }

  // Windows given a name of their own (title bar right-click > Rename tab):
  // address -> name. The taskbar's window list shows them too.
  property var names: ({})
  FileView {
    id: namesFile
    path: Quickshell.env("HOME") + "/.local/state/overtake/names.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try { root.names = JSON.parse(text() || "{}") } catch (e) { root.names = {} }
    }
    onLoadFailed: root.names = {}
  }
  function titleOf(t) {
    return t ? (root.names[addressOf(t)] || t.title || "") : ""
  }
  function setName(address, name) {
    var live = (Hyprland.toplevels.values || []).map(addressOf)
    var next = {}
    for (var k in root.names) if (live.indexOf(k) !== -1) next[k] = root.names[k]   // drop closed windows
    name = String(name || "").trim()
    if (name) next[address] = name
    else delete next[address]
    root.names = next
    namesFile.setText(JSON.stringify(next, null, 2) + "\n")
  }

  // ---------- Title bar menu (right-click) ----------
  property string menuFor: ""        // the window it acts on
  property point menuAt: Qt.point(0, 0)
  property string renaming: ""       // the window whose tab is being renamed
  // (given up when another window takes focus: the title bar holds the
  // keyboard while renaming)
  onToplevelChanged: if (renaming && addressOf(toplevel) !== renaming) renaming = ""

  // `overtake rename <address>` (the taskbar's Rename window) writes
  // "<address> <time>" here after bringing the window up; the first value
  // seen is just startup.
  property string lastRenameRequest: ""
  property bool renameRequestSeen: false
  FileView {
    path: Quickshell.env("HOME") + "/.local/state/overtake/rename-request"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      var value = text().trim()
      if (!value) { root.renameRequestSeen = true; return }
      if (value === root.lastRenameRequest) return
      if (root.renameRequestSeen) renameStart.address = value.split(" ")[0], renameStart.restart()
      root.lastRenameRequest = value
      root.renameRequestSeen = true
    }
    onLoadFailed: root.renameRequestSeen = true
  }
  // Wait for the window to be the focused one, so its title bar is showing.
  Timer {
    id: renameStart
    property string address: ""
    property int tries: 0
    interval: 100
    onTriggered: {
      if (root.addressOf(root.toplevel) === address) { root.menuFor = ""; root.renaming = address; tries = 0 }
      else if (++tries < 20) restart()
      else tries = 0
    }
  }
  function isBrowser(t) {
    var cls = t && t.lastIpcObject ? String(t.lastIpcObject.class || "") : ""
    return /^(chromium|chrome-|google-chrome|brave)/.test(cls)
  }
  function openMenu(t, x, y) {
    root.renaming = ""
    root.menuFor = addressOf(t)
    root.menuAt = Qt.point(x, y)
  }
  function toplevelFor(address) {
    var list = Hyprland.toplevels.values || []
    for (var i = 0; i < list.length; i++) if (addressOf(list[i]) === address) return list[i]
    return null
  }

  property var zones: ({})
  FileView {
    path: Quickshell.env("HOME") + "/.local/state/overtake/zones.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try { root.zones = JSON.parse(text() || "{}") } catch (e) { root.zones = {} }
    }
    onLoadFailed: root.zones = {}
  }

  // ---------- Which window, and where ----------
  // No bar when: the focused window isn't on the workspace being shown
  // (Hyprland keeps reporting the last window after switching to an empty
  // workspace), true fullscreen, special workspaces, the screensaver, or an app
  // that draws its own buttons. Those apps still get a tabs-only strip when
  // they share a snap zone, in the gap snapping leaves above the window.
  readonly property bool eligible: {
    if (!modeOn || !info || !info.at || !info.size || !toplevel) return false
    if (!toplevel.workspace || toplevel.workspace !== Hyprland.focusedWorkspace) return false
    if (info.fullscreen === 2) return false
    if (info.workspace && info.workspace.id <= 0) return false
    if (String(info.class || "") === "org.omarchy.screensaver") return false
    return !ownButtons || tabsOnly
  }
  readonly property bool ownButtons: !!info && root.skipPatterns.some(function(re) { return re.test(String(info.class || "")) })
  readonly property bool tabsOnly: ownButtons && stack.length > 1 && barAbove

  readonly property var monitor: info ? (Hyprland.monitors.values || []).find(function(m) { return m.id === info.monitor }) || null : null
  readonly property var mon: monitor ? monitor.lastIpcObject : null
  readonly property real monX: mon && mon.x !== undefined ? mon.x : 0
  readonly property real monY: mon && mon.y !== undefined ? mon.y : 0
  readonly property real monW: mon ? mon.width / mon.scale : 0
  readonly property real monTop: mon ? mon.y + (mon.reserved ? mon.reserved[1] : 0) : 0
  readonly property var screenForWindow: monitor ? Quickshell.screens.find(function(s) { return s.name === monitor.name }) || null : null

  readonly property real winX: info && info.at ? info.at[0] : 0
  readonly property real winY: info && info.at ? info.at[1] : 0
  readonly property real winW: info && info.size ? info.size[0] : 0
  readonly property bool barAbove: winY - barHeight >= monTop
  readonly property real barX: winX
  readonly property real barY: barAbove ? winY - barHeight : winY

  // App windows stacked in the same snap zone on this workspace (tabs). A
  // minimized one keeps its zone (to go back into it) but lives on
  // special:minimized meanwhile, so it gets no tab; the taskbar restores it.
  readonly property var zoneEntry: zones[address] || null
  readonly property var stack: {
    if (!zoneEntry) return []
    return (Hyprland.toplevels.values || []).filter(function(t) {
      var e = root.zones[root.addressOf(t)]
      return e && e.ws === root.zoneEntry.ws && e.zone === root.zoneEntry.zone
        && !!t.workspace && t.workspace.name === e.ws
    })
  }

  // ---------- Dragging ----------
  property bool pressed: false
  property bool dragging: false

  // A floating window too close to the top for the bar to fit above it gets
  // moved down (`overtake make-room`), so the bar never covers its toolbar.
  readonly property bool needsRoom: eligible && !barAbove && !dragging && !ownButtons
    && !!info && info.floating === true && info.fullscreen === 0
  onNeedsRoomChanged: if (needsRoom) roomTimer.restart()
  Timer {
    id: roomTimer
    interval: 400
    onTriggered: if (root.needsRoom) root.run(["make-room", root.address])
  }
  property real pressX: 0
  property real pressY: 0
  property real startWinX: 0
  property real startWinY: 0
  property real frozenX: 0
  property real frozenY: 0
  property real cursorX: 0
  property real cursorY: 0
  property real pendingX: 0
  property real pendingY: 0
  property string dragAddress: ""
  property string hoverZone: ""
  property bool pickerOpen: false
  property string pickerFor: ""
  onPickerOpenChanged: if (pickerOpen) pickerFor = address

  // While a window is being dragged the snap layouts pop up just above the
  // pointer (where the drag started), so a small flick up reaches them.
  readonly property bool snapBarShown: dragging || selfMoving
  property real anchorX: 0
  property real anchorY: 0
  property bool anchorSet: false

  function anchorSnapBar(x, y) {
    anchorX = Math.max(monX + 8, Math.min(x - snapW / 2, monX + monW - snapW - 8))
    anchorY = y - snapH - 28 >= monTop + 8 ? y - snapH - 28 : y + 40
    anchorSet = true
  }

  // Hyprland animates every move, so a window dragged through IPC trails
  // behind the pointer. Switch the move animation off for the drag.
  function setMoveAnimation(on) {
    Quickshell.execDetached(["hyprctl", "eval", on
      ? "hl.animation({ leaf = \"windowsMove\", enabled = true, speed = 3.79, bezier = \"easeOutQuint\" })"
      : "hl.animation({ leaf = \"windowsMove\", enabled = false })"])
  }

  function beginDrag(x, y) {
    resetSelfMove()
    pressed = true
    pressX = x
    pressY = y
    frozenX = barX
    frozenY = barY
    startWinX = winX
    startWinY = winY
    dragAddress = address
  }

  function updateDrag(x, y) {
    if (!pressed) return
    var dx = x - pressX, dy = y - pressY
    if (!dragging) {
      if (Math.abs(dx) + Math.abs(dy) < 6) return
      dragging = true
      pickerOpen = false
      setMoveAnimation(false)
      anchorSnapBar(frozenX + pressX, frozenY + pressY)
      if (maximized) Hyprland.dispatch("hl.dsp.window.fullscreen({ mode = \"maximized\", window = \"address:" + dragAddress + "\" })")
      if (info && !info.floating) Hyprland.dispatch("hl.dsp.window.float({ action = \"enable\", window = \"address:" + dragAddress + "\" })")
    }
    cursorX = frozenX + x
    cursorY = frozenY + y
    pendingX = Math.round(startWinX + dx)
    pendingY = Math.round(startWinY + dy)
    if (!moveTimer.running) moveTimer.start()
    hoverZone = snapBarShown ? zoneAt(cursorX, cursorY) : ""
  }

  function endDrag() {
    if (dragging) {
      moveTimer.stop()
      Hyprland.dispatch("hl.dsp.window.move({ x = " + pendingX + ", y = " + pendingY + ", relative = false, window = \"address:" + dragAddress + "\" })")
      setMoveAnimation(true)
      if (hoverZone) run(["snap", hoverZone, dragAddress])
      else if (root.zones[dragAddress]) run(["unsnap", dragAddress])
    }
    pressed = false
    dragging = false
    anchorSet = false
    hoverZone = ""
    Hyprland.refreshToplevels()
  }

  // Coalesce pointer motion into at most one move per frame.
  Timer {
    id: moveTimer
    interval: 16
    onTriggered: Hyprland.dispatch("hl.dsp.window.move({ x = " + root.pendingX + ", y = " + root.pendingY + ", relative = false, window = \"address:" + root.dragAddress + "\" })")
  }

  // ---------- Snap bar geometry (shared by drawing and hit-testing) ----------
  // Three layout cards: halves, quarters, full screen.
  readonly property int cardW: 156
  readonly property int cardH: 96
  readonly property int cardGap: 14
  readonly property int snapPad: 14
  readonly property int snapW: cardW * 3 + cardGap * 2 + snapPad * 2
  readonly property int snapH: cardH + snapPad * 2
  readonly property real snapX: anchorSet ? anchorX : monX + (monW - snapW) / 2
  readonly property real snapY: anchorSet ? anchorY : monTop + 12

  // Where a zone puts the window (mirrors snap_window in overtake), for
  // the preview outline.
  readonly property int snapGap: 12
  function zoneRect(zone) {
    if (!mon || !zone) return null
    var r = mon.reserved || [0, 0, 0, 0]
    var ux = monX + r[0] + snapGap, uy = monY + r[1] + snapGap
    var uw = monW - r[0] - r[2] - 2 * snapGap, uh = mon.height / mon.scale - r[1] - r[3] - 2 * snapGap
    var hw = Math.floor((uw - snapGap) / 2), hh = Math.floor((uh - snapGap) / 2)
    var right = ux + hw + snapGap, lower = uy + hh + snapGap
    switch (zone) {
      case "left": return [ux, uy, hw, uh]
      case "right": return [right, uy, hw, uh]
      case "top-left": return [ux, uy, hw, hh]
      case "top-right": return [right, uy, hw, hh]
      case "bottom-left": return [ux, lower, hw, hh]
      case "bottom-right": return [right, lower, hw, hh]
      case "full": return [ux, uy, uw, uh]
    }
    return null
  }
  readonly property var previewRect: snapBarShown ? zoneRect(hoverZone) : null

  function zoneAt(x, y) {
    var rx = x - snapX - snapPad, ry = y - snapY - snapPad
    if (ry < 0 || ry > cardH || rx < 0) return ""
    var card = Math.floor(rx / (cardW + cardGap))
    var u = (rx - card * (cardW + cardGap)) / cardW, v = ry / cardH
    if (card > 2 || u > 1) return ""
    if (card === 0) return u < 0.5 ? "left" : "right"
    if (card === 1) return (v < 0.5 ? "top-" : "bottom-") + (u < 0.5 ? "left" : "right")
    return "full"
  }

  // Super+Z runs `overtake snap-layouts`, which writes a new timestamp to
  // this file (shell IPC isn't available to third-party plugins). A rewrite
  // arrives as two changes (truncate, then write), so only a new non-empty
  // value counts; the first value seen is just startup.
  property string lastSnapRequest: ""
  property bool snapRequestSeen: false
  FileView {
    path: Quickshell.env("HOME") + "/.local/state/overtake/snap-request"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      var value = text().trim()
      if (!value || value === root.lastSnapRequest) return
      if (root.snapRequestSeen) root.pickerOpen = !root.pickerOpen
      root.lastSnapRequest = value
      root.snapRequestSeen = true
    }
    onLoadFailed: root.snapRequestSeen = true
  }

  Timer {
    // A picker opened from Super+Z or the maximize button closes on its own.
    running: root.pickerOpen
    interval: 6000
    onTriggered: root.pickerOpen = false
  }

  // Window geometry only arrives through Hyprland IPC, so refresh it on window
  // events and on a light poll (Hyprland sends no event for resizes).
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (/window|workspace|fullscreen|floating|monitor/.test(event.name)) {
        Hyprland.refreshToplevels()
        Hyprland.refreshMonitors()
      }
      // Close the picker only when focus moves to a different window.
      if (event.name === "activewindowv2" && "0x" + event.data !== root.pickerFor) root.pickerOpen = false
      // A screen came or went (lid, dock): windows go back to their zones and
      // relative places once the monitor layout has settled.
      if (root.modeOn && /^monitor(added|removed)/.test(event.name)) rescueTimer.restart()
      // Every window floats in Overtake Mode. One that ends up tiled (a tab torn
      // off into a new window, the float toggle key) sits under all the
      // floating ones, where clicking can't raise it, so float it again.
      if (root.modeOn && event.name === "changefloatingmode" && String(event.data).split(",")[1] === "0") floatTimer.restart()
      // An app's own minimize button: Hyprland only announces the request
      // ("minimized>>ADDRESS,1"), so carry it out.
      // Minimized windows live on special:minimized; if Hyprland shows it (focus
      // landing on one of them), hide it again.
      if (root.modeOn && event.name === "activespecial" && String(event.data).split(",")[0] === "special:minimized")
        root.run(["hide-minimized"])
      if (root.modeOn && event.name === "minimized") {
        var parts = String(event.data).split(",")
        if (parts[1] === "1") root.run(["minimize", "0x" + parts[0]])
      }
    }
  }

  Timer {
    id: floatTimer
    interval: 300
    onTriggered: root.run(["float-all"])
  }

  // After a screen change: put windows back in their zones / relative places,
  // then once more when the new screen's bar has claimed its space.
  Timer {
    id: rescueTimer
    interval: 2500
    onTriggered: {
      root.run(["relayout"])
      relayoutAgainTimer.restart()
    }
  }

  Timer {
    id: relayoutAgainTimer
    interval: 4000
    onTriggered: root.run(["relayout"])
  }

  // Keep a record of where every window sits (paused around screen changes,
  // so the record is from before the change).
  Timer {
    interval: 5000
    repeat: true
    running: root.modeOn && !root.dragging && !rescueTimer.running && !relayoutAgainTimer.running
    onTriggered: root.run(["remember"])
  }

  Timer {
    interval: 400
    running: root.modeOn && !root.dragging && !root.watchingSelfMove
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      Hyprland.refreshToplevels()
      Hyprland.refreshMonitors()
    }
  }

  // ---------- Drags that start in an app's own title area ----------
  // Apps can move themselves through Hyprland (a browser's tab strip, a GTK
  // header bar, an app with its own buttons), which reports nothing. Watch the
  // focused window while it's floating: a drag is the window
  // moving (same size) for two or more polls in a row, which tells it apart
  // from a one-off snap or maximize jump. Near the top of the screen that shows
  // the snap bar; once the window has stopped for half a second over a zone, it
  // snaps there. Dragging a snapped window out restores its size.
  // Not during a drag of our own title bar: both would act on the drop, and
  // the watcher's "dragged out of its zone" unsnap undid the bar's snap.
  readonly property bool watchingSelfMove: modeOn && !pressed && !!(info && info.floating && info.fullscreen === 0) && Hyprland.focusedWorkspace === (toplevel ? toplevel.workspace : null)
  property string watchAddress: ""
  property var lastGeometry: null
  property int movedTicks: 0
  property int stillTicks: 0
  property bool selfMoving: false

  // `overtake` stamps this file whenever it arranges windows (snap, relayout,
  // float-all, rescue); movement for the next two seconds is ours, not a drag.
  property real arrangingUntil: 0
  FileView {
    path: Quickshell.env("HOME") + "/.local/state/overtake/arranging"
    watchChanges: true
    printErrors: false
    onFileChanged: { root.arrangingUntil = Date.now() + 2000; reload() }
  }

  Timer {
    interval: 80
    running: root.watchingSelfMove
    repeat: true
    onTriggered: {
      root.selfMoveTick()
      Hyprland.refreshToplevels()
    }
    onRunningChanged: if (!running) root.resetSelfMove()
  }

  function resetSelfMove() {
    lastGeometry = null
    movedTicks = 0
    stillTicks = 0
    if (selfMoving) hoverZone = ""
    selfMoving = false
    anchorSet = false
  }

  function selfMoveTick() {
    if (watchAddress !== address) {
      resetSelfMove()
      watchAddress = address
    }
    var g = [winX, winY, info.size[0], info.size[1]]
    var last = lastGeometry
    lastGeometry = g
    if (!last) return
    if (Date.now() < arrangingUntil) { movedTicks = 0; return }  // Overtake moving it, not the user
    var moved = g[0] !== last[0] || g[1] !== last[1]
    var sameSize = g[2] === last[2] && g[3] === last[3]
    if (moved && sameSize) {
      stillTicks = 0
      movedTicks += 1
      if (movedTicks >= 2) {
        selfMoving = true
        cursorProc.running = true
      }
      return
    }
    movedTicks = 0
    if (!selfMoving) return
    stillTicks += 1
    if (stillTicks < 6) return
    if (hoverZone) run(["snap", hoverZone, address])
    else if (root.zones[address]) run(["unsnap", address])
    selfMoving = false
    anchorSet = false
    hoverZone = ""
  }

  Process {
    id: cursorProc
    command: ["hyprctl", "cursorpos", "-j"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var pos = JSON.parse(text)
          root.cursorX = pos.x
          root.cursorY = pos.y
          if (root.selfMoving && !root.anchorSet) root.anchorSnapBar(pos.x, pos.y)
          root.hoverZone = root.snapBarShown ? root.zoneAt(pos.x, pos.y) : ""
        } catch (e) {}
      }
    }
  }

  // ---------- Title bar ----------
  PanelWindow {
    id: bar

    // Stay mapped while dragging, even if the focus check flickers, so the
    // drag keeps receiving pointer events until release.
    visible: (root.eligible || root.pressed) && root.screenForWindow !== null
    screen: root.screenForWindow
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "overtake-titlebar"
    // Top, not Overlay: above windows but under notifications and popups.
    WlrLayershell.layer: WlrLayer.Top
    // Keyboard only while a tab is being renamed.
    WlrLayershell.keyboardFocus: root.renaming !== "" ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    anchors { top: true; left: true }
    implicitWidth: Math.max(200, root.winW)
    implicitHeight: root.barHeight
    margins {
      left: Math.round((root.pressed ? root.frozenX : root.barX) - (bar.screen ? bar.screen.x : 0))
      top: Math.round((root.pressed ? root.frozenY : root.barY) - (bar.screen ? bar.screen.y : 0))
    }

    // Hidden while dragging (the window itself follows the pointer).
    Item {
      anchors.fill: parent
      opacity: root.dragging ? 0 : 1

      Rectangle {
        anchors.fill: parent
        color: Commons.Color.background
        opacity: 0.94
        radius: root.barAbove ? Style.space(6) : 0
        Rectangle {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          height: 1
          color: Commons.Color.accent
          opacity: 0.6
        }
      }

      // Drag area under everything else; tabs and buttons sit on top of it.
      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onPressed: function(mouse) {
          if (mouse.button === Qt.RightButton) {
            var p = mapToItem(null, mouse.x, mouse.y)
            root.openMenu(root.toplevel, bar.margins.left + p.x, bar.margins.top + p.y)
            return
          }
          root.beginDrag(mouse.x, mouse.y)
        }
        onPositionChanged: function(mouse) { root.updateDrag(mouse.x, mouse.y) }
        onReleased: root.endDrag()
        onCanceled: root.endDrag()
        onDoubleClicked: root.run(["maximize", root.address])
      }

      Row {
        id: tabs
        anchors.left: parent.left
        anchors.leftMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(4)
        readonly property var items: root.stack.length > 1 ? root.stack : (root.toplevel ? [root.toplevel] : [])
        readonly property real tabWidth: Math.min(Style.space(240), (bar.width - (buttons.visible ? buttons.width : 0) - Style.space(24)) / Math.max(1, items.length))

        Repeater {
          model: tabs.items

          Item {
            id: tab
            required property var modelData
            readonly property bool active: modelData === root.toplevel
            readonly property bool isTab: root.stack.length > 1
            width: tabs.tabWidth
            height: root.barHeight - Style.space(8)

            Rectangle {
              anchors.fill: parent
              visible: tab.isTab
              radius: Style.space(4)
              color: tab.active ? Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.28)
                                : Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, tabArea.containsMouse ? 0.12 : 0.05)
            }

            readonly property bool editing: root.renaming !== "" && root.renaming === root.addressOf(tab.modelData)

            TextInput {
              id: nameEdit
              anchors.fill: parent
              anchors.leftMargin: Style.space(8)
              anchors.rightMargin: Style.space(8)
              visible: tab.editing
              verticalAlignment: Text.AlignVCenter
              color: Commons.Color.foreground
              selectionColor: Commons.Color.accent
              selectByMouse: true
              clip: true
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
              onVisibleChanged: if (visible) { text = root.titleOf(tab.modelData); selectAll(); forceActiveFocus() }
              Keys.onReturnPressed: { root.setName(root.renaming, text); root.renaming = "" }
              Keys.onEnterPressed: { root.setName(root.renaming, text); root.renaming = "" }
              Keys.onEscapePressed: root.renaming = ""
              onActiveFocusChanged: if (!activeFocus && tab.editing) root.renaming = ""
            }

            Text {
              anchors.fill: parent
              anchors.leftMargin: Style.space(8)
              anchors.rightMargin: Style.space(8)
              visible: !tab.editing
              verticalAlignment: Text.AlignVCenter
              textFormat: Text.PlainText
              text: root.titleOf(tab.modelData)
              elide: Text.ElideRight
              color: Commons.Color.foreground
              opacity: tab.active ? 1 : 0.7
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
            }

            MouseArea {
              id: tabArea
              anchors.fill: parent
              enabled: tab.isTab && !tab.active && !tab.editing
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              acceptedButtons: Qt.LeftButton | Qt.RightButton
              onClicked: function(mouse) {
                if (mouse.button === Qt.RightButton) {
                  var p = mapToItem(null, mouse.x, mouse.y)
                  root.openMenu(tab.modelData, bar.margins.left + p.x, bar.margins.top + p.y)
                } else root.run(["show", root.addressOf(tab.modelData)])  // focus and raise
              }
            }
          }
        }
      }

      Row {
        id: buttons
        visible: !root.tabsOnly  // the app has its own buttons
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter

        ControlButton { glyph: ""; onClicked: root.run(["minimize", root.address]) }
        ControlButton {
          id: maxButton
          glyph: root.maximized ? "" : ""
          onClicked: root.run(["maximize", root.address])
          onHoverHeld: root.pickerOpen = true
        }
        ControlButton { glyph: ""; danger: true; onClicked: root.run(["close", root.address]) }
      }
    }
  }

  // ---------- Title bar menu ----------
  // Right-click on the title bar or a tab: Copy URL (browser windows), Rename
  // tab and, once renamed, Reset name. A click anywhere else closes it.
  PanelWindow {
    id: titleMenu
    readonly property var target: root.menuFor ? root.toplevelFor(root.menuFor) : null
    readonly property var rows: {
      var t = target, list = []
      if (!t) return list
      var a = root.menuFor
      if (root.isBrowser(t)) list.push({ glyph: "\uf0c5", label: "Copy URL", run: function() { root.run(["copy-url", a]) } })
      list.push({ glyph: "\uf044", label: "Rename tab…", run: function() { root.run(["show", a]); root.renaming = a } })
      if (root.names[a]) list.push({ glyph: "\uf0e2", label: "Reset name", run: function() { root.setName(a, "") } })
      return list
    }
    visible: root.menuFor !== "" && target !== null && bar.screen !== null
    screen: bar.screen
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "overtake-titlebar-menu"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    anchors { top: true; bottom: true; left: true; right: true }

    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      onPressed: root.menuFor = ""
    }

    Rectangle {
      id: menuBox
      readonly property real sx: titleMenu.screen ? titleMenu.screen.x : 0
      readonly property real sy: titleMenu.screen ? titleMenu.screen.y : 0
      x: Math.min(root.menuAt.x - sx, titleMenu.width - width - Style.space(8))
      y: Math.min(root.menuAt.y - sy + Style.space(4), titleMenu.height - height - Style.space(8))
      width: Style.space(200)
      height: menuColumn.implicitHeight + Style.space(12)
      radius: Style.space(8)
      color: Commons.Color.background
      border.width: 1
      border.color: Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.15)
      focus: titleMenu.visible
      Keys.onEscapePressed: root.menuFor = ""

      Column {
        id: menuColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.margins: Style.space(6)

        Repeater {
          model: titleMenu.rows
          Rectangle {
            required property var modelData
            width: menuColumn.width
            height: Style.space(30)
            radius: Style.space(4)
            color: Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, rowArea.containsMouse ? 0.1 : 0)

            Text {
              id: rowGlyph
              anchors.left: parent.left
              anchors.leftMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(18)
              textFormat: Text.PlainText
              text: modelData.glyph
              color: Commons.Color.foreground
              opacity: 0.8
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
            }
            Text {
              anchors.left: rowGlyph.right
              anchors.leftMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: modelData.label
              color: Commons.Color.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
            }
            MouseArea {
              id: rowArea
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: { var run = modelData.run; root.menuFor = ""; run() }
            }
          }
        }
      }
    }
  }

  // ---------- Snap bar ----------
  PanelWindow {
    id: snapBar

    visible: root.modeOn && (root.snapBarShown || root.pickerOpen) && root.screenForWindow !== null
    screen: root.screenForWindow
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "overtake-snap"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    anchors { top: true; left: true }
    implicitWidth: root.snapW
    implicitHeight: root.snapH
    margins {
      left: Math.round(root.snapX - (snapBar.screen ? snapBar.screen.x : 0))
      top: Math.round(root.snapY - (snapBar.screen ? snapBar.screen.y : 0))
    }

    Rectangle {
      anchors.fill: parent
      radius: Style.space(10)
      color: Commons.Color.background
      opacity: 0.95
      border.width: 1
      border.color: Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.15)
    }

    Row {
      x: root.snapPad
      y: root.snapPad
      spacing: root.cardGap

      // Halves
      SnapCard {
        SnapZone { zone: "left"; x: 0; y: 0; width: parent.width / 2 - 2; height: parent.height }
        SnapZone { zone: "right"; x: parent.width / 2 + 2; y: 0; width: parent.width / 2 - 2; height: parent.height }
      }
      // Quarters
      SnapCard {
        SnapZone { zone: "top-left"; x: 0; y: 0; width: parent.width / 2 - 2; height: parent.height / 2 - 2 }
        SnapZone { zone: "top-right"; x: parent.width / 2 + 2; y: 0; width: parent.width / 2 - 2; height: parent.height / 2 - 2 }
        SnapZone { zone: "bottom-left"; x: 0; y: parent.height / 2 + 2; width: parent.width / 2 - 2; height: parent.height / 2 - 2 }
        SnapZone { zone: "bottom-right"; x: parent.width / 2 + 2; y: parent.height / 2 + 2; width: parent.width / 2 - 2; height: parent.height / 2 - 2 }
      }
      // Full screen
      SnapCard {
        SnapZone { zone: "full"; x: 0; y: 0; width: parent.width; height: parent.height }
      }
    }
  }

  // Outline of where the window will land, under the snap bar.
  PanelWindow {
    visible: root.modeOn && root.previewRect !== null && root.screenForWindow !== null
    screen: root.screenForWindow
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "overtake-snap-preview"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    mask: Region {}

    anchors { top: true; left: true }
    implicitWidth: root.previewRect ? Math.round(root.previewRect[2]) : 1
    implicitHeight: root.previewRect ? Math.round(root.previewRect[3]) : 1
    margins {
      left: (root.previewRect ? root.previewRect[0] : 0) - (screen ? screen.x : 0)
      top: (root.previewRect ? root.previewRect[1] : 0) - (screen ? screen.y : 0)
    }

    Rectangle {
      anchors.fill: parent
      radius: Style.space(8)
      color: Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.18)
      border.width: 2
      border.color: Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.7)
    }
  }

  component SnapCard: Item {
    width: root.cardW
    height: root.cardH
  }

  // One snap target. While dragging, the title bar holds the pointer, so the
  // highlight comes from hit-testing (root.hoverZone); in picker mode it's a
  // normal click target.
  component SnapZone: Rectangle {
    id: zoneRect
    property string zone: ""
    readonly property bool lit: root.hoverZone === zone || zoneArea.containsMouse
    radius: Style.space(4)
    color: lit ? Commons.Color.accent : Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.14)
    border.width: 1
    border.color: Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, lit ? 0.6 : 0.2)

    Behavior on color { ColorAnimation { duration: 90 } }

    MouseArea {
      id: zoneArea
      anchors.fill: parent
      enabled: root.pickerOpen && !root.dragging
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: {
        root.run(["snap", zoneRect.zone, root.address])
        root.pickerOpen = false
      }
    }
  }

  component ControlButton: Item {
    id: button

    property string glyph: ""
    property bool danger: false
    signal clicked()
    signal hoverHeld()

    width: root.barHeight + Style.space(12)
    height: root.barHeight

    Rectangle {
      anchors.fill: parent
      color: button.danger ? "#e81123" : Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.14)
      opacity: area.containsMouse ? 1 : 0
    }

    Text {
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: button.glyph
      color: button.danger && area.containsMouse ? "#ffffff" : Commons.Color.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }

    MouseArea {
      id: area
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: button.clicked()
    }

    // Hovering maximize for a moment opens the snap layouts.
    Timer {
      running: area.containsMouse
      interval: 700
      onTriggered: button.hoverHeld()
    }
  }
}
