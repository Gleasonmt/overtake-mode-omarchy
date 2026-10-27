import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons

// Studio's Mission Control (Ctrl+Up, or from Spotlight): every window on the
// workspace you're on, spread out as live previews, with the workspaces
// along the top. Click a window to bring it forward, click a workspace to go
// there, drag a window onto a workspace to move it there. Esc, Ctrl+Up again
// or a click on empty space closes it.
Item {
  id: root

  property bool active: false
  required property AppModel apps

  property bool open: false

  readonly property color fg: Commons.Color.foreground
  readonly property color bg: Commons.Color.background

  function toggle() {
    if (open) { open = false; return }
    Hyprland.refreshToplevels()
    open = true
  }

  readonly property var screen: Quickshell.screens.find(function(s) { return Hyprland.focusedMonitor && s.name === Hyprland.focusedMonitor.name }) || Quickshell.screens[0]
  readonly property var workspace: Hyprland.focusedWorkspace
  readonly property var windows: (Hyprland.toplevels.values || []).filter(function(t) {
    return t && t.workspace && t.workspace === root.workspace && t.lastIpcObject && t.lastIpcObject.size
  })

  // A grid that fits n windows into w x h, each cell keeping the screen's shape.
  function layout(n, w, h) {
    if (n === 0) return { cols: 1, rows: 1, cw: w, ch: h }
    var best = null
    for (var cols = 1; cols <= n; cols++) {
      var rows = Math.ceil(n / cols)
      var cw = w / cols, ch = h / rows
      var score = Math.min(cw / 16, ch / 10)
      if (!best || score > best.score) best = { cols: cols, rows: rows, cw: cw, ch: ch, score: score }
    }
    return best
  }

  property int hoverWorkspace: 0

  PanelWindow {
    id: window
    visible: root.active && root.open
    screen: root.screen
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "overtake-mission"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    anchors { top: true; bottom: true; left: true; right: true }

    Rectangle {
      anchors.fill: parent
      color: Qt.rgba(root.bg.r * 0.4, root.bg.g * 0.4, root.bg.b * 0.4, 0.72)
    }
    MouseArea { anchors.fill: parent; onClicked: root.open = false }

    Item {
      anchors.fill: parent
      focus: window.visible
      onVisibleChanged: if (visible) forceActiveFocus()
      Keys.onEscapePressed: root.open = false
    }

    // ---------- Workspaces ----------
    Row {
      id: spaces
      anchors.top: parent.top
      anchors.topMargin: 18
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: 14
      Repeater {
        model: 9
        Rectangle {
          id: space
          required property int index
          readonly property int number: index + 1
          readonly property int count: (Hyprland.toplevels.values || []).filter(function(t) { return t.workspace && t.workspace.id === space.number }).length
          readonly property bool current: root.workspace && root.workspace.id === number
          visible: count > 0 || current || number <= 3
          width: 132
          height: 74
          radius: 10
          color: root.hoverWorkspace === number ? Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.45)
                                                : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, spaceMouse.containsMouse ? 0.18 : 0.1)
          border.width: current ? 2 : 1
          border.color: current ? Commons.Color.accent : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.25)
          Text {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -6
            textFormat: Text.PlainText
            text: "Desktop " + space.number
            color: root.fg
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
          }
          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 10
            textFormat: Text.PlainText
            text: space.count === 1 ? "1 window" : space.count + " windows"
            color: root.fg
            opacity: 0.6
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
          MouseArea {
            id: spaceMouse
            anchors.fill: parent
            hoverEnabled: true
            onClicked: {
              Hyprland.dispatch("hl.dsp.focus({ workspace = \"" + space.number + "\" })")
              root.open = false
            }
          }
        }
      }
    }

    function spaceAt(x, y) {
      for (var i = 0; i < spaces.children.length; i++) {
        var c = spaces.children[i]
        if (!c.visible || !c.number) continue
        var p = c.mapFromItem(null, x, y)
        if (p.x >= 0 && p.y >= 0 && p.x <= c.width && p.y <= c.height) return c.number
      }
      return 0
    }

    // ---------- Windows ----------
    Item {
      id: stage
      anchors.top: spaces.bottom
      anchors.topMargin: 36
      anchors.bottom: parent.bottom
      anchors.bottomMargin: 60
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.leftMargin: 60
      anchors.rightMargin: 60

      readonly property var grid: root.layout(root.windows.length, width, height)

      Text {
        anchors.centerIn: parent
        visible: root.windows.length === 0
        textFormat: Text.PlainText
        text: "No windows on this desktop"
        color: root.fg
        opacity: 0.6
        font.family: Style.font.family
        font.pixelSize: Style.font.body
      }

      Repeater {
        model: root.open ? root.windows : []
        Item {
          id: thumb
          required property var modelData
          required property int index
          readonly property var size: modelData.lastIpcObject.size
          readonly property int col: index % stage.grid.cols
          readonly property int rowN: Math.floor(index / stage.grid.cols)
          readonly property real fit: Math.min((stage.grid.cw - 28) / size[0], (stage.grid.ch - 44) / size[1], 1)
          width: size[0] * fit
          height: size[1] * fit + 24
          x: col * stage.grid.cw + (stage.grid.cw - width) / 2
          y: rowN * stage.grid.ch + (stage.grid.ch - height) / 2
          z: drag.active ? 10 : 0

          property bool dragged: false

          Rectangle {
            id: frame
            width: parent.width
            height: parent.height - 24
            radius: 10
            color: Qt.rgba(root.bg.r, root.bg.g, root.bg.b, 0.6)
            border.width: thumbMouse.containsMouse ? 3 : 1
            border.color: thumbMouse.containsMouse ? Commons.Color.accent : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.25)
            clip: true

            ScreencopyView {
              anchors.fill: parent
              anchors.margins: 2
              captureSource: thumb.modelData.wayland
              live: true
              paintCursor: false
            }
          }
          Row {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            spacing: 6
            Image {
              width: 18; height: 18
              sourceSize.width: 36; sourceSize.height: 36
              source: root.apps.iconFor(root.apps.entryForAppId(root.apps.windowAppId(thumb.modelData)), root.apps.windowAppId(thumb.modelData))
              asynchronous: true
            }
            Text {
              width: Math.min(implicitWidth, thumb.width - 30)
              textFormat: Text.PlainText
              text: root.apps.titleOf(thumb.modelData)
              elide: Text.ElideRight
              color: root.fg
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }
          }

          MouseArea {
            id: thumbMouse
            anchors.fill: parent
            hoverEnabled: true
            drag.target: thumb
            drag.threshold: 10
            onPressed: thumb.dragged = false
            onPositionChanged: if (drag.active) {
              thumb.dragged = true
              var p = mapToItem(null, mouseX, mouseY)
              root.hoverWorkspace = window.spaceAt(p.x, p.y)
            }
            onReleased: function(m) {
              if (thumb.dragged) {
                thumb.dragged = false
                var target = root.hoverWorkspace
                root.hoverWorkspace = 0
                thumb.x = Qt.binding(function() { return thumb.col * stage.grid.cw + (stage.grid.cw - thumb.width) / 2 })
                thumb.y = Qt.binding(function() { return thumb.rowN * stage.grid.ch + (stage.grid.ch - thumb.height) / 2 })
                if (target && root.workspace && target !== root.workspace.id)
                  root.apps.run(["send", String(target), root.apps.addressOf(thumb.modelData)])
                return
              }
              root.open = false
              root.apps.show(thumb.modelData)
            }
          }
        }
      }
    }
  }
}
