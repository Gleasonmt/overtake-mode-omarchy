import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons

// Studio's App Switcher: hold Super and tap Tab to step through open apps
// (most recently used first), Shift+Tab to step back; let go of Super to
// switch. Arrow keys and the pointer pick too, Q quits the picked app, Esc
// cancels. Each Super+Tab arrives as `overtake ui switcher` (Hyprland's
// binding runs even while this panel has the keyboard), so the first one
// opens it on the next app and the rest step along.
//
// Super+` (`overtake ui app-windows`) brings up the focused app's next window.
Item {
  id: root

  property bool active: false
  required property AppModel apps

  property bool open: false
  property var items: []
  property int index: 0

  readonly property color fg: Commons.Color.foreground
  readonly property color bg: Commons.Color.background

  function step(delta) {
    if (!open) {
      items = apps.recentGroups.slice()
      if (items.length === 0) return
      // The focused app is first, so the first press lands on the one before.
      index = items.length > 1 ? (delta > 0 ? 1 : items.length - 1) : 0
      open = true
      return
    }
    if (items.length) index = (index + delta + items.length) % items.length
  }

  function commit() {
    if (!open) return
    var group = items[index]
    open = false
    if (group) apps.show(apps.frontWindow(group))
  }

  function cancel() { open = false }

  function quitPicked() {
    var group = items[index]
    if (!group) return
    var first = apps.frontWindow(group)
    if (first) apps.run(["quit-app", apps.addressOf(first)])
    items = items.filter(function(g) { return g !== group })
    if (!items.length) { open = false; return }
    index = Math.min(index, items.length - 1)
  }

  // Super+`: the focused app's windows in turn (on this workspace first).
  function nextAppWindow() {
    var t = Hyprland.activeToplevel
    if (!t) return
    var group = apps.groups.find(function(g) { return g.windows.indexOf(t) !== -1 })
    if (!group) return
    var list = group.windows.filter(function(w) { return !apps.isMinimized(w) })
    if (list.length < 2) return
    var i = list.indexOf(t)
    apps.show(list[(i + 1) % list.length])
  }

  // If Super came up before the panel had the keyboard (a quick tap), the
  // release is never seen here; Hyprland's release binding sends a commit.
  PanelWindow {
    id: window
    visible: root.active && root.open
    screen: Quickshell.screens.find(function(s) { return Hyprland.focusedMonitor && s.name === Hyprland.focusedMonitor.name }) || Quickshell.screens[0]
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "overtake-switcher"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    anchors { top: true; bottom: true; left: true; right: true }

    MouseArea { anchors.fill: parent; onPressed: root.cancel() }

    Item {
      id: keys
      focus: window.visible
      onVisibleChanged: if (visible) forceActiveFocus()
      Keys.onReleased: function(e) {
        if (e.key === Qt.Key_Super_L || e.key === Qt.Key_Super_R || e.key === Qt.Key_Meta) root.commit()
      }
      Keys.onPressed: function(e) {
        switch (e.key) {
          case Qt.Key_Escape: root.cancel(); break
          case Qt.Key_Return: case Qt.Key_Enter: case Qt.Key_Space: root.commit(); break
          case Qt.Key_Right: case Qt.Key_End: root.step(1); break
          case Qt.Key_Left: case Qt.Key_Home: root.step(-1); break
          case Qt.Key_Q: root.quitPicked(); break
          default: return
        }
        e.accepted = true
      }
    }

    Rectangle {
      anchors.centerIn: parent
      width: Math.min(parent.width - 48, strip.width + 36)
      height: 150
      radius: 22
      color: Qt.rgba(root.bg.r, root.bg.g, root.bg.b, 0.82)
      border.width: 1
      border.color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.18)
      clip: true

      MouseArea { anchors.fill: parent }

      Row {
        id: strip
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -10
        spacing: 6
        Repeater {
          model: root.items
          Item {
            id: cellItem
            required property var modelData
            required property int index
            width: 96
            height: 96
            Rectangle {
              anchors.fill: parent
              radius: 16
              color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, root.index === cellItem.index ? 0.18 : 0)
              border.width: root.index === cellItem.index ? 1 : 0
              border.color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.25)
            }
            Image {
              anchors.centerIn: parent
              width: 72; height: 72
              sourceSize.width: 144; sourceSize.height: 144
              source: root.apps.iconFor(cellItem.modelData.entry, cellItem.modelData.appId)
              mipmap: true
              asynchronous: true
              opacity: cellItem.modelData.windows.every(function(t) { return root.apps.isMinimized(t) }) ? 0.55 : 1
            }
            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              onEntered: root.index = cellItem.index
              onClicked: { root.index = cellItem.index; root.commit() }
            }
          }
        }
      }
      // The name under the picked app, kept inside the panel.
      Text {
        id: pickedName
        anchors.top: strip.bottom
        anchors.topMargin: 10
        width: Math.min(implicitWidth, parent.width - 32)
        x: Math.max(16, Math.min(parent.width - 16 - width, strip.x + root.index * (96 + strip.spacing) + 48 - width / 2))
        horizontalAlignment: Text.AlignHCenter
        textFormat: Text.PlainText
        text: root.items[root.index] ? root.apps.nameOf(root.items[root.index]) : ""
        elide: Text.ElideRight
        color: root.fg
        font.family: Style.font.family
        font.pixelSize: Style.font.body
      }
    }
  }
}
