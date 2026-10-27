import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Studio's menu bar, on the left of the top bar: the system menu (the
// Omarchy logo), the focused app's name in bold, and File, Edit, View,
// Window and Help. Linux apps don't share their own menus with the desktop,
// so these menus hold what works for every app: new window, close, the edit
// keys (sent to the app as Ctrl+key, as Super+key does), full screen, zoom,
// tiling and the app's windows. Click a title to open its menu; while one is
// open, moving over another title opens that one; arrow keys move.
//
// `overtake ui app-menu` (the logo's shortcut from scripts) opens the system menu.
Panel {
  id: root
  moduleName: "overtake.menubar"

  readonly property bool vertical: bar ? bar.vertical : false
  readonly property int barSize: bar ? bar.barSize : Style.bar.sizeHorizontal
  readonly property color fg: root.bar ? root.bar.barForeground : Commons.Color.foreground
  readonly property string fontFamily: root.bar ? root.bar.fontFamily : Style.font.family

  // ---------- The focused app ----------
  readonly property var barWindow: root.QsWindow.window
  readonly property var toplevel: {
    var t = Hyprland.activeToplevel
    // Hyprland keeps the last window as active after switching to an empty workspace.
    return t && t.workspace && t.workspace === Hyprland.focusedWorkspace ? t : null
  }
  readonly property string appId: {
    var t = root.toplevel
    if (!t) return ""
    if (t.wayland && t.wayland.appId) return String(t.wayland.appId)
    return t.lastIpcObject && t.lastIpcObject.class ? String(t.lastIpcObject.class) : ""
  }
  readonly property var entry: appId ? (webappEntry(appId) || DesktopEntries.heuristicLookup(appId) || DesktopEntries.byId(appId)) : null
  readonly property string appName: !toplevel ? "Desktop"
    : appId === "org.quickshell" ? "Settings"
    // foot, Alacritty, Ghostty… all read as "Terminal", the name a Mac shows.
    : isTerminal ? "Terminal"
    : entry ? String(entry.name) : (appId || "App")
  readonly property string address: {
    var value = toplevel ? String(toplevel.address || "") : ""
    return value && value.indexOf("0x") !== 0 ? "0x" + value : value
  }
  readonly property bool isTerminal: !!toplevel && !!toplevel.lastIpcObject
    && (toplevel.lastIpcObject.tags || []).some(function(tag) { return String(tag).replace(/\*$/, "") === "terminal" })

  function webappEntry(id) {
    var match = id.match(/^chrome-(.+)-Default$/)
    if (!match) return null
    var url = match[1].replace("__", "/").replace(/_/g, "/")
    var apps = DesktopEntries.applications.values || []
    for (var i = 0; i < apps.length; i++) if (String(apps[i].execString || "").indexOf(url) !== -1) return apps[i]
    return null
  }

  function sh(command) { Quickshell.execDetached(["sh", "-c", command]) }
  function overtake(args) { Quickshell.execDetached(["overtake"].concat(args)) }

  // A key to the focused app (after the menu has closed and the app has its
  // keyboard back), as Hyprland's send_key_state, the way Super+key does it.
  function sendKey(mods, key) {
    var addr = root.address
    if (!addr) return
    keyTimer.mods = mods
    keyTimer.key = key
    keyTimer.addr = addr
    keyTimer.restart()
  }
  Timer {
    id: keyTimer
    property string mods: ""
    property string key: ""
    property string addr: ""
    interval: 120
    onTriggered: {
      var down = "hl.dsp.send_key_state({ mods = \"" + mods + "\", key = \"" + key + "\", state = \"down\" })"
      var up = "hl.dsp.send_key_state({ mods = \"" + mods + "\", key = \"" + key + "\", state = \"up\" })"
      Quickshell.execDetached(["sh", "-c", "hyprctl dispatch \"hl.dsp.focus({ window = 'address:" + addr + "' })\" >/dev/null; hyprctl dispatch '" + down + "' >/dev/null; sleep 0.05; hyprctl dispatch '" + up + "' >/dev/null"])
    }
  }
  function appKey(key, terminalMods) {
    if (root.isTerminal) { if (terminalMods !== undefined) root.sendKey(terminalMods, key) }
    else root.sendKey("CTRL", key)
  }

  // ---------- Menus ----------
  readonly property var titles: ["system", "app", "File", "Edit", "View", "Window", "Help"]

  function rows(which) {
    var a = root.address, hasWindow = a !== ""
    var none = !hasWindow
    switch (which) {
      case "system": return [
        { label: "About This Computer", run: function() { sh("omarchy-launch-about") } },
        { separator: true },
        { label: "System Settings…", shortcut: "Super ,", run: function() { overtake(["settings"]) } },
        { label: "Omarchy Menu…", shortcut: "Super Alt Space", run: function() { sh("omarchy-menu toggle") } },
        { label: "Install Apps…", run: function() { sh("omarchy-menu toggle install") } },
        { separator: true },
        { label: "Force Quit…", shortcut: "Super Alt Esc", run: function() { overtake(["ui", "force-quit"]) } },
        { separator: true },
        { label: "Look: Studio", check: true, run: function() {} },
        { label: "Look: Classic", run: function() { overtake(["style", "classic"]) } },
        { label: "Omarchy Desktop", run: function() { overtake(["off"]) } },
        { separator: true },
        { label: "Sleep", run: function() { sh("systemctl suspend") } },
        { label: "Restart…", run: function() { sh("omarchy-menu toggle system") } },
        { label: "Shut Down…", run: function() { sh("omarchy-menu toggle system") } },
        { separator: true },
        { label: "Lock Screen", shortcut: "Ctrl Super Q", run: function() { sh("omarchy-system-lock") } },
        { label: "Log Out…", run: function() { sh("omarchy-menu toggle system") } }
      ]
      case "app": return none ? [
        { label: "Spotlight…", shortcut: "Super Space", run: function() { overtake(["ui", "spotlight"]) } },
        { label: "Apps", run: function() { overtake(["ui", "apps"]) } },
        { label: "Mission Control", shortcut: "Ctrl Up", run: function() { overtake(["ui", "mission-control"]) } },
        { separator: true },
        { label: "Show Desktop", shortcut: "Super F3", run: function() { overtake(["show-desktop"]) } }
      ] : [
        { label: "New " + root.appName + " Window", disabled: !root.entry, run: function() { launchEntry() } },
        { separator: true },
        { label: "Hide " + root.appName, shortcut: "Super H", run: function() { overtake(["hide-app", a]) } },
        { label: "Hide Others", shortcut: "Alt Super H", run: function() { overtake(["hide-others", a]) } },
        { label: "Show All", run: function() { overtake(["restore-all"]) } },
        { separator: true },
        { label: "Quit " + root.appName, shortcut: "Super Q", run: function() { overtake(["quit-app", a]) } }
      ]
      case "File": return [
        { label: "New Window", shortcut: "Super N", disabled: none, run: function() { root.appKey("N", "CTRL + SHIFT") } },
        { label: "New Tab", shortcut: "Super T", disabled: none, run: function() { root.appKey("T", "CTRL + SHIFT") } },
        { label: "Open…", shortcut: "Super O", disabled: none || root.isTerminal, run: function() { root.appKey("O") } },
        { separator: true },
        { label: "Save", shortcut: "Super S", disabled: none || root.isTerminal, run: function() { root.appKey("S") } },
        { label: "Print…", shortcut: "Super P", disabled: none || root.isTerminal, run: function() { root.appKey("P") } },
        { separator: true },
        { label: "Close Window", shortcut: "Shift Super W", disabled: none, run: function() { overtake(["close", a]) } }
      ]
      case "Edit": return [
        { label: "Undo", shortcut: "Super Z", disabled: none || root.isTerminal, run: function() { root.appKey("Z") } },
        { label: "Redo", shortcut: "Shift Super Z", disabled: none || root.isTerminal, run: function() { root.sendKey("CTRL + SHIFT", "Z") } },
        { separator: true },
        { label: "Cut", shortcut: "Super X", disabled: none || root.isTerminal, run: function() { root.sendKey("CTRL", "X") } },
        { label: "Copy", shortcut: "Super C", disabled: none, run: function() { root.isTerminal ? root.sendKey("CTRL", "Insert") : root.sendKey("CTRL", "C") } },
        { label: "Paste", shortcut: "Super V", disabled: none, run: function() { root.isTerminal ? root.sendKey("SHIFT", "Insert") : root.sendKey("CTRL", "V") } },
        { label: "Select All", shortcut: "Super A", disabled: none, run: function() { root.appKey("A", "CTRL + SHIFT") } },
        { separator: true },
        { label: "Find…", shortcut: "Super F", disabled: none, run: function() { root.appKey("F", "CTRL + SHIFT") } },
        { label: "Clipboard History…", shortcut: "Super Ctrl V", run: function() { sh("omarchy-shell shell toggle omarchy.clipboard") } },
        { label: "Emoji & Symbols", shortcut: "Ctrl Super Space", run: function() { sh("omarchy-shell shell toggle omarchy.emojis") } }
      ]
      case "View": return [
        { label: toplevel && toplevel.lastIpcObject && toplevel.lastIpcObject.fullscreen === 2 ? "Exit Full Screen" : "Enter Full Screen",
          shortcut: "Ctrl Super F", disabled: none,
          run: function() { Hyprland.dispatch("hl.dsp.window.fullscreen({ mode = \"fullscreen\", window = \"address:" + a + "\" })") } },
        { separator: true },
        { label: "Zoom In", shortcut: "Super =", disabled: none, run: function() { root.sendKey("CTRL", "equal") } },
        { label: "Zoom Out", shortcut: "Super -", disabled: none, run: function() { root.sendKey("CTRL", "minus") } },
        { label: "Actual Size", disabled: none, run: function() { root.sendKey("CTRL", "0") } },
        { separator: true },
        { label: "Reload", shortcut: "Super R", disabled: none || root.isTerminal, run: function() { root.appKey("R") } }
      ]
      case "Window": return windowRows(a, none)
      case "Help": return [
        { label: "Keyboard Shortcuts", shortcut: "Super K", run: function() { sh("omarchy-menu-keybindings") } },
        { label: "Overtake Mode Help", run: function() { sh("xdg-open https://github.com/Gleasonmt/overtake-mode-omarchy#readme") } },
        { label: "Omarchy Manual", run: function() { sh("omarchy-launch-webapp https://learn.omacom.io/2/the-omarchy-manual") } }
      ]
    }
    return []
  }

  function windowRows(a, none) {
    var list = [
      { label: "Minimize", shortcut: "Super M", disabled: none, run: function() { overtake(["minimize", a]) } },
      { label: "Zoom", disabled: none, run: function() { overtake(["maximize", a]) } },
      { label: "Fill", shortcut: "Ctrl Super Up", disabled: none, run: function() { overtake(["snap", "full", a]) } },
      { label: "Center", shortcut: "Ctrl Super C", disabled: none, run: function() { overtake(["snap", "center", a]) } },
      { separator: true },
      { label: "Left Half", shortcut: "Ctrl Super Left", disabled: none, run: function() { overtake(["snap", "left", a]) } },
      { label: "Right Half", shortcut: "Ctrl Super Right", disabled: none, run: function() { overtake(["snap", "right", a]) } },
      { label: "Top Left Quarter", disabled: none, run: function() { overtake(["snap", "top-left", a]) } },
      { label: "Top Right Quarter", disabled: none, run: function() { overtake(["snap", "top-right", a]) } },
      { label: "Bottom Left Quarter", disabled: none, run: function() { overtake(["snap", "bottom-left", a]) } },
      { label: "Bottom Right Quarter", disabled: none, run: function() { overtake(["snap", "bottom-right", a]) } },
      { label: "Return to Previous Size", shortcut: "Ctrl Super Down", disabled: none, run: function() { overtake(["unsnap", a]) } },
      { separator: true },
      { label: "Mission Control", shortcut: "Ctrl Up", run: function() { overtake(["ui", "mission-control"]) } },
      { label: "Bring All to Front", disabled: none, run: function() { bringAllToFront() } }
    ]
    // The app's own windows, the focused one ticked.
    var mine = appWindows()
    if (mine.length) list.push({ separator: true })
    mine.forEach(function(t) {
      var addr = String(t.address || "")
      if (addr.indexOf("0x") !== 0) addr = "0x" + addr
      list.push({ label: t.title || root.appName, check: t === root.toplevel,
                  run: function() { overtake([t.workspace && t.workspace.name === "special:minimized" ? "restore" : "show", addr]) } })
    })
    return list
  }

  function appWindows() {
    if (!root.appId) return []
    return (Hyprland.toplevels.values || []).filter(function(t) {
      if (!t || !t.workspace || !(t.workspace.id > 0 || t.workspace.name === "special:minimized")) return false
      var id = t.wayland && t.wayland.appId ? String(t.wayland.appId) : (t.lastIpcObject ? String(t.lastIpcObject.class || "") : "")
      return id === root.appId
    })
  }

  function bringAllToFront() {
    appWindows().forEach(function(t) {
      var addr = String(t.address || "")
      if (addr.indexOf("0x") !== 0) addr = "0x" + addr
      if (t.workspace && t.workspace.name === "special:minimized") overtake(["restore", addr, "stay"])
    })
    if (root.address) overtake(["show", root.address])
  }

  function launchEntry() {
    if (root.entry) Quickshell.execDetached(["uwsm-app", "--", "gtk-launch", String(root.entry.id) + ".desktop"])
  }

  // ---------- Open menu state ----------
  property string current: ""      // which menu is open
  property var currentRows: []
  property int cursor: -1
  property Item currentAnchor: null

  function openMenu(which, anchor) {
    current = which
    currentRows = rows(which)
    cursor = -1
    currentAnchor = anchor
    if (!root.opened) root.open()
  }
  function closeMenu() { root.close() }
  onOpenedChanged: if (!opened) current = ""

  function moveCursor(step) {
    var n = currentRows.length, i = cursor
    for (var tries = 0; tries < n; tries++) {
      i = (i + step + n) % n
      if (!currentRows[i].separator && !currentRows[i].disabled) { cursor = i; return }
    }
  }
  function switchMenu(step) {
    var i = (titles.indexOf(current) + step + titles.length) % titles.length
    var item = titleRow.children.find(function(c) { return c.which === titles[i] })
    if (item) openMenu(titles[i], item)
  }
  function activate(row) {
    if (!row || row.separator || row.disabled) return
    var run = row.run
    closeMenu()
    if (run) run()
  }

  // `overtake ui app-menu` opens the system menu (on the focused monitor's bar).
  property string lastUiRequest: ""
  property bool uiRequestSeen: false
  FileView {
    path: Quickshell.env("HOME") + "/.local/state/overtake/ui-request"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      var value = text().trim()
      if (!value || value === root.lastUiRequest) { root.uiRequestSeen = true; return }
      var seen = root.uiRequestSeen
      root.lastUiRequest = value
      root.uiRequestSeen = true
      var onFocusedMonitor = root.barWindow && root.barWindow.screen && Hyprland.focusedMonitor
        && Hyprland.focusedMonitor.name === root.barWindow.screen.name
      if (seen && onFocusedMonitor && value.split(" ")[0] === "app-menu") {
        if (root.opened && root.current === "system") root.closeMenu()
        else root.openMenu("system", logoTitle)
      }
    }
    onLoadFailed: root.uiRequestSeen = true
  }

  visible: !root.vertical
  implicitWidth: visible ? titleRow.implicitWidth + Style.space(4) : 0
  implicitHeight: root.barSize

  Row {
    id: titleRow
    anchors.verticalCenter: parent.verticalCenter
    x: Style.space(2)
    spacing: 0

    MenuTitle { id: logoTitle; which: "system"; logo: true }
    MenuTitle { which: "app"; label: root.appName; bold: true }
    Repeater {
      model: root.toplevel ? ["File", "Edit", "View", "Window", "Help"] : ["Window", "Help"]
      MenuTitle { required property string modelData; which: modelData; label: modelData }
    }
  }

  KeyboardPanel {
    id: menu
    anchorItem: root.currentAnchor || titleRow
    owner: root
    bar: root.bar
    open: root.opened && root.current !== ""
    focusTarget: menuKeys
    contentWidth: Style.space(270)
    contentHeight: menu.fittedContentHeight(menuColumn.implicitHeight)

    PanelKeyCatcher {
      id: menuKeys
      anchors.fill: parent
      onCloseRequested: root.closeMenu()
      onMoveRequested: function(dx, dy) { if (dy) root.moveCursor(dy); else if (dx) root.switchMenu(dx) }
      onActivateRequested: root.activate(root.currentRows[root.cursor])

      Column {
        id: menuColumn
        anchors.left: parent.left
        anchors.right: parent.right

        Repeater {
          model: root.currentRows
          Item {
            id: rowItem
            required property var modelData
            required property int index
            width: menuColumn.width
            height: modelData.separator ? Style.space(9) : Style.space(26)
            readonly property bool lit: !modelData.separator && !modelData.disabled && (rowMouse.containsMouse || root.cursor === index)

            Rectangle {
              visible: !!rowItem.modelData.separator
              anchors.verticalCenter: parent.verticalCenter
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.leftMargin: Style.space(6)
              anchors.rightMargin: Style.space(6)
              height: 1
              color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.14)
            }
            Rectangle {
              anchors.fill: parent
              visible: rowItem.lit
              radius: Style.space(5)
              color: Commons.Color.accent
            }
            Text {
              visible: !rowItem.modelData.separator
              x: Style.space(6)
              width: Style.space(14)
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: rowItem.modelData.check ? "✓" : ""
              color: rowItem.lit ? Commons.Color.background : root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
            Text {
              visible: !rowItem.modelData.separator
              x: Style.space(22)
              width: parent.width - x - shortcutText.implicitWidth - Style.space(18)
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: rowItem.modelData.label || ""
              elide: Text.ElideRight
              color: rowItem.lit ? Commons.Color.background : root.fg
              opacity: rowItem.modelData.disabled ? 0.4 : 1
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
            Text {
              id: shortcutText
              visible: !rowItem.modelData.separator
              anchors.right: parent.right
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: rowItem.modelData.shortcut || ""
              color: rowItem.lit ? Commons.Color.background : root.fg
              opacity: rowItem.modelData.disabled ? 0.3 : 0.55
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
            MouseArea {
              id: rowMouse
              anchors.fill: parent
              hoverEnabled: true
              enabled: !rowItem.modelData.separator
              onEntered: if (!rowItem.modelData.disabled) root.cursor = rowItem.index
              onClicked: root.activate(rowItem.modelData)
            }
          }
        }
      }
    }
  }

  component MenuTitle: Item {
    id: title
    property string which: ""
    property string label: ""
    property bool bold: false
    property bool logo: false
    readonly property bool isOpen: root.opened && root.current === which

    width: (logo ? Style.space(20) : labelText.implicitWidth) + Style.space(18)
    height: root.barSize

    Rectangle {
      anchors.fill: parent
      anchors.topMargin: Style.space(3)
      anchors.bottomMargin: Style.space(3)
      radius: Style.space(5)
      color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, title.isOpen ? 0.2 : (titleMouse.containsMouse ? 0.1 : 0))
    }
    Text {
      visible: title.logo
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: ""
      color: root.fg
      font.family: "omarchy"
      font.pixelSize: Style.font.body + 1
    }
    Text {
      id: labelText
      visible: !title.logo
      anchors.centerIn: parent
      width: Math.min(implicitWidth, Style.space(220))
      textFormat: Text.PlainText
      text: title.label
      elide: Text.ElideRight
      color: root.fg
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.bold: title.bold
    }
    // The bar lays its own mouse area over every widget (to drag widgets
    // around) and hands a click only to targets registered with it, as
    // WidgetButton does; the same list lets an open menu's overlay pass a
    // click on another title through.
    property var registeredBar: null
    function triggerPress(button) {
      if (title.isOpen) root.closeMenu()
      else root.openMenu(title.which, title)
    }
    function syncClickRegistration() {
      if (registeredBar) registeredBar.unregisterClickTarget(title)
      registeredBar = root.bar
      if (registeredBar) registeredBar.registerClickTarget(title)
    }
    Connections {
      target: root
      function onBarChanged() { title.syncClickRegistration() }
    }
    Component.onCompleted: syncClickRegistration()
    Component.onDestruction: if (registeredBar) registeredBar.unregisterClickTarget(title)

    MouseArea {
      id: titleMouse
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.NoButton
      // While a menu is open, moving onto another title opens that one.
      onEntered: if (root.opened && root.current !== "" && root.current !== title.which) root.openMenu(title.which, title)
    }
  }
}
