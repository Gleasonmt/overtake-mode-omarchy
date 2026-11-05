import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Notification center: a bell at the end of the Overtake Mode bar. Toasts
// move here when they time out or are closed (Omarchy files each one in its
// history, the last 100 for a day; Overtake's notifications give critical
// ones 15 seconds on screen instead of forever). The bell shows
// how many arrived since the center was last opened. The panel groups them by
// app, newest app first, all closed; a group expands to its notifications, to act on
// (click), remove (x) or clear. The gear switches to Manage, where each app
// is set to Show, Quiet (no pop-ups, still collected) or Off; Overtake's
// notifications read those from ~/.config/overtake/notifications.json. Do Not
// Disturb sits at the bottom.
//
// With "clock": true in its bar entry (Overtake's Studio look) the bell is
// the date and time instead, as in a menu bar, with a dot for new ones.
Panel {
  id: root
  moduleName: "overtake.notification-center"
  ipcTarget: "overtake.notification-center"

  readonly property string home: Quickshell.env("HOME")
  readonly property string stateDir: home + "/.local/state/omarchy/notifications"
  readonly property string historyFile: stateDir + "/history.json"   // Omarchy's, newest closed first
  readonly property string quietFile: stateDir + "/quiet.json"       // Omarchy's Do Not Disturb
  readonly property string seenFile: home + "/.local/state/overtake/notifications-seen"
  readonly property string modesFile: home + "/.config/overtake/notifications.json"
  readonly property bool vertical: bar ? bar.vertical : false
  readonly property color fg: bar ? bar.barForeground : Commons.Color.foreground
  // The panel sits on the theme's background, not over the wallpaper.
  readonly property color panelFg: Commons.Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  property var entries: []   // history entries, newest first; each has .key
  property double seen: 0    // newest timestamp the user has seen in the panel
  property bool dnd: false
  property string view: "list"   // "list" or "manage"
  property var expanded: ({})    // app -> true while its group is open
  property var appModes: ({})    // app -> "quiet" | "off" (absent = show)
  readonly property int unread: entries.filter(function(e) { return (e.timestamp || 0) > seen }).length

  // One group per app, newest first: { app, icon, glyph, entries, newest, critical }.
  readonly property var groups: {
    var byApp = Object.create(null), out = []   // (no inherited keys: an app may call itself "constructor")
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
  // (Not "Omarchy" or "Notifications": the panel's names for Omarchy's own
  // feedback and for senders without a name, which a setting can't reach.)
  readonly property var knownApps: {
    var names = groups.map(function(g) { return g.app }).filter(function(app) { return app !== "Omarchy" && app !== "Notifications" })
    Object.keys(appModes).forEach(function(app) { if (names.indexOf(app) === -1) names.push(app) })
    return names.sort(function(a, b) { return a.toLowerCase().localeCompare(b.toLowerCase()) })
  }
  function groupFor(app) {
    for (var i = 0; i < groups.length; i++) if (groups[i].app === app) return groups[i]
    return null
  }

  readonly property bool clockMode: setting("clock", false) === true
  property date now: new Date()
  Timer { interval: root.clockMode ? 1000 : 30000; repeat: true; running: root.clockMode || root.opened; onTriggered: root.now = new Date() }

  implicitWidth: clockMode ? clockText.implicitWidth + Style.space(18) + (root.unread > 0 || root.dnd ? Style.space(12) : 0) : button.implicitWidth
  implicitHeight: clockMode ? (bar ? bar.barSize : Style.bar.sizeHorizontal) : button.implicitHeight

  // ---------- History ----------
  // Omarchy keeps it in one file (the last 100, for a day), rewritten whole a
  // moment after each change: watched, not polled.
  FileView {
    id: historyView
    path: root.historyFile
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.entries = root.parseHistory(text())
    onLoadFailed: root.entries = []
  }
  function reload() { historyView.reload() }
  function parseHistory(raw) {
    var list
    try { list = JSON.parse(String(raw || "").trim() || "[]") } catch (e) { return [] }
    if (!Array.isArray(list)) return []
    var out = []
    list.forEach(function(e) {
      if (!e || typeof e !== "object" || typeof e.key !== "string") return
      // Omarchy's own "you just did that" toasts (Overtake Mode on, silenced
      // notifications, ...) are feedback, not something to come back to,
      // unless they carry an action (a screenshot's "click to edit").
      if (e.app === "omarchy-action" && !e.execArgv) return
      var entry = Object.assign({}, e)
      if (entry.app === "omarchy-action") entry.app = "Omarchy"
      // When it arrived, in ms (Omarchy writes seconds; the seen file is ms).
      entry.timestamp = Math.round(Number(e.ts || e.closed_ts || 0) * 1000)
      out.push(entry)
    })
    out.sort(function(a, b) { return b.timestamp - a.timestamp })
    return out
  }

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
    onLoaded: {
      try {
        var apps = (JSON.parse(text()) || {}).apps
        root.appModes = apps && typeof apps === "object" && !Array.isArray(apps) ? apps : {}
      } catch (e) { root.appModes = {} }
    }
    onLoadFailed: root.appModes = {}
  }
  function modeOf(app) {
    var mode = Object.prototype.hasOwnProperty.call(appModes, app) ? appModes[app] : ""
    return mode === "quiet" || mode === "off" ? mode : "show"
  }
  function setMode(app, mode) {
    if (app === "__proto__") return   // (an app name a plain object can't hold)
    var next = Object.assign({}, appModes)
    if (mode === "show") delete next[app]
    else next[app] = mode
    appModes = next
    modesView.setText(JSON.stringify({ apps: next }, null, 2) + "\n")
  }

  // A body as text: notification bodies are markup ("Tom &amp; Jerry",
  // <b>…</b>), so the spec's tags go and entities are decoded, as Omarchy's
  // Markup.oneLine does (a "<" that isn't one of those tags stays).
  readonly property var entities: ({ amp: "&", lt: "<", gt: ">", quot: "\"", apos: "'", nbsp: " " })
  function decodeOnce(text) {
    return text
      .replace(/&#(\d{1,7});/g, function(m, n) { var c = parseInt(n, 10); return c > 0 && c < 0x110000 ? String.fromCodePoint(c) : m })
      .replace(/&#x([0-9a-f]{1,6});/gi, function(m, n) { var c = parseInt(n, 16); return c > 0 && c < 0x110000 ? String.fromCodePoint(c) : m })
      .replace(/&([a-z]+);/gi, function(m, name) { var hit = root.entities[name.toLowerCase()]; return hit === undefined ? m : hit })
  }
  function plainBody(body, keepLines) {
    var text = String(body || "").slice(0, 32768)
      .replace(/<\/?(?:b|i|u|s|em|strong|a|img|br)\b[^>]*>/gi, function(tag) { return /^<br/i.test(tag) ? "\n" : "" })
    for (var i = 0; i < 3; i++) { var once = decodeOnce(text); if (once === text) break; text = once }
    return keepLines ? text.trim() : text.replace(/\s+/g, " ").trim()
  }

  // ---------- Actions ----------
  // History is the notifications service's own (it rewrites the file from
  // memory), so entries are taken out through it: Overtake's copy answers
  // `forget`. Omarchy's own doesn't, and the reload then
  // puts the rows back.
  function removeAll(list) {
    var keys = list.map(function(e) { return String(e.key || "") })
                   .filter(function(k) { return /^[A-Za-z0-9_-]{1,120}$/.test(k) })
    if (!keys.length) return
    keys.forEach(function(k) { if (pendingKeys.indexOf(k) === -1) pendingKeys.push(k) })
    entries = entries.filter(function(e) { return keys.indexOf(e.key) === -1 })
    sendPending()
  }
  function remove(entry) { removeAll([entry]) }

  // Clear all takes out what the panel shows, not anything that arrived
  // since it last read the file.
  function clearAll() { removeAll(entries.slice()) }
  // Removals wait their turn: one call at a time, the rest queued.
  property var pendingKeys: []
  function sendPending() {
    if (historyProc.running || !pendingKeys.length) return
    var args = ["forget", pendingKeys.join(" ")]
    pendingKeys = []
    historyProc.command = ["omarchy-shell", "notifications"].concat(args)
    historyProc.running = true
  }
  Process {
    id: historyProc
    stdout: StdioCollector {
      onStreamFinished: {
        var reply = String(text || "").trim()
        // "none": already gone (taken out, or aged out of Omarchy's day)
        if (reply === "notready") root.showNotice("Notifications are still loading; try again in a moment.")
        else if (reply !== "ok" && reply !== "none")
          root.showNotice("Couldn't remove: Overtake's notifications aren't loaded (overtake build-copies all).")
        reloadSoon.restart()
      }
    }
    onExited: root.sendPending()
  }
  Timer {   // the file as it now stands, once nothing is still on its way
    id: reloadSoon
    interval: 500
    onTriggered: if (historyProc.running || root.pendingKeys.length) restart(); else root.reload()
  }

  // Like clicking the toast, in Omarchy's order: its own action; the app that
  // sent it, brought forward if it's open; for a browser's web notification,
  // its site. Nothing is opened from the message text. If none of those
  // can happen the entry stays in the list rather than vanishing for nothing.
  function activate(entry) {
    // The toast's own action, checked and run exactly as Omarchy's own
    // notifications do (an argv of strings, through a login shell's PATH).
    // (Omarchy's parseExecArgv: up to 32 strings of up to 4096 characters,
    // no NUL, not starting with an option)
    var argv = null, raw = String(entry.execArgv || "")
    if (raw.length <= 32768) try { argv = JSON.parse(raw) } catch (e) {}
    var valid = Array.isArray(argv) && argv.length > 0 && argv.length <= 32
      && argv.every(function(a) { return typeof a === "string" && a.length <= 4096 && a.indexOf("\u0000") === -1 })
      && argv[0] !== "" && argv[0].charAt(0) !== "-"
    if (valid) {
      Quickshell.execDetached(["bash", "-lc", 'exec "$@"', "bash"].concat(argv))
      remove(entry)
      close()
      return
    }
    if (openProc.running) return
    openProc.entry = entry
    // (the app's name, to find its window, as Omarchy's own toasts do)
    openProc.command = ["overtake", "notification-open", String(entry.app || "")]
    openProc.running = true
  }
  Process {
    id: openProc
    property var entry: null
    onExited: function(code) {
      if (code === 0) { root.remove(entry); root.close(); return }
      // No window: a browser's web notification opens its site, as Omarchy's
      // toasts do (Omarchy marks those "web:<host>"; a plain hostname only).
      var host = root.webHost(entry)
      if (host) {
        Qt.openUrlExternally("https://" + host + "/")
        root.remove(entry)
        root.close()
      } else root.showNotice("Nothing to open for this one: it has no action, and its app isn't open.")
    }
  }

  function webHost(entry) {
    var key = String(entry && entry.groupKey || "")
    if (key.indexOf("web:") !== 0) return ""
    var host = key.slice(4).toLowerCase()
    return host.length <= 253 && /^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)+$/.test(host)
      && !/^(?:0x[0-9a-f]*|[0-9]+)$/.test(host.split(".").pop()) ? host : ""
  }

  // A short message shown in the panel itself (a toast would vanish, and
  // would land in this same list).
  property string notice: ""
  function showNotice(text) { notice = text; noticeTimer.restart() }
  Timer { id: noticeTimer; interval: 6000; onTriggered: root.notice = "" }

  function toggleGroup(app) {
    if (app === "__proto__") return
    var next = Object.assign({}, expanded)
    next[app] = !isOpen(app)
    expanded = next
  }
  // Every group starts closed, so the panel always opens on the short list.
  function isOpen(app) { return Object.prototype.hasOwnProperty.call(expanded, app) && expanded[app] === true }

  Process {
    id: dndProc
    command: ["omarchy-shell", "notifications", "isDnd"]
    stdout: StdioCollector { onStreamFinished: root.dnd = String(text || "").trim() === "on" }
  }
  function refreshDnd() { if (!dndProc.running) dndProc.running = true }
  function toggleDnd() {
    dnd = !dnd
    Quickshell.execDetached(["omarchy-shell", "notifications", "setDnd", dnd ? "on" : "off"])
  }
  // Omarchy saves Do Not Disturb to this file on every change: watched, not polled.
  FileView {
    path: root.quietFile
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try { var s = JSON.parse(text()); if (typeof s.dnd === "boolean") root.dnd = s.dnd } catch (e) {}
    }
  }

  onOpenedChanged: {
    if (opened) { now = new Date(); refreshDnd(); reload(); markSeen() }
    else { view = "list"; expanded = {} }
  }
  onEntriesChanged: if (opened) markSeen()

  function ago(ts) {
    var s = Math.max(0, (root.now.getTime() - (ts || 0)) / 1000)   // (root.now: "now" ages while the panel is open)
    if (s < 60) return "now"
    if (s < 3600) return Math.floor(s / 60) + " min ago"
    if (s < 86400) return Math.floor(s / 3600) + " h ago"
    return Qt.formatDateTime(new Date(ts), "MMM d, h:mm AP")
  }

  // The app's own icon for its group: a theme icon by plain name only (Omarchy
  // keeps only those in history), so nothing the sender names is read or fetched.
  function iconFor(entry) {
    var icon = String(entry.appIcon || "")
    return /^[A-Za-z0-9_.-]{1,256}$/.test(icon) ? Quickshell.iconPath(icon, true) : ""
  }

  // ---------- The bell ----------
  // ---------- Studio: the clock ----------
  Item {
    id: clockButton
    visible: root.clockMode
    anchors.fill: parent
    Rectangle {
      anchors.fill: parent
      anchors.topMargin: Style.space(3)
      anchors.bottomMargin: Style.space(3)
      radius: Style.space(5)
      color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, root.opened ? 0.2 : (clockMouse.containsMouse ? 0.1 : 0))
    }
    Text {
      id: clockText
      anchors.verticalCenter: parent.verticalCenter
      x: Style.space(9)
      textFormat: Text.PlainText
      text: Qt.formatDateTime(root.now, "ddd MMM d  h:mm AP")
      color: root.fg
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
    // New notifications (a dot), or Do Not Disturb (a moon).
    Text {
      visible: root.dnd
      anchors.left: clockText.right
      anchors.leftMargin: Style.space(5)
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: "\uf186"
      color: root.fg
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
    Rectangle {
      visible: !root.dnd && root.unread > 0
      anchors.left: clockText.right
      anchors.leftMargin: Style.space(6)
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(7); height: width; radius: width / 2
      color: Commons.Color.accent
    }
    MouseArea {
      id: clockMouse
      anchors.fill: parent
      hoverEnabled: true
      onClicked: root.toggle()
      onEntered: if (root.bar) root.bar.showTooltip(clockButton, root.dnd ? "Do not disturb is on" : (root.unread > 0 ? root.unread + " new notification" + (root.unread === 1 ? "" : "s") : Qt.formatDateTime(root.now, "dddd, MMMM d, yyyy")))
      onExited: if (root.bar) root.bar.hideTooltip(clockButton)
    }
  }

  BarIconButton {
    id: button
    visible: !root.clockMode
    anchors.fill: parent
    bar: root.bar
    text: root.dnd ? "" : (root.unread > 0 ? "" : "")
    tooltipText: root.dnd ? "Do not disturb is on" : (root.unread > 0 ? root.unread + " new notification" + (root.unread === 1 ? "" : "s") : "Notifications")
    onPressed: function(b) { root.toggle() }
  }

  Rectangle {
    visible: root.unread > 0 && !root.clockMode
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
    anchorItem: root.clockMode ? clockButton : button
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
              color: root.panelFg
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
          color: root.panelFg
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
                color: Qt.rgba(root.panelFg.r, root.panelFg.g, root.panelFg.b, .05)
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
                    color: headMouse.containsMouse ? Qt.rgba(root.panelFg.r, root.panelFg.g, root.panelFg.b, .06) : "transparent"

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
                            color: root.panelFg
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.bodySmall
                            font.bold: true
                          }
                          Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            height: Style.space(16)
                            width: Math.max(height, countText.implicitWidth + Style.space(10))
                            radius: height / 2
                            color: Qt.rgba(root.panelFg.r, root.panelFg.g, root.panelFg.b, .14)
                            Text {
                              textFormat: Text.PlainText
                              id: countText
                              anchors.centerIn: parent
                              text: String(group.modelData.entries.length)
                              color: root.panelFg
                              font.family: root.fontFamily
                              font.pixelSize: Style.font.caption
                            }
                          }
                          Text {
                            textFormat: Text.PlainText
                            anchors.verticalCenter: parent.verticalCenter
                            visible: root.modeOf(group.modelData.app) === "quiet"
                            text: ""
                            color: root.panelFg
                            opacity: .5
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption
                          }
                          Text {
                            textFormat: Text.PlainText
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.ago(group.modelData.newest)
                            color: root.panelFg
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
                            var body = root.plainBody(e.body, false)
                            return (e.summary || "") + (body ? " — " + body : "")
                          }
                          textFormat: Text.PlainText
                          elide: Text.ElideRight
                          color: root.panelFg
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
                        color: root.panelFg
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
                        color: Qt.rgba(root.panelFg.r, root.panelFg.g, root.panelFg.b, itemMouse.containsMouse ? .09 : 0)

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
                                color: root.panelFg
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.bodySmall
                                font.bold: true
                              }
                              Text {
                                textFormat: Text.PlainText
                                id: itemTime
                                anchors.baseline: itemSummary.baseline
                                text: root.ago(item.modelData.timestamp)
                                color: root.panelFg
                                opacity: .5
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.caption
                              }
                            }
                            Text {
                              width: parent.width
                              visible: text.length > 0
                              text: root.plainBody(item.modelData.body, true)
                              textFormat: Text.PlainText
                              wrapMode: Text.Wrap
                              maximumLineCount: 3
                              elide: Text.ElideRight
                              color: root.panelFg
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
          color: root.panelFg
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
                    color: root.panelFg
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
                  color: Qt.rgba(root.panelFg.r, root.panelFg.g, root.panelFg.b, .07)
                  Row {
                    id: modeRow
                    anchors.centerIn: parent
                    Repeater {
                      // (notify-send's pop-ups aren't kept by Omarchy, so Quiet would just hide them: Show or Off)
                      model: appRow.modelData === "notify-send" ? [["show", "Show"], ["off", "Off"]] : [["show", "Show"], ["quiet", "Quiet"], ["off", "Off"]]
                      Rectangle {
                        id: modeChip
                        required property var modelData
                        readonly property bool active: appRow.mode === modelData[0]
                        width: modeLabel.implicitWidth + Style.space(18)
                        height: Style.space(22)
                        radius: modes.radius
                        color: active ? Commons.Color.accent : (modeMouse.containsMouse ? Qt.rgba(root.panelFg.r, root.panelFg.g, root.panelFg.b, .1) : "transparent")
                        Text {
                          textFormat: Text.PlainText
                          id: modeLabel
                          anchors.centerIn: parent
                          text: modeChip.modelData[1]
                          color: modeChip.active ? Commons.Color.background : root.panelFg
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
          color: Qt.rgba(root.panelFg.r, root.panelFg.g, root.panelFg.b, .12)
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
              color: root.panelFg
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
            Text {
              textFormat: Text.PlainText
              width: parent.width
              wrapMode: Text.Wrap
              text: root.dnd
                ? "On: pop-ups are hidden (except critical battery alerts); notifications still collect here"
                : "Off: notifications pop up, then collect here"
              color: root.panelFg
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
      color: ibMouse.containsMouse ? Qt.rgba(root.panelFg.r, root.panelFg.g, root.panelFg.b, .16) : "transparent"
    }
    Text {
      textFormat: Text.PlainText
      anchors.centerIn: parent
      text: ib.glyph
      color: root.panelFg
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
    color: linkMouse.containsMouse ? Commons.Color.accent : root.panelFg
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
      color: root.panelFg
      opacity: .7
      font.family: root.fontFamily
      font.pixelSize: Style.space(16)
    }
  }
}
