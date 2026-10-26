import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Taskbar: a Start button, pinned apps, and every open (or minimized) app,
// grouped by app. Apps with a window on the workspace this bar's monitor is
// showing are lit; ones open only on other workspaces get a faint mark, and
// clicking them jumps there. Left-click launches an app that isn't running and
// toggles focus/minimize for a single window; an app with several windows (on
// any workspace) opens a picker to choose one.
// Middle-click opens a new window; right-click opens a window menu.
Panel {
  id: root
  moduleName: "overtake.taskbar"

  readonly property bool vertical: bar ? bar.vertical : false
  readonly property int barSize: bar ? bar.barSize : Style.bar.sizeHorizontal

  readonly property var defaultPinned: ["chromium", "org.gnome.Nautilus", "foot"]
  // The pins, as saved in shell.json. Read from the file: the settings the
  // shell hands this panel can be stale after a restart, and a pin change
  // saved from a stale list loses the pins it's missing.
  property var savedPinned: null
  FileView {
    path: Quickshell.env("HOME") + "/.config/omarchy/shell.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      var pins = null
      function find(node) {
        if (pins || !node || typeof node !== "object") return
        if (node.id === root.moduleName && Array.isArray(node.pinned)) { pins = node.pinned; return }
        for (var k in node) find(node[k])
      }
      var config = null
      try { config = JSON.parse(text()); find(config) } catch (e) {}
      root.savedPinned = pins ? pins.map(String) : null
      var layout = config && config.bar && config.bar.layout ? config.bar.layout : {}
      root.section = ""
      for (var name in layout)
        if (Array.isArray(layout[name]) && layout[name].some(function(e) { return e && e.id === root.moduleName })) root.section = name
    }
  }
  property string section: ""   // the bar section the taskbar sits in: left, center or right

  // Move the taskbar to the start of a bar section ("left" or "center").
  // A panel's shell API can't edit the bar layout, so this goes through
  // `overtake taskbar-position`, which edits shell.json like Omarchy's own
  // bar commands do.
  function moveTaskbar(to) {
    if (root.bar) root.bar.run("overtake taskbar-position " + (to === "center" ? "center" : "left"))
  }

  readonly property var pinned: {
    if (Array.isArray(savedPinned)) return savedPinned
    var value = setting("pinned", null)
    return Array.isArray(value) ? value : defaultPinned
  }
  readonly property bool showStart: setting("showStart", true) !== false
  readonly property int iconSize: Number(setting("iconSize", 18))
  readonly property color fg: root.bar ? root.bar.barForeground : Commons.Color.foreground

  // The workspace shown on this bar's monitor.
  readonly property var barWindow: root.QsWindow.window
  readonly property var currentWorkspace: {
    var monitor = barWindow && barWindow.screen ? Hyprland.monitorFor(barWindow.screen) : null
    return monitor && monitor.activeWorkspace ? monitor.activeWorkspace : Hyprland.focusedWorkspace
  }
  readonly property string currentWorkspaceName: currentWorkspace ? String(currentWorkspace.name) : ""

  // Names given to windows from their title bar (Rename tab): address -> name.
  property var windowNames: ({})
  FileView {
    path: Quickshell.env("HOME") + "/.local/state/overtake/names.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try { root.windowNames = JSON.parse(text() || "{}") } catch (e) { root.windowNames = {} }
    }
    onLoadFailed: root.windowNames = {}
  }
  function titleOf(toplevel) {
    return root.windowNames[addressOf(toplevel)] || toplevel.title || ""
  }

  // Where each minimized window came from (written by `overtake minimize`).
  property var minimizedFrom: ({})
  FileView {
    path: Quickshell.env("HOME") + "/.local/state/overtake/minimized.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try { root.minimizedFrom = JSON.parse(text() || "{}") } catch (e) { root.minimizedFrom = {} }
    }
    onLoadFailed: root.minimizedFrom = {}
  }

  function workspaceOf(toplevel) {
    if (isMinimized(toplevel)) return String(root.minimizedFrom[addressOf(toplevel)] || "")
    return toplevel.workspace ? String(toplevel.workspace.name) : ""
  }

  function onThisWorkspace(toplevel) {
    return workspaceOf(toplevel) === root.currentWorkspaceName
  }

  function entryById(id) {
    return id ? DesktopEntries.byId(id) : null
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

  function windowAppId(toplevel) {
    if (toplevel.wayland && toplevel.wayland.appId) return String(toplevel.wayland.appId)
    var ipc = toplevel.lastIpcObject
    return ipc && ipc.class ? String(ipc.class) : ""
  }

  function iconFor(entry, appId) {
    if (appId === "org.quickshell") return Quickshell.iconPath("preferences-system", true)  // Overtake Settings
    var source = entry && entry.icon ? Quickshell.iconPath(entry.icon, true) : ""
    if (!source && appId) source = Quickshell.iconPath(appId.toLowerCase(), true)
    return source || Quickshell.iconPath("application-x-executable", true)
  }

  // What the taskbar shows: pinned apps and every app with a window open (on
  // any workspace, or minimized). `here` is the windows on (or minimized from)
  // the workspace this bar's monitor is showing; the picker reaches the rest.
  readonly property var shownGroups: root.allGroups.map(function(g) {
    return Object.assign({}, g, { here: g.windows.filter(onThisWorkspace) })
  }).filter(function(g) { return g.pinned || g.windows.length > 0 })

  // Pinned apps first (in pin order), then any other running app in workspace
  // order, across every workspace.
  readonly property var allGroups: {
    var order = []
    var byKey = {}

    for (var i = 0; i < root.pinned.length; i++) {
      var id = String(root.pinned[i])
      if (byKey[id]) continue
      byKey[id] = { key: id, entry: entryById(id), appId: id, pinned: true, windows: [] }
      order.push(id)
    }

    var toplevels = (Hyprland.toplevels.values || []).filter(function(t) {
      return t && t.workspace && (t.workspace.id > 0 || isMinimized(t))
    }).sort(function(a, b) { return workspaceOrder(a) - workspaceOrder(b) })

    for (var j = 0; j < toplevels.length; j++) {
      var appId = windowAppId(toplevels[j])
      if (appId === "org.omarchy.screensaver") continue  // not an app the user opened
      var entry = entryForAppId(appId)
      var key = entry ? entry.id : appId
      if (!key) continue
      if (!byKey[key]) {
        byKey[key] = { key: key, entry: entry, appId: appId, pinned: false, windows: [] }
        order.push(key)
      }
      byKey[key].windows.push(toplevels[j])
    }

    return order.map(function(k) { return byKey[k] })
  }

  // Minimized windows wait on the hidden special:minimized workspace (see
  // ~/.local/bin/overtake); they stay on the taskbar, dimmed.
  function isMinimized(toplevel) {
    return !!(toplevel && toplevel.workspace && toplevel.workspace.name === "special:minimized")
  }

  function workspaceOrder(toplevel) {
    return toplevel.workspace.id > 0 ? toplevel.workspace.id : 100
  }

  function visibleWindows(group) {
    return group.windows.filter(function(t) { return !isMinimized(t) })
  }

  function addressOf(toplevel) {
    var address = String(toplevel.address || "")
    return address && address.indexOf("0x") !== 0 ? "0x" + address : address
  }

  function windowCommand(action, toplevel) {
    var address = addressOf(toplevel)
    if (address && root.bar) root.bar.run("overtake " + action + " " + address)
  }

  function focusWindow(toplevel) {
    var address = addressOf(toplevel)
    if (!address || !root.bar) return
    root.bar.run("overtake show " + address)  // brings it back on screen first if it's off every screen
  }

  function launch(group) {
    var id = group.entry ? String(group.entry.id) : ""
    if (!id || !root.bar) return
    root.bar.run("uwsm-app -- gtk-launch " + Util.shellQuote(id + ".desktop"))
  }

  // The window a menu or click acts on: the focused one if it's in the group,
  // otherwise the first visible one, otherwise the first minimized one.
  function targetWindow(group) {
    if (group.windows.indexOf(Hyprland.activeToplevel) !== -1) return Hyprland.activeToplevel
    var shown = visibleWindows(group)
    return shown.length > 0 ? shown[0] : (group.windows[0] || null)
  }

  function showWindow(toplevel) {
    if (isMinimized(toplevel)) windowCommand("restore", toplevel)
    else focusWindow(toplevel)
  }

  function activate(group, anchor) {
    if (group.windows.length === 0) {
      launch(group)
    } else if (group.windows.length > 1) {
      openPopup("picker", group, anchor)
    } else if (group.windows[0] === Hyprland.activeToplevel && !isMinimized(group.windows[0])) {
      windowCommand("minimize", group.windows[0])  // clicking the focused app minimizes it
    } else {
      showWindow(group.windows[0])
    }
  }

  // ---------- Popup: window picker (left-click) or window menu (right-click) ----------
  property string popupMode: "menu"
  property var menuGroup: null
  // The popup's rows, built once when it opens. A live binding rebuilt them
  // whenever any window title changed (Claude terminals animate theirs),
  // which reset the hover highlight under the pointer.
  property var popupRows: []
  property Item menuAnchor: null

  function openPopup(mode, group, anchor) {
    root.popupMode = mode
    root.menuGroup = group
    root.menuAnchor = anchor
    root.popupRows = popupItems(group)
    root.open()
  }

  function openMenu(group, anchor) {
    openPopup("menu", group, anchor)
  }

  function workspaceLabel(toplevel) {
    var name = workspaceOf(toplevel)
    if (isMinimized(toplevel)) return name === root.currentWorkspaceName ? "Minimized" : "Minimized · ws " + name
    return name === root.currentWorkspaceName ? "This workspace" : "Workspace " + name
  }

  // Right-click on a window in the picker: what to do with that one window.
  function windowMenu(t) {
    var items = [
      { glyph: "\uf2d2", label: "Switch to", run: function() { showWindow(t) } },
      { glyph: "\uf044", label: "Rename window…", run: function() { windowCommand("rename", t) } }
    ]
    if (isMinimized(t)) items.push({ glyph: "\uf2d2", label: "Restore", run: function() { windowCommand("restore", t) } })
    else items.push({ glyph: "\uf2d1", label: "Minimize", run: function() { windowCommand("minimize", t) } })
    items.push({ glyph: "\uf00d", label: "Close window", danger: true, run: function() { windowCommand("close", t) } })
    return items
  }

  // One row per window, this workspace's first, then a "New window" row.
  // Right-click a window's row for its own menu (rename, close, ...).
  function pickerItems(group) {
    if (!group) return []
    var windows = group.windows.slice().sort(function(a, b) {
      return (onThisWorkspace(b) ? 1 : 0) - (onThisWorkspace(a) ? 1 : 0)
    })
    var items = windows.map(function(t) {
      return { glyph: isMinimized(t) ? "–" : (t === Hyprland.activeToplevel ? "●" : "○"),
               label: titleOf(t) || (group.entry ? group.entry.name : group.appId),
               detail: workspaceLabel(t),
               run: function() { showWindow(t) },
               menu: function() { return windowMenu(t) } }
    })
    if (group.entry) items.push({ glyph: "", label: "New window", run: function() { launch(group) } })
    return items
  }

  function popupItems(group) {
    return root.popupMode === "picker" ? pickerItems(group) : menuItems(group)
  }

  function menuItems(group) {
    if (!group) return []
    var items = []
    var target = targetWindow(group)
    if (target) {
      if (isMinimized(target)) items.push({ glyph: "", label: "Restore", run: function() { windowCommand("restore", target) } })
      else items.push({ glyph: "", label: "Minimize", run: function() { windowCommand("minimize", target) } })
      items.push({ glyph: "", label: "Maximize", run: function() { windowCommand("maximize", target) } })
      items.push({ glyph: "", label: "Rename window…", run: function() { windowCommand("rename", target) } })
    }
    if (group.entry) items.push({ glyph: "", label: "New window", run: function() { launch(group) } })
    if (group.entry) {
      var pinnedNow = root.pinned.indexOf(String(group.entry.id)) !== -1
      items.push({ glyph: "", label: pinnedNow ? "Unpin from taskbar" : "Pin to taskbar",
                   run: function() { togglePin(group) } })
    }
    if (group.windows.length > 0) {
      var windows = group.windows.slice()
      items.push({ glyph: "", label: windows.length > 1 ? "Close all windows" : "Close window", danger: true,
                   run: function() { windows.forEach(function(t) { windowCommand("close", t) }) } })
    }
    return items
  }

  function togglePin(group) {
    if (group.entry) togglePinId(String(group.entry.id))
  }

  function togglePinId(id) {
    if (id) setPinId(id, root.pinned.indexOf(id) === -1)
  }

  function setPinId(id, pin) {
    var next = root.pinned.slice()
    var index = next.indexOf(id)
    if (pin === (index !== -1)) return
    if (pin) next.push(id)
    else next.splice(index, 1)
    savePins(next)
  }

  function savePins(next) {
    root.savedPinned = next
    root.settings = Object.assign({}, root.settings, { pinned: next })
    if (root.bar && root.bar.shell) root.bar.shell.updateEntryInline(root.moduleName, root.settings)
  }

  // ---------- Dragging icons ----------
  // A left-button drag on the taskbar would move the whole taskbar around the
  // bar (the bar handles left presses on its entries before they reach them).
  // So this layer sits above that, on the bar's slot for this taskbar, and
  // takes the left button itself: a click is the icon's click, a drag moves
  // that app along the taskbar. Right and middle clicks pass through to the
  // icons. The Start button's right-click menu moves the taskbar instead.
  readonly property Item barSlot: {
    var p = root.parent
    while (p && !(p.activeItem !== undefined && p.moduleName === root.moduleName)) p = p.parent
    return p
  }
  property string dragKey: ""      // the app being dragged
  property real dragDX: 0
  property int dropIndex: -1       // where it would land, in shownGroups
  property real dropX: 0

  function buttonAt(point) {
    var item = row.childAt(point.x, point.y)
    return item && item.visible ? item : null
  }

  function appButtons() {
    var list = []
    for (var i = 0; i < row.children.length; i++) {
      var c = row.children[i]
      if (c.visible && c.groupKey) list.push(c)
    }
    return list
  }

  function updateDrop(x) {
    var buttons = appButtons()
    var index = buttons.length
    for (var i = 0; i < buttons.length; i++) {
      if (x < buttons[i].x + buttons[i].width / 2) { index = i; break }
    }
    root.dropIndex = index
    root.dropX = row.x + (index < buttons.length ? buttons[index].x : buttons[buttons.length - 1].x + buttons[buttons.length - 1].width)
  }

  // Drop: reorder. A pinned app stays pinned in its new place; an unpinned
  // one dropped among (or right after) the pinned ones is pinned there.
  function finishDrag() {
    var keys = root.shownGroups.map(function(g) { return String(g.key) })
    var from = keys.indexOf(root.dragKey)
    var group = root.shownGroups[from]
    if (from === -1 || root.dropIndex < 0 || !group || !group.entry) return
    var to = root.dropIndex > from ? root.dropIndex - 1 : root.dropIndex
    keys.splice(from, 1)
    keys.splice(to, 0, root.dragKey)
    var pins = {}
    root.pinned.forEach(function(id) { pins[String(id)] = true })
    var pinnedCount = Object.keys(pins).length
    if (!pins[root.dragKey] && to > pinnedCount) return   // an unpinned app among the unpinned: nothing to keep
    pins[root.dragKey] = true
    root.savePins(keys.filter(function(k) { return pins[k] }))
  }

  MouseArea {
    id: iconDrag
    parent: root.barSlot || root
    anchors.fill: parent
    z: 1000
    acceptedButtons: Qt.LeftButton
    cursorShape: dragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor
    enabled: root.visible && root.barSlot !== null

    property Item pressedButton: null
    property real pressX: 0
    property bool dragging: false

    function rowPoint(x, y) { return iconDrag.mapToItem(row, x, y) }

    onPressed: function(mouse) {
      pressX = mouse.x
      dragging = false
      pressedButton = root.buttonAt(rowPoint(mouse.x, mouse.y))
      if (root.bar && pressedButton) root.bar.hideTooltip(pressedButton)
    }
    onPositionChanged: function(mouse) {
      if (!pressedButton || !pressedButton.groupKey) return
      if (!dragging && Math.abs(mouse.x - pressX) < Style.space(6)) return
      dragging = true
      root.dragKey = pressedButton.groupKey
      root.dragDX = mouse.x - pressX
      root.updateDrop(rowPoint(mouse.x, mouse.y).x)
    }
    onReleased: function(mouse) {
      if (dragging) root.finishDrag()
      else if (pressedButton && root.buttonAt(rowPoint(mouse.x, mouse.y)) === pressedButton) pressedButton.leftClicked()
      reset()
    }
    onCanceled: reset()
    function reset() {
      dragging = false
      pressedButton = null
      root.dragKey = ""
      root.dragDX = 0
      root.dropIndex = -1
    }
  }

  // Where a dragged icon would land.
  Rectangle {
    visible: root.dragKey !== "" && root.dropIndex >= 0
    x: root.dropX - width / 2
    anchors.verticalCenter: row.verticalCenter
    width: Style.space(2)
    height: root.barSize * 0.6
    radius: width / 2
    color: Commons.Color.accent
    z: 10
  }

  // The desktop's icon menu pins and unpins apps here: it writes
  // "pin|unpin <id> <time>" to this file. Only the bar on the focused monitor
  // applies it (a bar that never loaded the settings, such as one for a
  // switched-off screen, would save its defaults over them); the first value
  // seen is just startup.
  property string lastPinRequest: ""
  property bool pinRequestSeen: false
  FileView {
    path: Quickshell.env("HOME") + "/.local/state/overtake/taskbar-pin-request"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      var value = text().trim()
      if (!value) { root.pinRequestSeen = true; return }
      if (value === root.lastPinRequest) return
      var parts = value.split(" ")
      var onFocusedMonitor = root.barWindow && root.barWindow.screen && Hyprland.focusedMonitor
        && Hyprland.focusedMonitor.name === root.barWindow.screen.name
      if (root.pinRequestSeen && onFocusedMonitor && parts.length >= 2) root.setPinId(parts[1], parts[0] === "pin")
      root.lastPinRequest = value
      root.pinRequestSeen = true
    }
    onLoadFailed: root.pinRequestSeen = true
  }

  function tooltipFor(group) {
    var name = group.entry ? group.entry.name : group.appId
    if (group.windows.length === 1) return titleOf(group.windows[0]) || name
    if (group.windows.length > 1) return name + " · " + group.windows.length + " windows (click to choose)"
    return name
  }

  visible: !root.vertical
  implicitWidth: visible ? row.implicitWidth : 0
  implicitHeight: root.barSize

  Row {
    id: row
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(2)

    TaskButton {
      id: startButton
      visible: root.showStart
      startLogo: true
      tip: "Start"
      onLeftClicked: startMenu.show("start")
      onRightClicked: startMenu.show("quick")
    }

    // Overtake Mode: switch between it and Omarchy's own desktop.
    TaskButton {
      id: osButton
      visible: root.showStart
      glyph: "\uf0ec"
      tip: "Overtake Mode"
      onLeftClicked: startMenu.show("os")
      onRightClicked: startMenu.show("os")
    }

    Repeater {
      model: root.shownGroups

      TaskButton {
        id: taskButton
        required property var modelData

        iconSource: root.iconFor(modelData.entry, modelData.appId)
        running: modelData.here.length > 0
        elsewhere: !running && modelData.windows.length > 0
        dimmed: running && root.visibleWindows({ windows: modelData.here }).length === 0
        focusedApp: modelData.here.indexOf(Hyprland.activeToplevel) !== -1
        tip: root.tooltipFor(modelData)
        groupKey: String(modelData.key)
        onLeftClicked: root.activate(modelData, taskButton)
        onMiddleClicked: root.launch(modelData)
        onRightClicked: root.openMenu(modelData, taskButton)
      }
    }
  }

  StartMenu {
    id: startMenu
    anchorItem: startButton
    osAnchorItem: osButton
    bar: root.bar
    taskbarPinned: root.pinned
    taskbarSection: root.section
    onToggleTaskbarPin: function(id) { root.togglePinId(id) }
    onMoveTaskbar: function(to) { root.moveTaskbar(to) }
  }

  // `overtake start [quick]` (Super+S / Super+X) writes "<mode> <time>" here;
  // only the bar on the focused monitor opens. A rewrite arrives as two
  // changes (truncate, then write), so only a new non-empty value counts, and
  // the first value seen is just startup.
  property string lastStartRequest: ""
  property bool startRequestSeen: false
  FileView {
    path: Quickshell.env("HOME") + "/.local/state/overtake/start-request"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      var value = text().trim()
      if (!value) { root.startRequestSeen = true; return }
      if (value === root.lastStartRequest) return
      var onFocusedMonitor = root.barWindow && root.barWindow.screen && Hyprland.focusedMonitor
        && Hyprland.focusedMonitor.name === root.barWindow.screen.name
      if (root.startRequestSeen && onFocusedMonitor) startMenu.show(value.split(" ")[0])
      root.lastStartRequest = value
      root.startRequestSeen = true
    }
    onLoadFailed: root.startRequestSeen = true
  }

  KeyboardPanel {
    id: menu
    anchorItem: root.menuAnchor || row
    owner: root
    bar: root.bar
    open: root.opened && root.menuGroup !== null
    focusTarget: menuKeys
    contentWidth: Style.space(root.popupMode === "picker" ? 380 : 230)
    contentHeight: menu.fittedContentHeight(menuColumn.implicitHeight)

    PanelKeyCatcher {
      id: menuKeys
      anchors.fill: parent
      onCloseRequested: root.close()

      Column {
        id: menuColumn
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Style.space(2)

        Text {
          width: parent.width
          bottomPadding: Style.space(6)
          textFormat: Text.PlainText
          text: root.menuGroup ? (root.menuGroup.entry ? root.menuGroup.entry.name : root.menuGroup.appId) : ""
          color: root.fg
          opacity: 0.6
          elide: Text.ElideRight
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
          font.bold: true
        }

        Repeater {
          model: root.popupRows

          Item {
            required property var modelData
            width: menuColumn.width
            height: Style.space(30)

            Rectangle {
              anchors.fill: parent
              radius: Style.space(4)
              color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, itemMouse.containsMouse ? 0.12 : 0)
            }

            Row {
              anchors.verticalCenter: parent.verticalCenter
              anchors.left: parent.left
              anchors.leftMargin: Style.space(8)
              spacing: Style.space(10)

              Text {
                width: Style.space(16)
                textFormat: Text.PlainText
                text: modelData.glyph
                color: modelData.danger && itemMouse.containsMouse ? Commons.Color.urgent : root.fg
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.body
              }

              Text {
                width: menuColumn.width - Style.space(42) - detailText.implicitWidth
                textFormat: Text.PlainText
                text: modelData.label
                elide: Text.ElideRight
                color: modelData.danger && itemMouse.containsMouse ? Commons.Color.urgent : root.fg
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.body
              }
            }

            Text {
              id: detailText
              anchors.verticalCenter: parent.verticalCenter
              anchors.right: parent.right
              anchors.rightMargin: Style.space(8)
              textFormat: Text.PlainText
              text: modelData.detail || ""
              color: root.fg
              opacity: 0.55
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
            }

            MouseArea {
              id: itemMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              acceptedButtons: Qt.LeftButton | Qt.RightButton
              onClicked: function(mouse) {
                if (mouse.button === Qt.RightButton) {
                  if (modelData.menu) root.popupRows = modelData.menu()   // that window's own menu, in place
                  return
                }
                modelData.run()
                root.close()
              }
            }
          }
        }
      }
    }
  }

  component TaskButton: Item {
    id: button

    property string iconSource: ""
    property string glyph: ""  // a font glyph instead of an icon
    property string glyphFont: ""
    property bool startLogo: false
    property bool running: false
    property bool elsewhere: false
    property bool dimmed: false
    property bool focusedApp: false
    property string tip: ""
    property string groupKey: ""     // the app this button stands for (empty: Start, Overtake Mode)
    readonly property bool beingDragged: groupKey !== "" && groupKey === root.dragKey

    z: beingDragged ? 5 : 0
    opacity: beingDragged ? 0.75 : 1
    transform: Translate { x: button.beingDragged ? root.dragDX : 0 }

    signal leftClicked()
    signal middleClicked()
    signal rightClicked()

    width: visible ? root.barSize + Style.space(6) : 0
    height: root.barSize

    Rectangle {
      anchors.fill: parent
      anchors.margins: Style.space(2)
      radius: Style.space(4)
      color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, mouse.containsMouse ? 0.14 : (button.focusedApp ? 0.08 : 0))

      Behavior on color { ColorAnimation { duration: 120 } }
    }

    Text {
      anchors.centerIn: parent
      visible: button.glyph !== ""
      textFormat: Text.PlainText
      text: button.glyph
      color: root.fg
      opacity: mouse.containsMouse ? 1 : 0.85
      font.family: button.glyphFont || (root.bar ? root.bar.fontFamily : Style.font.family)
      font.pixelSize: root.iconSize - Style.space(2)
    }

    Image {
      anchors.centerIn: parent
      visible: !button.startLogo && button.glyph === ""
      opacity: button.dimmed ? 0.45 : 1
      source: button.iconSource
      width: root.iconSize
      height: root.iconSize
      sourceSize.width: root.iconSize * 2
      sourceSize.height: root.iconSize * 2
      smooth: true
      asynchronous: true
    }

    // Start: the Omarchy logo (U+E900 in Omarchy's icon font), in the accent colour.
    Text {
      visible: button.startLogo
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: "\ue900"
      color: Commons.Color.accent
      opacity: mouse.containsMouse ? 1 : 0.9
      font.family: "omarchy"
      font.pixelSize: root.iconSize + Style.space(2)
    }

    // Running indicator: a dot, widened and accented for the focused app, and
    // faint when the app is only open on other workspaces.
    Rectangle {
      visible: button.running || button.elsewhere
      opacity: button.elsewhere ? 0.35 : 1
      anchors.bottom: parent.bottom
      anchors.bottomMargin: Style.space(2)
      anchors.horizontalCenter: parent.horizontalCenter
      height: Style.space(3)
      radius: height / 2
      width: button.focusedApp ? Style.space(14) : Style.space(5)
      color: button.focusedApp ? Commons.Color.accent : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.6)

      Behavior on width { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
    }

    MouseArea {
      id: mouse
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
      cursorShape: Qt.PointingHandCursor

      onClicked: function(event) {
        if (event.button === Qt.MiddleButton) button.middleClicked()
        else if (event.button === Qt.RightButton) button.rightClicked()
        else button.leftClicked()
      }
      onEntered: if (root.bar && button.tip) root.bar.showTooltip(button, button.tip)
      onExited: if (root.bar) root.bar.hideTooltip(button)
    }
  }
}
