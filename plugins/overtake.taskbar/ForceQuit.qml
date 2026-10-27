import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons

// Studio's Force Quit (Super+Alt+Esc, or the logo menu): the open apps;
// pick one and Force Quit ends it at once (SIGKILL to its processes), after a
// confirmation, for an app that has stopped responding. Unsaved work in it is
// lost, which the confirmation says.
Item {
  id: root

  property bool active: false
  required property AppModel apps

  property bool open: false
  property int index: 0
  property bool confirming: false

  readonly property var items: apps.runningGroups
  readonly property color fg: Commons.Color.foreground
  readonly property color bg: Commons.Color.background

  function show() {
    if (open) { open = false; return }
    index = 0
    confirming = false
    open = true
  }

  function pidsOf(group) {
    var pids = []
    group.windows.forEach(function(t) {
      var pid = t.lastIpcObject ? Number(t.lastIpcObject.pid) : 0
      if (pid > 1 && pids.indexOf(pid) === -1) pids.push(pid)
    })
    return pids
  }

  function forceQuit() {
    var group = items[index]
    if (!group) return
    var pids = pidsOf(group)
    if (pids.length) Quickshell.execDetached(["kill", "-KILL"].concat(pids.map(String)))
    confirming = false
    index = Math.max(0, index - 1)
  }

  PanelWindow {
    id: window
    visible: root.active && root.open
    screen: Quickshell.screens.find(function(s) { return Hyprland.focusedMonitor && s.name === Hyprland.focusedMonitor.name }) || Quickshell.screens[0]
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "overtake-forcequit"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    anchors { top: true; bottom: true; left: true; right: true }

    MouseArea { anchors.fill: parent; onPressed: root.open = false }

    Rectangle {
      anchors.centerIn: parent
      width: 420
      height: 420
      radius: 16
      color: Qt.rgba(root.bg.r, root.bg.g, root.bg.b, 0.95)
      border.width: 1
      border.color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.18)
      focus: window.visible
      onVisibleChanged: if (visible) forceActiveFocus()
      Keys.onEscapePressed: { if (root.confirming) root.confirming = false; else root.open = false }
      Keys.onUpPressed: { root.confirming = false; root.index = Math.max(0, root.index - 1) }
      Keys.onDownPressed: { root.confirming = false; root.index = Math.min(root.items.length - 1, root.index + 1) }
      Keys.onReturnPressed: { if (root.confirming) root.forceQuit(); else root.confirming = true }

      MouseArea { anchors.fill: parent }

      Text {
        id: heading
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: 18
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        text: "Force Quit Applications"
        color: root.fg
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        font.bold: true
      }
      Text {
        id: sub
        anchors.top: heading.bottom
        anchors.topMargin: 4
        anchors.left: heading.left
        anchors.right: heading.right
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        text: "If an app doesn't respond for a while, select its name and click Force Quit."
        color: root.fg
        opacity: 0.65
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }

      Rectangle {
        id: listBox
        anchors.top: sub.bottom
        anchors.topMargin: 12
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: footer.top
        anchors.margins: 18
        anchors.bottomMargin: 12
        radius: 8
        color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.05)
        border.width: 1
        border.color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.12)
        clip: true

        ListView {
          anchors.fill: parent
          anchors.margins: 4
          model: root.items
          currentIndex: root.index
          delegate: Rectangle {
            id: appRow
            required property var modelData
            required property int index
            width: ListView.view.width
            height: 34
            radius: 6
            color: root.index === appRow.index ? Commons.Color.accent : "transparent"
            Image {
              id: appIcon
              anchors.left: parent.left
              anchors.leftMargin: 8
              anchors.verticalCenter: parent.verticalCenter
              width: 22; height: 22
              sourceSize.width: 44; sourceSize.height: 44
              source: root.apps.iconFor(appRow.modelData.entry, appRow.modelData.appId)
              asynchronous: true
            }
            Text {
              anchors.left: appIcon.right
              anchors.leftMargin: 10
              anchors.right: parent.right
              anchors.rightMargin: 8
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: root.apps.nameOf(appRow.modelData)
              elide: Text.ElideRight
              color: root.index === appRow.index ? root.bg : root.fg
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
            }
            MouseArea { anchors.fill: parent; onClicked: { root.confirming = false; root.index = appRow.index } }
          }
        }
      }

      Item {
        id: footer
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: 18
        height: 34

        Text {
          anchors.left: parent.left
          anchors.right: quitButton.left
          anchors.rightMargin: 10
          anchors.verticalCenter: parent.verticalCenter
          visible: root.confirming
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          text: root.items[root.index] ? "Force " + root.apps.nameOf(root.items[root.index]) + " to quit? Unsaved changes will be lost." : ""
          color: root.fg
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
        Rectangle {
          id: quitButton
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          width: quitLabel.implicitWidth + 28
          height: 30
          radius: 8
          enabled: root.items.length > 0
          opacity: enabled ? 1 : 0.5
          color: root.confirming ? Commons.Color.urgent : Commons.Color.accent
          Text {
            id: quitLabel
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: root.confirming ? "Force Quit" : "Force Quit…"
            color: root.bg
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            font.bold: true
          }
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: { if (root.confirming) root.forceQuit(); else root.confirming = true }
          }
        }
      }
    }
  }
}
