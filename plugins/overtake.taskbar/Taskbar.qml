import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Taskbar, one per workspace (like virtual desktops):
// a Start button, pinned apps, and the apps open (or minimized from) the
// workspace this bar's monitor is showing, grouped by app. Left-click launches
// an app that isn't running and toggles focus/minimize for a single window; an
// app with several windows (on any workspace) opens a picker to choose one.
// Middle-click opens a new window; right-click opens a window menu.
Panel {
  id: root
  moduleName: "overtake.taskbar"

  readonly property bool vertical: bar ? bar.vertical : false
  readonly property int barSize: bar ? bar.barSize : Style.bar.sizeHorizontal

  readonly property var defaultPinned: ["chromium", "org.gnome.Nautilus", "foot"]
  readonly property var pinned: {
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

  // What this workspace's taskbar shows: pinned apps, plus apps with a window
  // open on (or minimized from) this workspace. Each group still carries all of
  // its app's windows so the picker can reach the other workspaces.
  readonly property var shownGroups: root.allGroups.map(function(g) {
    return Object.assign({}, g, { here: g.windows.filter(onThisWorkspace) })
  }).filter(function(g) { return g.pinned || g.here.length > 0 })

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

  // One row per window, this workspace's first, then a "New window" row.
  function pickerItems(group) {
    if (!group) return []
    var windows = group.windows.slice().sort(function(a, b) {
      return (onThisWorkspace(b) ? 1 : 0) - (onThisWorkspace(a) ? 1 : 0)
    })
    var items = windows.map(function(t) {
      return { glyph: isMinimized(t) ? "–" : (t === Hyprland.activeToplevel ? "●" : "○"),
               label: t.title || (group.entry ? group.entry.name : group.appId),
               detail: workspaceLabel(t),
               run: function() { showWindow(t) } }
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
    if (!id) return
    var next = root.pinned.slice()
    var index = next.indexOf(id)
    if (index === -1) next.push(id)
    else next.splice(index, 1)
    root.settings = Object.assign({}, root.settings, { pinned: next })
    if (root.bar && root.bar.shell) root.bar.shell.updateEntryInline(root.moduleName, root.settings)
  }

  function tooltipFor(group) {
    var name = group.entry ? group.entry.name : group.appId
    if (group.windows.length === 1) return group.windows[0].title || name
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
    onToggleTaskbarPin: function(id) { root.togglePinId(id) }
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
              onClicked: {
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
