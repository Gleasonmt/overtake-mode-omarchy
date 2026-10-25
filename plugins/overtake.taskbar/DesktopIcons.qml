import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons

// Desktop icons in a column on the left of each screen, drawn on
// the layer just above the wallpaper (so windows cover them, and they show on
// empty workspaces and with Super+D). Click selects, double-click opens.
// The list lives in ~/.config/overtake/desktop-icons.txt. Besides desktop
// entry ids it understands "trash", "browser" (your default browser) and
// "terminal" (your default terminal); apps that aren't installed are skipped.
Item {
  id: root

  property bool modeOn: false
  property var icons: []
  property string selected: ""

  FileView {
    path: Quickshell.env("HOME") + "/.config/overtake/desktop-icons.txt"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      root.icons = text().split("\n").map(function(line) { return line.trim() })
        .filter(function(line) { return line && line.charAt(0) !== "#" })
        .map(function(line) {
          var parts = line.split("|").map(function(p) { return p.trim() })
          return { id: parts[0], label: parts[1] || "" }
        })
        .filter(function(icon) { return root.builtIn[icon.id] || DesktopEntries.byId(icon.id) })
    }
  }

  // Icons that aren't a desktop entry: what they open and how they look.
  readonly property var builtIn: ({
    trash: { icon: "user-trash", label: "Trash", command: ["uwsm-app", "--", "nautilus", "trash:///"] },
    browser: { icon: "web-browser", label: "Browser", command: ["omarchy-launch-browser"] },
    terminal: { icon: "utilities-terminal", label: "Terminal", command: ["uwsm-app", "--", "omarchy-launch-terminal"] }
  })

  function entryFor(icon) {
    return root.builtIn[icon.id] ? null : DesktopEntries.byId(icon.id)
  }

  function labelFor(icon) {
    if (icon.label) return icon.label
    if (root.builtIn[icon.id]) return root.builtIn[icon.id].label
    var entry = entryFor(icon)
    return entry ? entry.name : icon.id
  }

  function iconSource(icon) {
    var name = root.builtIn[icon.id] ? root.builtIn[icon.id].icon : (entryFor(icon) ? entryFor(icon).icon : "")
    var source = name ? Quickshell.iconPath(name, true) : ""
    return source || Quickshell.iconPath("application-x-executable", true)
  }

  function open(icon) {
    if (root.builtIn[icon.id]) Quickshell.execDetached(root.builtIn[icon.id].command)
    else Quickshell.execDetached(["uwsm-app", "--", "gtk-launch", icon.id + ".desktop"])
    root.selected = ""
  }

  Variants {
    model: Quickshell.screens

    PanelWindow {
      required property var modelData

      screen: modelData
      visible: root.modeOn && root.icons.length > 0
      color: "transparent"
      exclusionMode: ExclusionMode.Ignore
      WlrLayershell.namespace: "overtake-desktop"
      WlrLayershell.layer: WlrLayer.Bottom
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

      anchors { top: true; left: true }
      margins { top: Style.space(16); left: Style.space(16) }
      implicitWidth: iconColumn.implicitWidth
      implicitHeight: iconColumn.implicitHeight

      Column {
        id: iconColumn
        spacing: Style.space(6)

        Repeater {
          model: root.icons

          Item {
            id: tile
            required property var modelData
            readonly property bool isSelected: root.selected === modelData.id

            width: Style.space(92)
            height: Style.space(88)

            Rectangle {
              anchors.fill: parent
              radius: Style.space(4)
              color: tile.isSelected ? Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.35)
                                     : Qt.rgba(1, 1, 1, area.containsMouse ? 0.12 : 0)
              border.width: tile.isSelected || area.containsMouse ? 1 : 0
              border.color: Qt.rgba(1, 1, 1, 0.25)
            }

            Image {
              id: image
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.top: parent.top
              anchors.topMargin: Style.space(8)
              width: Style.space(44)
              height: width
              sourceSize.width: width * 2
              sourceSize.height: height * 2
              source: root.iconSource(tile.modelData)
              smooth: true
              asynchronous: true
            }

            Text {
              anchors.top: image.bottom
              anchors.topMargin: Style.space(6)
              anchors.horizontalCenter: parent.horizontalCenter
              width: parent.width - Style.space(8)
              horizontalAlignment: Text.AlignHCenter
              textFormat: Text.PlainText
              text: root.labelFor(tile.modelData)
              color: "#ffffff"
              style: Text.Outline
              styleColor: Qt.rgba(0, 0, 0, 0.6)
              wrapMode: Text.WordWrap
              maximumLineCount: 2
              elide: Text.ElideRight
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
            }

            MouseArea {
              id: area
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.selected = tile.modelData.id
              onDoubleClicked: root.open(tile.modelData)
            }
          }
        }
      }
    }
  }
}
