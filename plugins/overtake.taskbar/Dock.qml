import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons

// Studio's Dock: a glass shelf along the bottom of every screen.
//
//   [Apps] pinned and running apps | minimized windows | Downloads  Trash
//
// A dot under an app means it's running (on any workspace). Click an app to
// open it, or to bring up its most recent window (switching workspace when
// it's on another one); click the focused app's icon to minimize that window.
// Middle-click opens a new window, right-click shows its windows and options
// (Keep in Dock, Hide, Quit, ...). Drag a pinned app sideways to reorder.
// Minimized windows sit after the divider until clicked. Settings:
// ~/.config/overtake/studio.json (size, magnification, auto-hide).
Item {
  id: root

  property bool active: false          // Studio look and Overtake Mode on
  property var settings: ({})
  required property AppModel apps

  readonly property int iconSize: Math.max(32, Math.min(80, Number(settings.dockSize || 48)))
  readonly property bool magnify: settings.dockMagnify !== false
  readonly property real magnifyScale: 1.6
  readonly property bool autohide: settings.dockAutohide === true
  readonly property int pad: Math.round(iconSize * 0.16)
  readonly property int cell: iconSize + pad
  readonly property int dockH: iconSize + pad * 2 + 4
  readonly property int edgeGap: 6

  readonly property color fg: Commons.Color.foreground
  readonly property color bg: Commons.Color.background
  readonly property string home: Quickshell.env("HOME")

  function run(args) { Quickshell.execDetached(["overtake"].concat(args)) }

  // ---------- Items ----------
  readonly property var appItems: apps.groups.filter(function(g) {
    return g.pinned || g.windows.some(function(t) { return !apps.isMinimized(t) }) || g.windows.length > 0
  })
  readonly property var minimizedItems: apps.windows.filter(function(t) { return apps.isMinimized(t) })

  function clickApp(group) {
    if (group.key === "overtake-apps") { run(["ui", "apps"]); return }
    if (group.windows.length === 0) { apps.launch(group); return }
    var front = apps.frontWindow(group)
    if (front === Hyprland.activeToplevel && !apps.isMinimized(front) && front.workspace === Hyprland.focusedWorkspace) {
      run(["minimize", apps.addressOf(front)])
      return
    }
    apps.show(front)
  }

  // ---------- Context menu ----------
  property var menuRows: []
  property real menuX: 0
  property var menuScreen: null
  property string menuTitle: ""

  function appMenu(group) {
    var rows = []
    group.windows.forEach(function(t) {
      rows.push({ label: apps.titleOf(t) || apps.nameOf(group), check: t === Hyprland.activeToplevel,
                  detail: apps.isMinimized(t) ? "Minimized" : (t.workspace && t.workspace !== Hyprland.focusedWorkspace ? "Workspace " + t.workspace.name : ""),
                  run: function() { apps.show(t) } })
    })
    if (rows.length) rows.push({ separator: true })
    if (group.entry) rows.push({ label: "New Window", run: function() { apps.launch(group) } })
    if (group.key !== "overtake-apps" && group.entry)
      rows.push({ label: apps.isPinned(group.key) ? "Remove from Dock" : "Keep in Dock",
                  run: function() { apps.setPinned(group.key, !apps.isPinned(group.key)) } })
    if (group.windows.length) {
      var first = apps.frontWindow(group)
      rows.push({ separator: true })
      rows.push({ label: "Show All Windows", run: function() {
        group.windows.forEach(function(t) { if (apps.isMinimized(t)) root.run(["restore", apps.addressOf(t), "stay"]) })
        apps.show(first)
      } })
      rows.push({ label: "Hide", run: function() { root.run(["hide-app", apps.addressOf(first)]) } })
      rows.push({ label: "Quit", run: function() { root.run(["quit-app", apps.addressOf(first)]) } })
    }
    return rows
  }

  function openMenu(title, rows, screen, x) {
    menuTitle = title
    menuRows = rows
    menuScreen = screen
    menuX = x
  }
  function closeMenu() { menuRows = []; menuScreen = null }

  // ---------- Downloads stack ----------
  property bool downloadsOpen: false
  property var downloadsScreen: null
  property real downloadsX: 0

  FolderListModel {
    id: downloads
    folder: "file://" + root.home + "/Downloads"
    showDirs: true
    showHidden: false
    sortField: FolderListModel.Time
    nameFilters: ["*"]
  }

  function fileIcon(name, isDir) {
    if (isDir) return Quickshell.iconPath("folder", true)
    var ext = String(name).split(".").pop().toLowerCase()
    var map = { pdf: "application-pdf", png: "image-x-generic", jpg: "image-x-generic", jpeg: "image-x-generic", webp: "image-x-generic",
                gif: "image-x-generic", mp4: "video-x-generic", mkv: "video-x-generic", webm: "video-x-generic", mp3: "audio-x-generic",
                zip: "package-x-generic", gz: "package-x-generic", xz: "package-x-generic", tar: "package-x-generic", deb: "package-x-generic",
                txt: "text-x-generic", md: "text-x-generic", doc: "x-office-document", docx: "x-office-document", odt: "x-office-document",
                xls: "x-office-spreadsheet", xlsx: "x-office-spreadsheet", ods: "x-office-spreadsheet", iso: "media-optical" }
    return Quickshell.iconPath(map[ext] || "text-x-generic", true)
  }

  // ---------- Trash ----------
  property bool trashFull: false
  Process {
    id: trashCheck
    command: ["sh", "-c", "ls -A \"$HOME/.local/share/Trash/files\" 2>/dev/null | head -n1"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.trashFull = text.trim() !== "" }
  }
  Timer { interval: 5000; repeat: true; running: root.active; triggeredOnStart: true; onTriggered: trashCheck.running = true }

  // ---------- One Dock per screen ----------
  Variants {
    model: root.active ? Quickshell.screens : []

    PanelWindow {
      id: dockWindow
      required property var modelData
      screen: modelData

      // Shown, or tucked away (auto-hide) until the pointer reaches the bottom edge.
      property bool revealed: !root.autohide || hoverArea.containsMouse || dockHold.running || root.menuScreen === modelData || (root.downloadsOpen && root.downloadsScreen === modelData)
      property real mouseX: -1
      readonly property bool magnifying: root.magnify && mouseX >= 0

      color: "transparent"
      WlrLayershell.namespace: "overtake-dock"
      WlrLayershell.layer: WlrLayer.Top
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      anchors { bottom: true; left: true; right: true }
      implicitHeight: root.dockH + root.edgeGap + Math.ceil(root.iconSize * (root.magnifyScale - 1)) + 40
      exclusionMode: root.autohide ? ExclusionMode.Ignore : ExclusionMode.Normal
      exclusiveZone: root.autohide ? 0 : root.dockH + root.edgeGap
      mask: Region { item: dockWindow.revealed ? shelf : edgeStrip }

      Timer { id: dockHold; interval: 700 }

      // The bottom-edge strip that brings an auto-hidden Dock up.
      Item {
        id: edgeStrip
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        width: shelf.width
        height: 3
      }

      Rectangle {
        id: shelf
        anchors.horizontalCenter: parent.horizontalCenter
        y: dockWindow.revealed ? parent.height - height - root.edgeGap : parent.height + 4
        Behavior on y { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        width: row.width + root.pad * 2
        height: root.dockH
        radius: Math.round(root.iconSize * 0.42)
        color: Qt.rgba(root.bg.r, root.bg.g, root.bg.b, 0.55)
        border.width: 1
        border.color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.18)

        // a soft highlight along the top edge, like light on glass
        Rectangle {
          anchors.fill: parent
          anchors.margins: 1
          radius: parent.radius - 1
          color: "transparent"
          border.width: 1
          border.color: Qt.rgba(1, 1, 1, 0.06)
        }
      }

      MouseArea {
        id: hoverArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        onPositionChanged: function(mouse) {
          var p = mapToItem(row, mouse.x, mouse.y)
          dockWindow.mouseX = p.y > -root.iconSize && p.y < row.height + root.edgeGap + 4 ? p.x : -1
        }
        onExited: { dockWindow.mouseX = -1; if (root.autohide) dockHold.restart() }
      }

      Row {
        id: row
        anchors.horizontalCenter: shelf.horizontalCenter
        anchors.bottom: shelf.bottom
        anchors.bottomMargin: root.pad + 2
        spacing: 0

        Repeater {
          model: root.appItems
          DockIcon {
            required property var modelData
            required property int index
            group: modelData
            iconSource: modelData.key === "overtake-apps" ? "" : root.apps.iconFor(modelData.entry, modelData.appId)
            glyph: modelData.key === "overtake-apps" ? "" : ""
            label: modelData.key === "overtake-apps" ? "Apps" : root.apps.nameOf(modelData)
            running: modelData.windows.length > 0
            win: dockWindow
            onLeftClicked: root.clickApp(modelData)
            onMiddleClicked: root.apps.launch(modelData)
            onRightClicked: root.openMenu(label, root.appMenu(modelData), dockWindow.modelData, centerX())
          }
        }

        DockDivider { visible: root.minimizedItems.length > 0 }

        Repeater {
          model: root.minimizedItems
          DockIcon {
            required property var modelData
            readonly property var entry: root.apps.entryForAppId(root.apps.windowAppId(modelData))
            iconSource: root.apps.iconFor(entry, root.apps.windowAppId(modelData))
            label: root.apps.titleOf(modelData)
            minimizedWindow: true
            win: dockWindow
            onLeftClicked: root.run(["restore", root.apps.addressOf(modelData)])
            onRightClicked: {
              var t = modelData
              root.openMenu(label, [
                { label: "Restore", run: function() { root.run(["restore", root.apps.addressOf(t)]) } },
                { label: "Close", run: function() { root.run(["close", root.apps.addressOf(t)]) } }
              ], dockWindow.modelData, centerX())
            }
          }
        }

        DockDivider {}

        DockIcon {
          iconSource: Quickshell.iconPath("folder-download", true) || Quickshell.iconPath("folder", true)
          label: "Downloads"
          win: dockWindow
          onLeftClicked: {
            root.downloadsOpen = !(root.downloadsOpen && root.downloadsScreen === dockWindow.modelData)
            root.downloadsScreen = dockWindow.modelData
            root.downloadsX = centerX()
          }
          onRightClicked: root.openMenu("Downloads", [
            { label: "Open in Files", run: function() { Quickshell.execDetached(["nautilus", "--new-window", root.home + "/Downloads"]) } }
          ], dockWindow.modelData, centerX())
        }

        DockIcon {
          iconSource: Quickshell.iconPath(root.trashFull ? "user-trash-full" : "user-trash", true)
          label: "Trash"
          win: dockWindow
          onLeftClicked: Quickshell.execDetached(["nautilus", "--new-window", "trash:///"])
          onRightClicked: root.openMenu("Trash", [
            { label: "Open", run: function() { Quickshell.execDetached(["nautilus", "--new-window", "trash:///"]) } },
            { label: "Empty Trash…", run: function() { Quickshell.execDetached(["sh", "-c", "notify-send -a Trash 'Empty Trash' 'Open the Trash and choose Empty to delete its files for good.'; nautilus --new-window trash:///"]) } }
          ], dockWindow.modelData, centerX())
        }
      }

      // Drag to reorder: the drop position marker.
      Rectangle {
        visible: dragState.key !== "" && dragState.dropIndex >= 0
        x: row.x + dragState.dropX - width / 2
        y: shelf.y + root.pad
        width: 3
        height: root.iconSize
        radius: 1.5
        color: Commons.Color.accent
      }
    }
  }

  // Pinned-app drag, shared by the screens' Docks.
  QtObject {
    id: dragState
    property string key: ""
    property int dropIndex: -1
    property real dropX: 0
  }

  // ---------- Menus (context menu, Downloads stack) ----------
  PanelWindow {
    visible: root.active && root.menuScreen !== null && root.menuRows.length > 0
    screen: root.menuScreen
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "overtake-dock-menu"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    anchors { top: true; bottom: true; left: true; right: true }

    MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onPressed: root.closeMenu() }

    GlassCard {
      id: menuCard
      width: 240
      height: menuCol.implicitHeight + 12
      x: Math.max(8, Math.min(root.menuX - width / 2, parent.width - width - 8))
      y: parent.height - root.dockH - root.edgeGap - height - 10
      focus: true
      Keys.onEscapePressed: root.closeMenu()

      Column {
        id: menuCol
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 6

        Text {
          width: parent.width
          leftPadding: 10
          bottomPadding: 4
          textFormat: Text.PlainText
          text: root.menuTitle
          elide: Text.ElideRight
          color: root.fg
          opacity: 0.55
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          font.bold: true
        }

        Repeater {
          model: root.menuRows
          MenuRow {
            required property var modelData
            row: modelData
            width: menuCol.width
            onActivated: { var run = modelData.run; root.closeMenu(); if (run) run() }
          }
        }
      }
    }
  }

  PanelWindow {
    visible: root.active && root.downloadsOpen && root.downloadsScreen !== null
    screen: root.downloadsScreen
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "overtake-dock-menu"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    anchors { top: true; bottom: true; left: true; right: true }

    MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onPressed: root.downloadsOpen = false }

    GlassCard {
      width: 300
      height: Math.min(420, stackList.contentHeight + 64)
      x: Math.max(8, Math.min(root.downloadsX - width / 2, parent.width - width - 8))
      y: parent.height - root.dockH - root.edgeGap - height - 10
      focus: true
      Keys.onEscapePressed: root.downloadsOpen = false

      Text {
        id: stackTitle
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.margins: 12
        textFormat: Text.PlainText
        text: downloads.count ? "Downloads" : "Downloads is empty"
        color: root.fg
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        font.bold: true
      }

      ListView {
        id: stackList
        anchors.top: stackTitle.bottom
        anchors.bottom: openFolder.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: 6
        clip: true
        model: downloads
        delegate: Item {
          required property string fileName
          required property string filePath
          required property bool fileIsDir
          width: stackList.width
          height: 36
          Rectangle {
            anchors.fill: parent
            radius: 6
            color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, fileMouse.containsMouse ? 0.12 : 0)
          }
          Image {
            id: fileGlyph
            anchors.left: parent.left
            anchors.leftMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            width: 24; height: 24
            sourceSize.width: 48; sourceSize.height: 48
            source: root.fileIcon(fileName, fileIsDir)
            asynchronous: true
          }
          Text {
            anchors.left: fileGlyph.right
            anchors.leftMargin: 10
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: fileName
            elide: Text.ElideMiddle
            color: root.fg
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
          }
          MouseArea {
            id: fileMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: { root.downloadsOpen = false; Quickshell.execDetached(["xdg-open", filePath]) }
          }
        }
      }

      Text {
        id: openFolder
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        anchors.margins: 12
        textFormat: Text.PlainText
        text: "Open in Files  "
        color: Commons.Color.accent
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: { root.downloadsOpen = false; Quickshell.execDetached(["nautilus", "--new-window", root.home + "/Downloads"]) }
        }
      }
    }
  }

  // ---------- Pieces ----------
  component GlassCard: Rectangle {
    radius: 12
    color: Qt.rgba(root.bg.r, root.bg.g, root.bg.b, 0.92)
    border.width: 1
    border.color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.16)
  }

  component MenuRow: Item {
    id: menuRow
    property var row: ({})
    signal activated()
    height: row.separator ? 9 : 28
    Rectangle {
      visible: !!menuRow.row.separator
      anchors.verticalCenter: parent.verticalCenter
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.leftMargin: 8
      anchors.rightMargin: 8
      height: 1
      color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.14)
    }
    Rectangle {
      visible: !menuRow.row.separator
      anchors.fill: parent
      radius: 6
      color: rowMouse.containsMouse ? Commons.Color.accent : "transparent"
    }
    Text {
      visible: !menuRow.row.separator
      anchors.left: parent.left
      anchors.leftMargin: 8
      anchors.verticalCenter: parent.verticalCenter
      width: 14
      textFormat: Text.PlainText
      text: menuRow.row.check ? "✓" : ""
      color: rowMouse.containsMouse ? root.bg : root.fg
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
    }
    Text {
      visible: !menuRow.row.separator
      anchors.left: parent.left
      anchors.leftMargin: 26
      anchors.right: detail.left
      anchors.rightMargin: 8
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: menuRow.row.label || ""
      elide: Text.ElideRight
      color: rowMouse.containsMouse ? root.bg : root.fg
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
    }
    Text {
      id: detail
      visible: !menuRow.row.separator
      anchors.right: parent.right
      anchors.rightMargin: 10
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: menuRow.row.detail || ""
      color: rowMouse.containsMouse ? root.bg : root.fg
      opacity: 0.6
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }
    MouseArea {
      id: rowMouse
      anchors.fill: parent
      enabled: !menuRow.row.separator
      hoverEnabled: true
      onClicked: menuRow.activated()
    }
  }

  component DockDivider: Item {
    width: visible ? root.pad * 2 + 1 : 0
    height: root.iconSize
    Rectangle {
      anchors.centerIn: parent
      width: 1
      height: parent.height * 0.8
      color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.22)
    }
  }

  component DockIcon: Item {
    id: icon

    property var group: null
    property string iconSource: ""
    property string glyph: ""
    property string label: ""
    property bool running: false
    property bool minimizedWindow: false
    property var win: null
    signal leftClicked()
    signal middleClicked()
    signal rightClicked()

    function centerX() {
      var p = icon.mapToItem(null, width / 2, 0)
      return p.x
    }

    // Magnification: grows with closeness to the pointer, within 2.5 icons.
    readonly property real distance: win && win.magnifying ? Math.abs(win.mouseX - (x + width / 2)) : 1e9
    readonly property real grow: root.magnify ? Math.max(0, 1 - distance / (root.cell * 2.5)) : 0
    readonly property real scaleNow: 1 + (root.magnifyScale - 1) * grow * grow
    readonly property bool pinnedDraggable: !!group && group.pinned && group.key !== "overtake-apps"
    readonly property bool beingDragged: !!group && dragState.key === String(group.key)

    width: root.cell * (1 + (scaleNow - 1) * 0.5)
    height: root.iconSize
    Behavior on width { enabled: !(icon.win && icon.win.magnifying); NumberAnimation { duration: 140 } }

    // Launch bounce.
    property real bounce: 0
    SequentialAnimation {
      id: bounceAnim
      loops: 2
      NumberAnimation { target: icon; property: "bounce"; to: root.iconSize * 0.45; duration: 220; easing.type: Easing.OutQuad }
      NumberAnimation { target: icon; property: "bounce"; to: 0; duration: 260; easing.type: Easing.InQuad }
    }

    Item {
      id: face
      width: root.iconSize
      height: root.iconSize
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: icon.bounce
      transformOrigin: Item.Bottom
      scale: icon.scaleNow
      opacity: icon.beingDragged ? 0.5 : 1
      Behavior on scale { enabled: !(icon.win && icon.win.magnifying); NumberAnimation { duration: 140 } }

      // Apps: a rounded tile with a grid glyph.
      Rectangle {
        visible: icon.glyph !== ""
        anchors.fill: parent
        anchors.margins: 2
        radius: width * 0.24
        gradient: Gradient {
          GradientStop { position: 0; color: Qt.lighter(Commons.Color.accent, 1.25) }
          GradientStop { position: 1; color: Qt.darker(Commons.Color.accent, 1.25) }
        }
        Text {
          anchors.centerIn: parent
          textFormat: Text.PlainText
          text: icon.glyph
          color: "#ffffff"
          font.family: Style.font.family
          font.pixelSize: parent.width * 0.46
        }
      }

      Image {
        visible: icon.glyph === ""
        anchors.fill: parent
        source: icon.iconSource
        sourceSize.width: root.iconSize * 2
        sourceSize.height: root.iconSize * 2
        smooth: true
        mipmap: true
        asynchronous: true
      }

      // A minimized window: its app icon with a small window badge.
      Rectangle {
        visible: icon.minimizedWindow
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        width: parent.width * 0.38
        height: width * 0.78
        radius: 3
        color: Qt.rgba(root.bg.r, root.bg.g, root.bg.b, 0.9)
        border.width: 1
        border.color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.5)
        Rectangle { anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right; height: 3; radius: 2; color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.5) }
      }
    }

    // Running dot.
    Rectangle {
      visible: icon.running
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.top: parent.bottom
      anchors.topMargin: 2
      width: 4
      height: 4
      radius: 2
      color: root.fg
      opacity: 0.8
    }

    // Name, above the icon while hovered.
    Rectangle {
      visible: mouse.containsMouse && icon.label !== "" && !mouse.pressed
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: face.top
      anchors.bottomMargin: root.iconSize * (icon.scaleNow - 1) + 10
      width: Math.min(280, tipText.implicitWidth + 20)
      height: tipText.implicitHeight + 8
      radius: height / 2
      color: Qt.rgba(root.bg.r, root.bg.g, root.bg.b, 0.92)
      border.width: 1
      border.color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.15)
      Text {
        id: tipText
        anchors.centerIn: parent
        width: parent.width - 20
        horizontalAlignment: Text.AlignHCenter
        textFormat: Text.PlainText
        text: icon.label
        elide: Text.ElideRight
        color: root.fg
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
      }
    }

    MouseArea {
      id: mouse
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
      cursorShape: dragState.key !== "" ? Qt.ClosedHandCursor : Qt.PointingHandCursor
      property real pressX: 0
      property bool dragged: false

      onPressed: function(m) { pressX = m.x; dragged = false }
      onPositionChanged: function(m) {
        if (!(m.buttons & Qt.LeftButton) || !icon.pinnedDraggable) return
        if (!dragged && Math.abs(m.x - pressX) < 8) return
        dragged = true
        dragState.key = String(icon.group.key)
        var rx = icon.mapToItem(icon.parent, m.x, 0).x
        // Drop position among the pinned icons (by their x).
        var kids = icon.parent.children, index = 0, dropX = 0, count = 0
        for (var i = 0; i < kids.length; i++) {
          var k = kids[i]
          if (!k.pinnedDraggable) continue
          if (rx > k.x + k.width / 2) { index = count + 1; dropX = k.x + k.width }
          else if (count === index) dropX = k.x
          count += 1
        }
        dragState.dropIndex = index
        dragState.dropX = dropX
      }
      onReleased: function(m) {
        if (dragged) {
          var key = dragState.key
          var pins = root.apps.pinned.filter(function(id) { return id !== "overtake-apps" })
          var from = pins.indexOf(key)
          var to = dragState.dropIndex > from ? dragState.dropIndex - 1 : dragState.dropIndex
          // (the Apps tile, when pinned, keeps the first place)
          var offset = root.apps.pinned.indexOf("overtake-apps") === 0 ? 1 : 0
          if (from !== -1 && to !== from) root.apps.movePin(key, to + offset)
          dragState.key = ""
          dragState.dropIndex = -1
          dragged = false
          return
        }
        if (!containsMouse) return
        if (m.button === Qt.RightButton) icon.rightClicked()
        else if (m.button === Qt.MiddleButton) icon.middleClicked()
        else {
          if (icon.group && icon.group.windows.length === 0 && icon.group.key !== "overtake-apps") bounceAnim.restart()
          icon.leftClicked()
        }
      }
      onCanceled: { dragState.key = ""; dragState.dropIndex = -1; dragged = false }
    }
  }
}
