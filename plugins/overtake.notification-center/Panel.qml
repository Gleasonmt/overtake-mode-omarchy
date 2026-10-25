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
// how many arrived since the center was last opened. The panel groups them by
// app, newest app first, all closed; a group expands to its notifications, to act on
// (click), remove (x) or clear. The gear switches to Manage, where each app
// is set to Show, Quiet (no pop-ups, still collected) or Off; Overtake's
// notifications read those from ~/.config/overtake/notifications.json. Do Not
// Disturb sits at the bottom.
Panel {
  id: root
  moduleName: "overtake.notification-center"
  ipcTarget: "overtake.notification-center"

  readonly property string home: Quickshell.env("HOME")
  readonly property string historyDir: home + "/.local/state/omarchy/notifications/history"
  readonly property string imagesDir: home + "/.local/state/omarchy/notifications/images"
  readonly property string seenFile: home + "/.local/state/overtake/notifications-seen"
  readonly property string modesFile: home + "/.config/overtake/notifications.json"
  readonly property bool vertical: bar ? bar.vertical : false
  readonly property color fg: bar ? bar.barForeground : Commons.Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  property var entries: []   // history entries, newest first; each has .file
  property double seen: 0    // newest timestamp the user has seen in the panel
  property bool dnd: false
  property string view: "list"   // "list" or "manage"
  property var expanded: ({})    // app -> true while its group is open
  property var appModes: ({})    // app -> "quiet" | "off" (absent = show)
  readonly property int unread: entries.filter(function(e) { return (e.timestamp || 0) > seen }).length

  // One group per app, newest first: { app, icon, glyph, entries, newest, critical }.
  readonly property var groups: {
    var byApp = {}, out = []
    entries.forEach(function(e) {
      var app = String(e.app || "Notifications")
      var g = byApp[app]
      if (!g) {
        g = byApp[app] = { app: app, icon: "", glyph: "", entries: [], newest: 0, critical: false }
        out.push(g)
      }
      g.entries.push(e)
      g.newest = Math.max(g.newest, e.timestamp || 0)
      if (!g.icon) g.icon = iconFor(e)
      if (!g.glyph && e.glyph) g.glyph = e.glyph
      if (e.urgency === 2) g.critical = true
    })
    return out.sort(function(a, b) { return b.newest - a.newest })
  }

  // Apps for Manage: everything with notifications, plus any with a setting
  // (an app set to Off sends nothing new, but must stay listed to undo it).
  readonly property var knownApps: {
    var names = groups.map(function(g) { return g.app })
    Object.keys(appModes).forEach(function(app) { if (names.indexOf(app) === -1) names.push(app) })
    return names.sort(function(a, b) { return a.toLowerCase().localeCompare(b.toLowerCase()) })
  }
  function groupFor(app) {
    for (var i = 0; i < groups.length; i++) if (groups[i].app === app) return groups[i]
    return null
  }

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
      Component.onDestruction: if (reloadTimer) reloadTimer.restart()   // (gone already while the shell shuts down)
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
        // notifications, ...) are feedback, not something to come back to,
        // unless they carry an action (a screenshot's "click to edit").
        out = out.filter(function(e) { return e.app !== "omarchy-action" || !!e.execArgv })
        out.forEach(function(e) { if (e.app === "omarchy-action") e.app = "Omarchy" })
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

  FileView {
    id: modesView
    path: root.modesFile
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: { try { root.appModes = (JSON.parse(text()) || {}).apps || {} } catch (e) { root.appModes = {} } }
    onLoadFailed: root.appModes = {}
  }
  function modeOf(app) { return appModes[app] || "show" }
  function setMode(app, mode) {
    var next = Object.assign({}, appModes)
    if (mode === "show") delete next[app]
    else next[app] = mode
    appModes = next
    modesView.setText(JSON.stringify({ apps: next }, null, 2) + "\n")
  }

  // ---------- Actions ----------
  function removeAll(list) {
    var files = list.map(function(e) { return e.file }).filter(function(f) { return !!f })
    if (!files.length) return
    // each entry's file and any images Omarchy saved for it
    Quickshell.execDetached(["bash", "-c", "img=$1; shift; for f; do stem=${f##*/}; rm -f -- \"$f\" \"$img/${stem%.json}\"-*; done", "_", root.imagesDir].concat(files))
    entries = entries.filter(function(e) { return files.indexOf(e.file) === -1 })
  }
  function remove(entry) { removeAll([entry]) }

  function clearAll() {
    Quickshell.execDetached(["omarchy-shell", "notifications", "clear"])
    entries = []
  }

  // Like clicking the toast: run its action if it carried one, otherwise
  // bring the app that sent it to the front. Then it's done with.
  // What clicking does, in order: the toast's own action; a file the message
  // names (a screenshot "saved to '...png'"), opened; the app that sent it,
  // brought forward if it's open. If none of those can happen the entry
  // stays in the list rather than vanishing for nothing.
  function activate(entry) {
    var argv = null
    try { argv = JSON.parse(entry.execArgv || "") } catch (e) {}
    if (Array.isArray(argv) && argv.length && typeof argv[0] === "string" && argv[0] && argv[0].charAt(0) !== "-") {
      Quickshell.execDetached(argv)
      remove(entry)
      close()
      return
    }
    if (openProc.running) return
    openProc.entry = entry
    openProc.command = ["overtake", "notification-open", String(entry.app || ""), String(entry.appIcon || ""),
                        String(entry.body || "").replace(/<[^>]*>/g, "")]
    openProc.running = true
  }
  Process {
    id: openProc
    property var entry: null
    onExited: function(code) {
      if (code === 0) { root.remove(entry); root.close() }
      else root.showNotice("Nothing to open for this one: its app isn't installed and it doesn't name a file.")
    }
  }

  // A short message shown in the panel itself (a toast would vanish, and
  // would land in this same list).
  property string notice: ""
  function showNotice(text) { notice = text; noticeTimer.restart() }
  Timer { id: noticeTimer; interval: 6000; onTriggered: root.notice = "" }

  function toggleGroup(app) {
    var next = Object.assign({}, expanded)
    next[app] = !isOpen(app)
    expanded = next
  }
  // Every group starts closed, so the panel always opens on the short list.
  function isOpen(app) { return !!expanded[app] }

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

  onOpenedChanged: {
    if (opened) { refreshDnd(); reload(); markSeen() }
    else { view = "list"; expanded = {} }
  }
  onEntriesChanged: if (opened) markSeen()

  function ago(ts) {
    var s = Math.max(0, (Date.now() - (ts || 0)) / 1000)
    if (s < 60) return "now"
    if (s < 3600) return Math.floor(s / 60) + " min ago"
    if (s < 86400) return Math.floor(s / 3600) + " h ago"
    return Qt.formatDateTime(new Date(ts), "MMM d, h:mm AP")
  }

  // The app's own icon for its group (a message's picture, like a sender's
  // avatar, only when the app has no icon).
  function iconFor(entry) {
    var icon = String(entry.appIcon || "")
    if (icon.charAt(0) === "/") return "file://" + icon
    if (icon.indexOf("://") !== -1) return icon
    if (icon) return Quickshell.iconPath(icon, true)
    var picture = String(entry.image || "")
    return picture ? (picture.charAt(0) === "/" ? "file://" + picture : picture) : ""
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
      textFormat: Text.PlainText
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
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: {
        if (root.view === "manage") root.view = "list"
        else root.close()
      }
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(10)

        // Header: back (in Manage), title, Clear all, the gear
        Item {
          width: parent.width
          implicitHeight: Math.max(title.implicitHeight, Style.space(24))

          Row {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(6)
            IconButton {
              visible: root.view === "manage"
              glyph: ""
              onClicked: root.view = "list"
            }
            Text {
              textFormat: Text.PlainText
              id: title
              anchors.verticalCenter: parent.verticalCenter
              text: root.view === "manage" ? "Manage notifications" : "Notifications"
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
            }
          }

          Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(10)
            LinkText {
              anchors.verticalCenter: parent.verticalCenter
              visible: root.view === "list" && root.entries.length > 0
              text: "Clear all"
              onClicked: root.clearAll()
            }
            IconButton {
              visible: root.view === "list"
              glyph: ""
              onClicked: root.view = "manage"
            }
          }
        }

        // ----- List: one group per app -----
        Text {
          textFormat: Text.PlainText
          visible: root.view === "list" && root.entries.length === 0
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
          visible: root.view === "list" && root.entries.length > 0
          width: parent.width
          height: Math.min(groupList.implicitHeight, Style.space(540))
          contentHeight: groupList.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds

          Column {
            id: groupList
            width: parent.width
            spacing: Style.space(6)

            Repeater {
              model: root.groups

              Rectangle {
                id: group
                required property var modelData
                readonly property bool open: root.isOpen(modelData.app)
                width: groupList.width
                implicitHeight: groupColumn.implicitHeight
                radius: Style.cornerRadius > 0 ? Style.space(6) : 0
                color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, .05)
                border.width: modelData.critical ? 1 : 0
                border.color: Commons.Color.urgent

                Column {
                  id: groupColumn
                  width: parent.width

                  // The app's row: icon, name and count, latest message, chevron, clear
                  Rectangle {
                    width: parent.width
                    implicitHeight: headRow.implicitHeight + Style.space(16)
                    radius: group.radius
                    color: headMouse.containsMouse ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, .06) : "transparent"

                    MouseArea {
                      id: headMouse
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.toggleGroup(group.modelData.app)
                    }

                    Row {
                      id: headRow
                      x: Style.space(10)
                      y: Style.space(8)
                      width: parent.width - Style.space(20)
                      spacing: Style.space(10)

                      AppIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        source: group.modelData.icon
                        glyph: group.modelData.glyph
                      }

                      Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - Style.space(28) - Style.space(14) - Style.space(24) - parent.spacing * 3
                        spacing: Style.space(2)
                        Row {
                          width: parent.width
                          spacing: Style.space(8)
                          Text {
                            textFormat: Text.PlainText
                            text: group.modelData.app
                            color: root.fg
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.bodySmall
                            font.bold: true
                          }
                          Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            height: Style.space(16)
                            width: Math.max(height, countText.implicitWidth + Style.space(10))
                            radius: height / 2
                            color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, .14)
                            Text {
                              textFormat: Text.PlainText
                              id: countText
                              anchors.centerIn: parent
                              text: String(group.modelData.entries.length)
                              color: root.fg
                              font.family: root.fontFamily
                              font.pixelSize: Style.font.caption
                            }
                          }
                          Text {
                            textFormat: Text.PlainText
                            anchors.verticalCenter: parent.verticalCenter
                            visible: root.modeOf(group.modelData.app) === "quiet"
                            text: ""
                            color: root.fg
                            opacity: .5
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption
                          }
                          Text {
                            textFormat: Text.PlainText
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.ago(group.modelData.newest)
                            color: root.fg
                            opacity: .5
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption
                          }
                        }
                        Text {
                          width: parent.width
                          visible: !group.open
                          text: {
                            var e = group.modelData.entries[0]
                            var body = String(e.body || "").replace(/<[^>]*>/g, "").replace(/\s+/g, " ")
                            return (e.summary || "") + (body ? " — " + body : "")
                          }
                          textFormat: Text.PlainText
                          elide: Text.ElideRight
                          color: root.fg
                          opacity: .7
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.caption
                        }
                      }

                      Text {
                        textFormat: Text.PlainText
                        anchors.verticalCenter: parent.verticalCenter
                        width: Style.space(14)
                        horizontalAlignment: Text.AlignHCenter
                        text: group.open ? "" : ""
                        color: root.fg
                        opacity: .5
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                      }

                      IconButton {
                        anchors.verticalCenter: parent.verticalCenter
                        glyph: ""
                        dim: !headMouse.containsMouse
                        onClicked: root.removeAll(group.modelData.entries)
                      }
                    }
                  }

                  // Its notifications, when open
                  Column {
                    visible: group.open
                    width: parent.width
                    bottomPadding: Style.space(6)
                    spacing: Style.space(2)

                    Repeater {
                      model: group.open ? group.modelData.entries : []

                      Rectangle {
                        id: item
                        required property var modelData
                        x: Style.space(12)
                        width: group.width - Style.space(18)
                        implicitHeight: itemRow.implicitHeight + Style.space(12)
                        radius: group.radius
                        color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, itemMouse.containsMouse ? .09 : 0)

                        MouseArea {
                          id: itemMouse
                          anchors.fill: parent
                          hoverEnabled: true
                          cursorShape: Qt.PointingHandCursor
                          acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                          onClicked: function(mouse) {
                            if (mouse.button === Qt.MiddleButton) root.remove(item.modelData)
                            else root.activate(item.modelData)
                          }
                        }

                        Row {
                          id: itemRow
                          x: Style.space(10)
                          y: Style.space(6)
                          width: parent.width - Style.space(14)
                          spacing: Style.space(8)

                          Column {
                            width: parent.width - Style.space(24) - parent.spacing
                            spacing: Style.space(2)
                            Row {
                              width: parent.width
                              spacing: Style.space(8)
                              Text {
                                id: itemSummary
                                width: Math.min(implicitWidth, parent.width - itemTime.implicitWidth - Style.space(8))
                                text: item.modelData.summary || ""
                                textFormat: Text.PlainText
                                elide: Text.ElideRight
                                color: root.fg
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.bodySmall
                                font.bold: true
                              }
                              Text {
                                textFormat: Text.PlainText
                                id: itemTime
                                anchors.baseline: itemSummary.baseline
                                text: root.ago(item.modelData.timestamp)
                                color: root.fg
                                opacity: .5
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.caption
                              }
                            }
                            Text {
                              width: parent.width
                              visible: text.length > 0
                              text: String(item.modelData.body || "").replace(/<[^>]*>/g, "")
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

                          IconButton {
                            glyph: ""
                            dim: !itemMouse.containsMouse
                            onClicked: root.remove(item.modelData)
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

        // ----- Manage: each app's setting -----
        Text {
          textFormat: Text.PlainText
          visible: root.view === "manage"
          width: parent.width
          wrapMode: Text.Wrap
          text: root.knownApps.length
            ? "Show: pop-ups, then kept here.  Quiet: kept here, no pop-ups.  Off: nothing from that app."
            : "Apps appear here once they've sent a notification."
          color: root.fg
          opacity: .6
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        Flickable {
          visible: root.view === "manage" && root.knownApps.length > 0
          width: parent.width
          height: Math.min(appList.implicitHeight, Style.space(480))
          contentHeight: appList.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds

          Column {
            id: appList
            width: parent.width
            spacing: Style.space(4)

            Repeater {
              model: root.knownApps

              Item {
                id: appRow
                required property string modelData
                readonly property var group: root.groupFor(modelData)
                readonly property string mode: root.modeOf(modelData)
                width: appList.width
                implicitHeight: Style.space(38)

                Row {
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(4)
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(10)
                  AppIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    source: appRow.group ? appRow.group.icon : ""
                    glyph: appRow.group ? appRow.group.glyph : ""
                    opacity: appRow.mode === "off" ? .4 : 1
                  }
                  Text {
                    textFormat: Text.PlainText
                    anchors.verticalCenter: parent.verticalCenter
                    width: appList.width - Style.space(28) - Style.space(14) - modes.width - Style.space(12)
                    text: appRow.modelData
                    elide: Text.ElideRight
                    color: root.fg
                    opacity: appRow.mode === "off" ? .5 : 1
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                  }
                }

                // Show | Quiet | Off
                Rectangle {
                  id: modes
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  width: modeRow.implicitWidth + Style.space(4)
                  height: Style.space(26)
                  radius: Style.cornerRadius > 0 ? height / 2 : 0
                  color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, .07)
                  Row {
                    id: modeRow
                    anchors.centerIn: parent
                    Repeater {
                      model: [["show", "Show"], ["quiet", "Quiet"], ["off", "Off"]]
                      Rectangle {
                        id: modeChip
                        required property var modelData
                        readonly property bool active: appRow.mode === modelData[0]
                        width: modeLabel.implicitWidth + Style.space(18)
                        height: Style.space(22)
                        radius: modes.radius
                        color: active ? Commons.Color.accent : (modeMouse.containsMouse ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, .1) : "transparent")
                        Text {
                          textFormat: Text.PlainText
                          id: modeLabel
                          anchors.centerIn: parent
                          text: modeChip.modelData[1]
                          color: modeChip.active ? Commons.Color.background : root.fg
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.caption
                          font.bold: modeChip.active
                        }
                        MouseArea {
                          id: modeMouse
                          anchors.fill: parent
                          hoverEnabled: true
                          cursorShape: Qt.PointingHandCursor
                          onClicked: root.setMode(appRow.modelData, modeChip.modelData[0])
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }

        Text {
          textFormat: Text.PlainText
          visible: root.notice !== ""
          width: parent.width
          wrapMode: Text.Wrap
          text: "\uf05a  " + root.notice
          color: Commons.Color.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        // ----- Footer: Do Not Disturb, apart from the list -----
        Rectangle {
          width: parent.width
          height: 1
          color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, .12)
        }
        Item {
          width: parent.width
          implicitHeight: Math.max(dndLabels.implicitHeight, dndSwitch.implicitHeight)

          Column {
            id: dndLabels
            anchors.left: parent.left
            anchors.right: dndSwitch.left
            anchors.rightMargin: Style.space(12)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)
            Text {
              textFormat: Text.PlainText
              text: "  Do not disturb"
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
            Text {
              textFormat: Text.PlainText
              width: parent.width
              wrapMode: Text.Wrap
              text: root.dnd
                ? "On: pop-ups are hidden for every app; notifications still collect here"
                : "Off: notifications pop up, then collect here"
              color: root.fg
              opacity: .55
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
          ToggleSwitch {
            id: dndSwitch
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            checked: root.dnd
            onToggled: root.toggleDnd()
          }
        }
      }
    }
  }

  // ---------- Small pieces ----------
  component IconButton: Item {
    id: ib
    property string glyph: ""
    property bool dim: false
    signal clicked()
    width: Style.space(24)
    height: Style.space(24)
    opacity: dim && !ibMouse.containsMouse ? .35 : 1
    Rectangle {
      anchors.fill: parent
      radius: width / 2
      color: ibMouse.containsMouse ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, .16) : "transparent"
    }
    Text {
      textFormat: Text.PlainText
      anchors.centerIn: parent
      text: ib.glyph
      color: root.fg
      font.family: root.fontFamily
      font.pixelSize: Style.space(12)
    }
    MouseArea {
      id: ibMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: ib.clicked()
    }
  }

  component LinkText: Text {
    textFormat: Text.PlainText
    id: link
    signal clicked()
    color: linkMouse.containsMouse ? Commons.Color.accent : root.fg
    opacity: linkMouse.containsMouse ? 1 : .75
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    font.underline: linkMouse.containsMouse
    MouseArea {
      id: linkMouse
      anchors.fill: parent
      anchors.margins: -Style.space(4)
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: link.clicked()
    }
  }

  component AppIcon: Item {
    id: ai
    property string source: ""
    property string glyph: ""
    width: Style.space(28)
    height: Style.space(28)
    Image {
      id: aiImage
      anchors.fill: parent
      source: ai.source
      sourceSize.width: width * 2
      sourceSize.height: height * 2
      fillMode: Image.PreserveAspectFit
      asynchronous: true
      visible: status === Image.Ready
    }
    Text {
      textFormat: Text.PlainText
      anchors.centerIn: parent
      visible: !aiImage.visible
      text: ai.glyph || ""
      color: root.fg
      opacity: .7
      font.family: root.fontFamily
      font.pixelSize: Style.space(16)
    }
  }
}
