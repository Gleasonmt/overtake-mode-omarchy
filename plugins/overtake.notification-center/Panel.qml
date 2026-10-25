import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Notification center: a bell at the end of the Overtake Mode bar. Toasts
// move here when they time out or are closed (Omarchy files each one in its
// notification history folder; Overtake's notifications keep the last 50 and
// give critical ones 15 seconds on screen instead of forever). The bell shows
// how many arrived since the center was last opened; the panel lists them,
// newest first, to act on (click), remove (x) or clear, and has a Do Not
// Disturb switch.
Panel {
  id: root
  moduleName: "overtake.notification-center"
  ipcTarget: "overtake.notification-center"

  readonly property string home: Quickshell.env("HOME")
  readonly property string historyDir: home + "/.local/state/omarchy/notifications/history"
  readonly property string imagesDir: home + "/.local/state/omarchy/notifications/images"
  readonly property string seenFile: home + "/.local/state/overtake/notifications-seen"
  readonly property bool vertical: bar ? bar.vertical : false
  readonly property color fg: bar ? bar.barForeground : Commons.Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  property var entries: []   // history entries, newest first; each has .file
  property double seen: 0    // newest timestamp the user has seen in the panel
  property bool dnd: false
  readonly property int unread: entries.filter(function(e) { return (e.timestamp || 0) > seen }).length

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // ---------- History ----------
  // The folder model notices files coming and going; every change re-reads
  // the folder in one jq call.
  FolderListModel {
    id: folder
    folder: "file://" + root.historyDir
    nameFilters: ["*.json"]
    showDirs: false
  }
  Instantiator {
    model: folder
    delegate: QtObject {
      Component.onCompleted: reloadTimer.restart()
      Component.onDestruction: reloadTimer.restart()
    }
  }
  Timer { id: reloadTimer; interval: 150; onTriggered: root.reload() }
  function reload() {
    if (readProc.running) reloadTimer.restart()
    else readProc.running = true
  }
  Process {
    id: readProc
    command: ["bash", "-c", "shopt -s nullglob; f=(\"$1\"/*.json); (( ${#f[@]} )) && jq -c '. + {file: input_filename}' \"${f[@]}\" 2>/dev/null; true", "_", root.historyDir]
    stdout: StdioCollector {
      onStreamFinished: {
        var out = []
        String(text || "").split("\n").forEach(function(line) {
          if (!line.trim()) return
          try { out.push(JSON.parse(line)) } catch (e) {}
        })
        // Omarchy's own "you just did that" toasts (Overtake Mode on, silenced
        // notifications, ...) are feedback, not something to come back to.
        out = out.filter(function(e) { return e.app !== "omarchy-action" })
        out.sort(function(a, b) { return (b.timestamp || 0) - (a.timestamp || 0) })
        root.entries = out
      }
    }
  }
  Component.onCompleted: reload()

  FileView {
    id: seenView
    path: root.seenFile
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.seen = Number(text().trim()) || 0
  }
  function markSeen() {
    var newest = entries.length ? (entries[0].timestamp || 0) : 0
    if (newest <= seen) return
    seen = newest
    seenView.setText(String(newest) + "\n")
  }

  // ---------- Actions ----------
  function remove(entry) {
    if (!entry || !entry.file) return
    // the entry's file and any images Omarchy saved for it
    Quickshell.execDetached(["bash", "-c", "stem=${1##*/}; rm -f -- \"$1\" \"$2/${stem%.json}\"-*", "_", entry.file, root.imagesDir])
    entries = entries.filter(function(e) { return e.file !== entry.file })
  }

  function clearAll() {
    Quickshell.execDetached(["omarchy-shell", "notifications", "clear"])
    entries = []
  }

  // Like clicking the toast: run its action if it carried one, otherwise
  // bring the app that sent it to the front. Then it's done with.
  function activate(entry) {
    var argv = null
    try { argv = JSON.parse(entry.execArgv || "") } catch (e) {}
    if (Array.isArray(argv) && argv.length && typeof argv[0] === "string" && argv[0] && argv[0].charAt(0) !== "-")
      Quickshell.execDetached(argv)
    else if (entry.app)
      Quickshell.execDetached(["/usr/share/omarchy/bin/omarchy-hyprland-focus-app", String(entry.app)])
    remove(entry)
    close()
  }

  Process {
    id: dndProc
    command: ["omarchy-shell", "notifications", "dndState"]
    stdout: StdioCollector { onStreamFinished: root.dnd = String(text || "").trim() === "on" }
  }
  function refreshDnd() { if (!dndProc.running) dndProc.running = true }
  function toggleDnd() {
    dnd = !dnd
    Quickshell.execDetached(["omarchy-shell", "notifications", "setDnd", dnd ? "on" : "off"])
  }
  Timer { interval: 30000; running: true; repeat: true; triggeredOnStart: true; onTriggered: root.refreshDnd() }

  onOpenedChanged: if (opened) { refreshDnd(); reload(); markSeen() }
  onEntriesChanged: if (opened) markSeen()

  function ago(ts) {
    var s = Math.max(0, (Date.now() - (ts || 0)) / 1000)
    if (s < 60) return "now"
    if (s < 3600) return Math.floor(s / 60) + " min ago"
    if (s < 86400) return Math.floor(s / 3600) + " h ago"
    return Qt.formatDateTime(new Date(ts), "MMM d, h:mm AP")
  }

  function iconFor(entry) {
    var image = String(entry.image || "")
    if (image) return image.charAt(0) === "/" ? "file://" + image : image
    var icon = String(entry.appIcon || "")
    if (!icon) return ""
    if (icon.charAt(0) === "/") return "file://" + icon
    if (icon.indexOf("://") !== -1) return icon
    return Quickshell.iconPath(icon, true)
  }

  // ---------- The bell ----------
  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.dnd ? "" : (root.unread > 0 ? "" : "")
    tooltipText: root.dnd ? "Do not disturb is on" : (root.unread > 0 ? root.unread + " new notification" + (root.unread === 1 ? "" : "s") : "Notifications")
    onPressed: function(b) { root.toggle() }
  }

  Rectangle {
    visible: root.unread > 0
    anchors.right: button.right
    anchors.top: button.top
    anchors.rightMargin: Style.space(1)
    anchors.topMargin: Math.max(Style.space(5), (button.height - Style.space(22)) / 2)
    height: Style.space(14)
    width: Math.max(height, badgeText.implicitWidth + Style.space(6))
    radius: height / 2
    color: Commons.Color.accent
    Text {
      id: badgeText
      anchors.centerIn: parent
      text: root.unread > 9 ? "9+" : String(root.unread)
      color: Commons.Color.background
      font.family: root.fontFamily
      font.pixelSize: Style.space(9)
      font.bold: true
    }
  }

  // ---------- The panel ----------
  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(10)

        // Header: title, Do Not Disturb, Clear all
        Item {
          width: parent.width
          implicitHeight: Math.max(title.implicitHeight, dndSwitch.implicitHeight)

          Text {
            id: title
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "Notifications"
            color: root.fg
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.bold: true
          }

          Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(12)

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: "Do not disturb"
              color: root.fg
              opacity: .7
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
            ToggleSwitch {
              id: dndSwitch
              anchors.verticalCenter: parent.verticalCenter
              checked: root.dnd
              onToggled: root.toggleDnd()
            }
            Text {
              id: clearAllText
              anchors.verticalCenter: parent.verticalCenter
              visible: root.entries.length > 0
              text: "Clear all"
              color: clearMouse.containsMouse ? Commons.Color.accent : root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.underline: clearMouse.containsMouse
              MouseArea {
                id: clearMouse
                anchors.fill: parent
                anchors.margins: -Style.space(4)
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.clearAll()
              }
            }
          }
        }

        Text {
          visible: root.entries.length === 0
          width: parent.width
          topPadding: Style.space(18)
          bottomPadding: Style.space(18)
          horizontalAlignment: Text.AlignHCenter
          text: "No new notifications"
          color: root.fg
          opacity: .55
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        Flickable {
          visible: root.entries.length > 0
          width: parent.width
          height: Math.min(list.implicitHeight, Style.space(520))
          contentHeight: list.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds

          Column {
            id: list
            width: parent.width
            spacing: Style.space(6)

            Repeater {
              model: root.entries

              Rectangle {
                id: row
                required property var modelData
                width: list.width
                implicitHeight: rowContent.implicitHeight + Style.space(16)
                radius: Style.cornerRadius > 0 ? Style.space(6) : 0
                color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, rowMouse.containsMouse ? .1 : .05)
                border.width: modelData.urgency === 2 ? 1 : 0
                border.color: Commons.Color.urgent

                MouseArea {
                  id: rowMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                  onClicked: function(mouse) {
                    if (mouse.button === Qt.MiddleButton) root.remove(row.modelData)
                    else root.activate(row.modelData)
                  }
                }

                Row {
                  id: rowContent
                  x: Style.space(10)
                  y: Style.space(8)
                  width: parent.width - Style.space(20)
                  spacing: Style.space(10)

                  Item {
                    width: Style.space(28)
                    height: Style.space(28)
                    Image {
                      id: rowIcon
                      anchors.fill: parent
                      source: root.iconFor(row.modelData)
                      sourceSize.width: width * 2
                      sourceSize.height: height * 2
                      fillMode: Image.PreserveAspectFit
                      asynchronous: true
                      visible: status === Image.Ready
                    }
                    Text {
                      anchors.centerIn: parent
                      visible: !rowIcon.visible
                      text: row.modelData.glyph || ""
                      color: root.fg
                      opacity: .7
                      font.family: root.fontFamily
                      font.pixelSize: Style.space(16)
                    }
                  }

                  Column {
                    width: parent.width - Style.space(28) - Style.space(10) - Style.space(24)
                    spacing: Style.space(2)

                    Text {
                      width: parent.width
                      text: (row.modelData.app || "Notification") + "  ·  " + root.ago(row.modelData.timestamp)
                      elide: Text.ElideRight
                      color: root.fg
                      opacity: .55
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                    Text {
                      width: parent.width
                      text: row.modelData.summary || ""
                      textFormat: Text.PlainText
                      elide: Text.ElideRight
                      color: root.fg
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.bodySmall
                      font.bold: true
                    }
                    Text {
                      width: parent.width
                      visible: text.length > 0
                      text: String(row.modelData.body || "").replace(/<[^>]*>/g, "")
                      textFormat: Text.PlainText
                      wrapMode: Text.Wrap
                      maximumLineCount: 3
                      elide: Text.ElideRight
                      color: root.fg
                      opacity: .8
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.bodySmall
                    }
                  }

                  // remove this one
                  Item {
                    width: Style.space(24)
                    height: Style.space(24)
                    opacity: rowMouse.containsMouse || xMouse.containsMouse ? 1 : .35
                    Rectangle {
                      anchors.fill: parent
                      radius: width / 2
                      color: xMouse.containsMouse ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, .16) : "transparent"
                    }
                    Text {
                      anchors.centerIn: parent
                      text: ""
                      color: root.fg
                      font.family: root.fontFamily
                      font.pixelSize: Style.space(12)
                    }
                    MouseArea {
                      id: xMouse
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.remove(row.modelData)
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
