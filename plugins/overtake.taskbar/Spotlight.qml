import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons

// Studio's Spotlight (Super+Space): one search field for apps, actions,
// files and quick sums, in the middle of the focused screen. Tab switches to
// the Apps view, every app in a grid (the Dock's Apps tile opens it too);
// right-click an app there to keep it in the Dock (an accent dot) or take
// it out.
//
//   Up/Down (or Left/Right in Apps) move, Enter opens, Esc closes.
//   Typing "=" or a sum ("12*4") shows the answer; Enter copies it.
//
// App lists are plain copies of each app's details (live DesktopEntry
// lists swapped under a view crashed Quickshell, see StartMenu.qml).
Item {
  id: root

  property bool active: false
  property AppModel appModel: null     // right-click an app in Apps: keep in / remove from the Dock
  property bool open: false
  property string view: "search"      // "search" or "apps"
  property string query: ""
  property int cursor: 0

  readonly property color fg: Commons.Color.foreground
  readonly property color bg: Commons.Color.background
  readonly property string home: Quickshell.env("HOME")

  function show(which) {
    var target = which === "apps" ? "apps" : "search"
    if (open && view === target) { close(); return }
    view = target
    query = ""
    cursor = 0
    fileResults = []
    open = true
  }
  function close() { open = false }

  function iconSource(name) {
    var source = name ? Quickshell.iconPath(name, true) : ""
    return source || Quickshell.iconPath("application-x-executable", true)
  }

  readonly property var apps: (DesktopEntries.applications.values || [])
    .filter(function(e) { return e && !e.noDisplay && e.name })
    .map(function(e) {
      return {
        kind: "app", id: String(e.id), name: String(e.name), detail: String(e.genericName || e.comment || ""),
        icon: root.iconSource(e.icon),
        extra: [e.genericName || "", (e.keywords || []).join(" "), e.comment || ""].join(" ").toLowerCase()
      }
    })
    .sort(function(a, b) { return a.name.toLowerCase().localeCompare(b.name.toLowerCase()) })

  // Things to do, found by name like apps.
  readonly property var actions: [
    { name: "System Settings", detail: "Overtake Settings", glyph: "", command: ["overtake", "settings"], extra: "preferences control panel" },
    { name: "Lock Screen", detail: "Action", glyph: "", command: ["omarchy-system-lock"], extra: "lock" },
    { name: "Sleep", detail: "Action", glyph: "", command: ["systemctl", "suspend"], extra: "suspend" },
    { name: "Restart…", detail: "Action", glyph: "", command: ["omarchy-menu", "toggle", "system"], extra: "reboot" },
    { name: "Shut Down…", detail: "Action", glyph: "", command: ["omarchy-menu", "toggle", "system"], extra: "power off" },
    { name: "Take Screenshot", detail: "Action", glyph: "", command: ["omarchy-capture-screenshot", "region"], extra: "capture screen shot" },
    { name: "Screen Recording", detail: "Action", glyph: "", command: ["omarchy-menu", "toggle", "trigger.capture.screenrecord"], extra: "record video capture" },
    { name: "Emoji & Symbols", detail: "Action", glyph: "", command: ["omarchy-shell", "shell", "toggle", "omarchy.emojis"], extra: "emoji smiley" },
    { name: "Clipboard History", detail: "Action", glyph: "", command: ["omarchy-shell", "shell", "toggle", "omarchy.clipboard"], extra: "paste copy" },
    { name: "Change Theme", detail: "Action", glyph: "", command: ["omarchy-menu", "toggle", "style.theme"], extra: "appearance colors" },
    { name: "Change Wallpaper", detail: "Action", glyph: "", command: ["overtake", "next-wallpaper"], extra: "background desktop picture" },
    { name: "Wi-Fi", detail: "Control Center", glyph: "", command: ["omarchy-shell", "omarchy.network", "open"], extra: "network wireless internet" },
    { name: "Bluetooth", detail: "Control Center", glyph: "", command: ["omarchy-shell", "omarchy.bluetooth", "open"], extra: "devices headphones" },
    { name: "Sound", detail: "Control Center", glyph: "", command: ["omarchy-shell", "omarchy.audio", "open"], extra: "volume audio output" },
    { name: "Mission Control", detail: "Action", glyph: "", command: ["overtake", "ui", "mission-control"], extra: "windows overview expose" },
    { name: "Force Quit…", detail: "Action", glyph: "", command: ["overtake", "ui", "force-quit"], extra: "kill app not responding" },
    { name: "Omarchy Menu", detail: "Action", glyph: "", font: "omarchy", command: ["omarchy-menu", "toggle"], extra: "omarchy" },
    { name: "Keyboard Shortcuts", detail: "Help", glyph: "", command: ["omarchy-menu-keybindings"], extra: "keys bindings help" },
    { name: "Classic mode", detail: "Overtake Mode", glyph: "", command: ["overtake", "style", "classic"], extra: "taskbar start overtake style" },
    { name: "Omarchy desktop", detail: "Overtake Mode", glyph: "", command: ["overtake", "off"], extra: "tiling turn off overtake" }
  ].map(function(a) { return Object.assign({ kind: "action" }, a) })

  function matches(item, q) {
    var name = item.name.toLowerCase()
    if (name.indexOf(q) === 0) return 3
    if (name.split(/[\s\-_.]+/).some(function(w) { return w.indexOf(q) === 0 })) return 2
    if (name.indexOf(q) !== -1 || (item.extra || "").indexOf(q) !== -1) return 1
    return 0
  }

  // A sum like "12*4+1" or "=2^10" (digits, operators, brackets, dots only).
  readonly property string sumText: {
    var q = query.trim().replace(/^=/, "").replace(/\^/g, "**").replace(/[x×]/g, "*").replace(/÷/g, "/").replace(/,/g, "")
    if (!/^[\d\s.+\-*/%()]+$/.test(q) || !/\d/.test(q) || !/[+\-*/%]/.test(q.replace(/^\s*-/, ""))) return ""
    try {
      var value = Function('"use strict"; return (' + q + ')')()
      if (typeof value !== "number" || !isFinite(value)) return ""
      return String(Math.round(value * 1e10) / 1e10)
    } catch (e) { return "" }
  }

  readonly property var results: {
    var q = query.trim().toLowerCase()
    if (!q) return []
    var out = []
    if (sumText) out.push({ kind: "sum", name: sumText, detail: "= " + query.trim().replace(/^=/, "") + "  ·  Enter copies", glyph: "" })
    var scored = []
    apps.forEach(function(a) { var s = matches(a, q); if (s) scored.push({ s: s + 1, item: a }) })
    actions.forEach(function(a) { var s = matches(a, q); if (s) scored.push({ s: s, item: a }) })
    scored.sort(function(x, y) { return y.s - x.s || x.item.name.localeCompare(y.item.name) })
    out = out.concat(scored.slice(0, 12).map(function(x) { return x.item }))
    return out.concat(fileResults)
  }

  // ---------- Files (fd, after a short pause in typing) ----------
  property var fileResults: []
  onQueryChanged: {
    cursor = 0
    fileResults = []
    if (query.trim().length >= 2 && view === "search") fileTimer.restart()
  }
  Timer {
    id: fileTimer
    interval: 220
    onTriggered: {
      fileSearch.running = false
      fileSearch.wanted = root.query.trim()
      fileSearch.command = ["fd", "--ignore-case", "--max-results", "8", "--max-depth", "6", "--fixed-strings", "--", fileSearch.wanted, root.home]
      fileSearch.running = true
    }
  }
  Process {
    id: fileSearch
    property string wanted: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (fileSearch.wanted !== root.query.trim()) return
        root.fileResults = text.split("\n").filter(function(l) { return l }).map(function(path) {
          var clean = path.replace(/\/$/, "")
          var dir = path.charAt(path.length - 1) === "/"
          return { kind: "file", name: clean.split("/").pop(), path: clean, dir: dir,
                   detail: clean.replace(root.home, "~").replace(/\/[^/]*$/, ""),
                   icon: Quickshell.iconPath(dir ? "folder" : "text-x-generic", true) }
        })
      }
    }
  }

  function activate(item) {
    if (!item) return
    close()
    if (item.kind === "app") Quickshell.execDetached(["uwsm-app", "--", "gtk-launch", item.id + ".desktop"])
    else if (item.kind === "action") Quickshell.execDetached(item.command)
    else if (item.kind === "file") Quickshell.execDetached(["uwsm-app", "--", "xdg-open", item.path])
    else if (item.kind === "sum") Quickshell.execDetached(["wl-copy", "--", item.name])
  }

  // Apps view: the grid, filtered by what's typed.
  readonly property var gridApps: {
    var q = query.trim().toLowerCase()
    return q ? apps.filter(function(a) { return matches(a, q) > 0 }) : apps
  }

  PanelWindow {
    id: window
    visible: root.active && root.open
    screen: Quickshell.screens.find(function(s) { return Hyprland.focusedMonitor && s.name === Hyprland.focusedMonitor.name }) || Quickshell.screens[0]
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "overtake-spotlight-backdrop"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    anchors { top: true; bottom: true; left: true; right: true }

    // A faint dim behind the Apps view; none behind the search field.
    Rectangle {
      anchors.fill: parent
      color: Qt.rgba(0, 0, 0, root.view === "apps" ? 0.35 : 0)
      Behavior on color { ColorAnimation { duration: 150 } }
    }
    MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onPressed: root.close() }

    Rectangle {
      id: card
      readonly property bool appsView: root.view === "apps"
      width: appsView ? Math.min(parent.width - 120, 1040) : Math.min(parent.width - 48, 680)
      height: appsView ? Math.min(parent.height - 160, 720) : field.height + (resultList.count ? Math.min(resultList.contentHeight, 440) + 14 : 0) + 20
      anchors.horizontalCenter: parent.horizontalCenter
      y: appsView ? (parent.height - height) / 2 : parent.height * 0.2
      radius: 18
      color: Qt.rgba(root.bg.r, root.bg.g, root.bg.b, 0.9)
      border.width: 1
      border.color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.18)
      clip: true

      MouseArea { anchors.fill: parent }   // clicks inside don't close

      // Search field.
      Item {
        id: field
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: 10
        height: 46

        Text {
          id: lens
          anchors.left: parent.left
          anchors.leftMargin: 10
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: ""
          color: root.fg
          opacity: 0.6
          font.family: Style.font.family
          font.pixelSize: 20
        }
        TextInput {
          id: input
          anchors.left: lens.right
          anchors.leftMargin: 12
          anchors.right: viewSwitch.left
          anchors.rightMargin: 10
          anchors.verticalCenter: parent.verticalCenter
          color: root.fg
          selectionColor: Commons.Color.accent
          font.family: Style.font.family
          font.pixelSize: 22
          clip: true
          text: root.query
          onTextChanged: root.query = text
          focus: window.visible
          onVisibleChanged: if (visible) forceActiveFocus()

          Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: !input.text
            textFormat: Text.PlainText
            text: root.view === "apps" ? "Search apps" : "Spotlight Search"
            color: root.fg
            opacity: 0.4
            font: input.font
          }

          Keys.onEscapePressed: root.close()
          Keys.onTabPressed: { root.view = root.view === "apps" ? "search" : "apps"; root.cursor = 0 }
          Keys.onReturnPressed: root.activate(root.view === "apps" ? root.gridApps[root.cursor] : root.results[root.cursor])
          Keys.onEnterPressed: root.activate(root.view === "apps" ? root.gridApps[root.cursor] : root.results[root.cursor])
          Keys.onUpPressed: root.move(root.view === "apps" ? -grid.columns : -1)
          Keys.onDownPressed: root.move(root.view === "apps" ? grid.columns : 1)
          Keys.onPressed: function(e) {
            if (root.view !== "apps") return
            if (e.key === Qt.Key_Left && !input.text) { root.move(-1); e.accepted = true }
            else if (e.key === Qt.Key_Right && !input.text) { root.move(1); e.accepted = true }
          }
        }
        // Search / Apps switch (Tab).
        Row {
          id: viewSwitch
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: 4
          Repeater {
            model: [{ v: "search", glyph: "", tip: "Search" }, { v: "apps", glyph: "", tip: "Apps (Tab)" }]
            Rectangle {
              required property var modelData
              width: 34; height: 30; radius: 8
              color: root.view === modelData.v ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.14) : (switchMouse.containsMouse ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.07) : "transparent")
              Text {
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: modelData.glyph
                color: root.fg
                font.family: Style.font.family
                font.pixelSize: 14
              }
              MouseArea { id: switchMouse; anchors.fill: parent; hoverEnabled: true; onClicked: { root.view = modelData.v; root.cursor = 0; input.forceActiveFocus() } }
            }
          }
        }
      }

      Rectangle {
        visible: card.appsView || resultList.count > 0
        anchors.top: field.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: 6
        height: 1
        color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.12)
      }

      // Search results.
      ListView {
        id: resultList
        visible: !card.appsView
        anchors.top: field.bottom
        anchors.topMargin: 14
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 8
        clip: true
        model: card.appsView ? [] : root.results
        currentIndex: root.cursor
        onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
        delegate: Item {
          id: resultRow
          required property var modelData
          required property int index
          readonly property bool firstOfKind: index === 0 || root.results[index - 1].kind !== modelData.kind
          width: resultList.width
          height: 44 + (firstOfKind ? 22 : 0)

          Text {
            visible: resultRow.firstOfKind
            x: 12
            y: 2
            textFormat: Text.PlainText
            text: ({ app: "Applications", action: "Actions", file: "Files", sum: "Calculator" })[modelData.kind] || ""
            color: root.fg
            opacity: 0.5
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            font.bold: true
          }
          Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 44
            radius: 10
            color: root.cursor === resultRow.index ? Commons.Color.accent : (rowMouse.containsMouse ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.08) : "transparent")

            Image {
              id: rowIcon
              visible: !!resultRow.modelData.icon
              anchors.left: parent.left
              anchors.leftMargin: 10
              anchors.verticalCenter: parent.verticalCenter
              width: 28; height: 28
              sourceSize.width: 56; sourceSize.height: 56
              source: resultRow.modelData.icon || ""
              asynchronous: true
            }
            Text {
              visible: !resultRow.modelData.icon
              anchors.horizontalCenter: rowIcon.horizontalCenter
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: resultRow.modelData.glyph || ""
              color: root.cursor === resultRow.index ? root.bg : root.fg
              font.family: resultRow.modelData.font || Style.font.family
              font.pixelSize: 18
            }
            Text {
              anchors.left: rowIcon.right
              anchors.leftMargin: 12
              anchors.right: rowDetail.left
              anchors.rightMargin: 10
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: resultRow.modelData.name
              elide: Text.ElideRight
              color: root.cursor === resultRow.index ? root.bg : root.fg
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              font.bold: resultRow.modelData.kind === "sum"
            }
            Text {
              id: rowDetail
              anchors.right: parent.right
              anchors.rightMargin: 12
              anchors.verticalCenter: parent.verticalCenter
              width: Math.min(implicitWidth, parent.width * 0.45)
              horizontalAlignment: Text.AlignRight
              textFormat: Text.PlainText
              text: resultRow.modelData.detail || ""
              elide: Text.ElideLeft
              color: root.cursor === resultRow.index ? root.bg : root.fg
              opacity: 0.6
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }
            MouseArea {
              id: rowMouse
              anchors.fill: parent
              hoverEnabled: true
              onClicked: root.activate(resultRow.modelData)
              onEntered: root.cursor = resultRow.index
            }
          }
        }
      }

      // Apps grid.
      GridView {
        id: grid
        visible: card.appsView
        readonly property int columns: Math.max(1, Math.floor(width / cellWidth))
        anchors.top: field.bottom
        anchors.topMargin: 16
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: 18
        anchors.rightMargin: 18
        anchors.bottomMargin: 12
        cellWidth: 124
        cellHeight: 118
        clip: true
        model: card.appsView ? root.gridApps : []
        currentIndex: root.cursor
        onCurrentIndexChanged: positionViewAtIndex(currentIndex, GridView.Contain)
        delegate: Item {
          id: tile
          required property var modelData
          required property int index
          width: grid.cellWidth
          height: grid.cellHeight
          Rectangle {
            anchors.fill: parent
            anchors.margins: 4
            radius: 14
            color: root.cursor === tile.index ? Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.3)
                                             : (tileMouse.containsMouse ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.08) : "transparent")
          }
          Image {
            id: tileIcon
            anchors.horizontalCenter: parent.horizontalCenter
            y: 14
            width: 60; height: 60
            sourceSize.width: 120; sourceSize.height: 120
            source: tile.modelData.icon
            asynchronous: true
            mipmap: true
          }
          // In the Dock: a dot, as under a running app in the Dock.
          Rectangle {
            visible: !!root.appModel && root.appModel.isPinned(tile.modelData.id)
            anchors.horizontalCenter: tileIcon.horizontalCenter
            anchors.top: tileIcon.bottom
            anchors.topMargin: 1
            width: 4; height: 4; radius: 2
            color: Commons.Color.accent
          }
          Text {
            anchors.top: tileIcon.bottom
            anchors.topMargin: 8
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width - 12
            horizontalAlignment: Text.AlignHCenter
            textFormat: Text.PlainText
            text: tile.modelData.name
            elide: Text.ElideRight
            color: root.fg
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
          }
          MouseArea {
            id: tileMouse
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: function(m) {
              if (m.button === Qt.RightButton) {
                if (root.appModel) root.appModel.setPinned(tile.modelData.id, !root.appModel.isPinned(tile.modelData.id))
                return
              }
              root.activate(tile.modelData)
            }
          }
        }
      }
    }
  }

  function move(step) {
    var count = view === "apps" ? gridApps.length : results.length
    if (!count) return
    cursor = Math.max(0, Math.min(count - 1, cursor + step))
  }
}
