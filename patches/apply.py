#!/usr/bin/env python3
"""Patch a copy of an Omarchy plugin for Overtake Mode.

  apply.py <workspaces|bluetooth|audio|notifications|battery> <plugin-dir>

Each patch is one or more exact replacements. If Omarchy has changed any code
one expects, nothing is written and it exits 3, so the installer can fall back
to Omarchy's own plugin instead of shipping a broken one.
"""
import sys, os

# Overtake Mode's UserIcons.qml, byte for byte (tests/t-qml-logic.js checks that),
# written into the notifications copy so its cards draw icons the same way.
USER_ICONS_QML = r'''import QtQuick
import Quickshell
import Quickshell.Io
// An icon by name. Qt decodes the file a name resolves to in the shell every plugin
// shares, and the icons in your own folders aren't always yours: Omarchy's web-app
// installer saves a site's icon there unmodified. So a name from your folders is
// drawn only from a stripped copy a limited child made (`overtake icon-copies`), or
// not at all, and a name goes to Qt's lookup only once a scan has looked for it in
// your folders and found nothing. Until then it draws nothing. A path is never looked
// up: Qt opens it on the main thread, and a named pipe would hang the shell for good.
Scope {
  id: root
  readonly property string dir: (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache") + "/overtake/user-icons"
  property var copies: null                   // name -> its copy's file, or "" for none; null until a list has been read
  property var checked: Object.create(null)   // names a finished scan looked for and didn't find in your folders
  property int checkedCount: 0
  property var asked: Object.create(null)     // names for the next scan
  property var asking: Object.create(null)    // names the running scan will answer
  property var answering: Object.create(null) // names the list about to be read answers

  function safe(name) { return /^[A-Za-z0-9_][A-Za-z0-9_.+-]{0,127}$/.test(String(name || "")) }
  function source(name) {
    if (!safe(name) || !copies) return ""
    if (name in copies) return copies[name] ? "file://" + dir + "/" + copies[name] : ""
    if (name in checked) return Quickshell.iconPath(name, true)
    if (!(name in asked || name in asking || name in answering)) { asked[name] = true; later.restart() }
    return ""
  }
  // One scan at a time, and not more often than this: a sender can name icons faster.
  Timer { id: later; interval: 3000; onTriggered: root.rescan() }
  // A scan that failed (its lock busy for a minute, a full disk) answered nothing:
  // its names wait for another, and draw nothing meanwhile.
  Timer { id: retry; interval: 30000; onTriggered: root.rescan() }
  function rescan() {
    if (scan.running) { later.restart(); return }
    asking = asked
    asked = Object.create(null)
    scan.running = true
  }

  // The list is read as it is, from this start or an earlier one: a name in it is
  // drawn from its copy or not at all, and a name not in it waits for a scan.
  FileView {
    id: list
    path: root.dir + "/index"
    printErrors: false
    onLoaded: {
      var next = Object.create(null)
      String(text()).split("\n").forEach(function(line) {
        var at = line.indexOf("\t")
        if (at > 0) next[line.slice(0, at)] = line.slice(at + 1)
      })
      if (root.checkedCount > 4000) { root.checked = Object.create(null); root.checkedCount = 0 }   // (bounded: a sender can name icons without end)
      for (var name in root.answering) if (!(name in next)) { root.checked[name] = true; root.checkedCount++ }
      root.answering = Object.create(null)
      root.copies = next   // (and what drew nothing looks again)
    }
  }
  Process {
    id: scan
    command: ["overtake", "icon-copies"]
    running: true
    onExited: function(code) {
      if (code === 0) {
        for (var name in root.asking) root.answering[name] = true
        root.asking = Object.create(null)
        list.reload()
      } else {
        for (var name in root.asking) root.asked[name] = true
        root.asking = Object.create(null)
        retry.restart()
      }
    }
  }
}
'''

PATCHES = {
    "workspaces": [("Workspaces.qml",
'''  function workspaceIds() {
    var base = root.block * root.slots
    var ids = [base + 1, base + 2, base + 3, base + 4, base + 5]
    var guests = []
    var values = Hyprland.workspaces.values

    for (var i = 0; i < values.length; i++) {
      var id = values[i].id
      if (id <= 0) continue
      if (root.blockOf(id) === root.block) {
        if (ids.indexOf(id) === -1) ids.push(id)
      } else if (values[i].monitor && values[i].monitor.name === root.monitorName) {
        guests.push(id)
      }
    }

    ids.sort(function(left, right) { return left - right })
    guests.sort(function(left, right) { return left - right })
    return ids.concat(guests)
  }''',
'''  // Overtake Mode: this monitor's own workspaces run 1 through the highest in
  // use (at least 5), with no gaps. Omarchy's own list skips empty ones past
  // 5, so 8 could show without 6 and 7, which reads as missing workspaces.
  // Visiting workspaces (an unplugged monitor's) still follow, as in Omarchy's.
  function workspaceIds() {
    var base = root.block * root.slots
    var highest = 5
    var guests = []
    var values = Hyprland.workspaces.values

    for (var i = 0; i < values.length; i++) {
      var id = values[i].id
      if (id <= 0) continue
      if (root.blockOf(id) === root.block) {
        if (id - base > highest) highest = id - base
      } else if (values[i].monitor && values[i].monitor.name === root.monitorName) {
        guests.push(id)
      }
    }

    var ids = []
    for (var n = 1; n <= highest; n++) ids.push(base + n)
    guests.sort(function(left, right) { return left - right })
    return ids.concat(guests)
  }'''),
      # Overtake Mode: a click on the layout mark doesn't change the layout here.
      # Omarchy's floating one brings title bars and a Dock that don't mix with
      # Overtake's, and it would stay after switching back.
      ("Workspaces.qml",
'''  function cycleLayout() {
    if (!root.bar) return''',
'''  function cycleLayout() {
    return   // Overtake Mode
    if (!root.bar) return''')],
    "bluetooth": ("Panel.qml",
'''      if (b === Qt.RightButton) root.toggleBluetooth()
      else root.toggle()''',
'''      // Overtake Mode: right-click opens the panel like left-click. Omarchy's
      // right-click turns Bluetooth off, which drops Bluetooth keyboards and mice.
      root.toggle()'''),
    "audio": ("Panel.qml",
'''      if (b === Qt.RightButton) root.toggleAllMuted()
      else root.toggle()''',
'''      // Overtake Mode: right-click opens the panel like left-click (Omarchy's
      // right-click mutes everything).
      root.toggle()'''),
    # Omarchy 4.5's notifications (Service.qml, Toast.qml and their .js) already
    # has a close mark on a hovered card, keeps 100 closed notifications for a
    # day in history.json and lets right-click dismiss. What's left for
    # Overtake Mode, only while it's on: critical toasts leave after 15 s for
    # the notification center (bell) instead of never, normal ones get 10 s,
    # each app's Show / Quiet / Off from the center, a critical battery alert
    # through Do Not Disturb, and the center's remove and Clear all (history is
    # this service's own file, rewritten whole from memory, so only it can take
    # an entry out).
    "notifications": [
      # A copied verification code goes to wl-copy on stdin, never as an
      # argument: wl-copy's clipboard server keeps its arguments in its
      # command line, readable by other accounts, while it holds the code.
      ("Service.qml",
'''  Process { id: clipProc; running: false }''',
'''  Process { id: clipProc; running: false }

  // Overtake Mode: a copied code goes to wl-copy on stdin, never as an
  // argument (wl-copy's clipboard server keeps its arguments in its command
  // line, readable by other accounts, while it holds the clipboard).
  Process {
    id: overtakeCodeClip
    property string value: ""
    property string forKey: ""   // the card it came from, kept if the copy fails
    function send(v) {
      running = false
      value = v
      stdinEnabled = true
      running = true
    }
    function failed() {
      codeTaken.keys = codeTaken.keys.filter(function(k) { return k !== forKey })
      service.showPlaceholder("Couldn't copy the code.")
    }
    command: ["wl-copy", "--sensitive"]
    onStarted: { write(value); value = ""; stdinEnabled = false }
    onExited: function(code) { if (code !== 0) failed() }
    // (couldn't start at all: no exit comes, and the value was never taken)
    onRunningChanged: if (!running && value !== "") { value = ""; failed() }
  }
  // Overtake Mode: which icons a card may draw by name, and from where: see UserIcons.qml.
  readonly property UserIcons overtakeIcons: UserIcons {}
  // The sender's window, brought forward. Its name is the sender's to choose, so
  // it goes on stdin rather than in a command line, and is matched as plain text.
  Process {
    id: overtakeFocusApp
    property string value: ""
    function send(v) {
      running = false
      value = v.replace(/[\\r\\n]+/g, " ")
      stdinEnabled = true
      running = true
    }
    command: ["overtake", "notification-open"]
    onStarted: { write(value + "\\n"); value = ""; stdinEnabled = false }
  }
  // Overtake Mode: a link in a notification's text can carry a reset or sign-in
  // token, and whatever opens it keeps it in its command line, readable by
  // other accounts. So a click puts the full link on the clipboard, over stdin
  // and kept out of clipboard history, and opens only https://<host>/. An email
  // address is copied and nothing is opened. The card says what happened.
  Process {
    id: overtakeLinkClip
    property string value: ""
    property string done: ""
    property string failed: ""
    property var waiting: null   // a click while a copy is still running
    function send(v, sayDone, sayFailed) {
      if (running) { waiting = [v, sayDone, sayFailed]; return }
      value = v
      done = sayDone
      failed = sayFailed
      stdinEnabled = true
      running = true
    }
    command: ["wl-copy", "--sensitive"]
    onStarted: { write(value); value = ""; stdinEnabled = false }
    onExited: function(code) { service.showPlaceholder(code === 0 ? done : failed) }
    onRunningChanged: {
      if (running) return
      // (couldn't start at all: no exit comes, and the value was never taken)
      if (value !== "") { value = ""; service.showPlaceholder(failed) }
      if (waiting) { var next = waiting; waiting = null; send(next[0], next[1], next[2]) }
    }
  }
  function overtakeOpenLink(raw) {
    // (the text's own link arrives with its & still written &amp;: measured)
    var safe = Security.safeExternalUrl(String(raw || "").replace(/&amp;/g, "&"))
    if (!safe) return
    var host = Security.hostOf(safe)
    if (!host) {   // mailto: only the address, nothing to open
      overtakeLinkClip.send(safe.replace(/^mailto:/i, ""), "Email address copied.", "Couldn't copy the email address.")
      return
    }
    overtakeLinkClip.send(safe, "Full link copied. Opening " + host + " only.", "Couldn't copy the full link. Opening " + host + " only.")
    Security.openExternalUrl("https://" + host + "/")
  }

  // Overtake Mode: a sender's raw picture (the image-data hint) is never drawn
  // (see Toast.qml), but Quickshell keeps its bytes for as long as the sender's
  // object lives: up to the bus's 64 MiB for each picture (measured), and nothing
  // tells this code its size. So only this many cards may hold on to one; past
  // that, a card keeps its text and icon, and the sender's object is let go,
  // which takes its buttons with it.
  readonly property int overtakeMaxPictures: 8
  // The same goes for text, buttons and hints, which can be read: a sender's
  // object past these sizes is let go at once. (The card's own copies are
  // already cut to Omarchy's limits and this file's, in Store.js.)
  function overtakeOversized(n) {
    if (String(n.body || "").length > 65536 || String(n.summary || "").length > 8192) return true
    if (String(n.appName || "").length > 4096 || String(n.appIcon || "").length > 4096 || String(n.desktopEntry || "").length > 4096) return true
    var actions = n.actions || []
    if (actions.length > 32) return true
    var total = 0
    for (var i = 0; i < actions.length; i++) total += String(actions[i].identifier || "").length + String(actions[i].text || "").length
    var hints = n.hints || {}, size = 0
    // (a picture has its own limit, below)
    Object.keys(hints).forEach(function(k) {
      if (k !== "image-data" && k !== "image_data" && k !== "icon_data") size += k.length + overtakeSizeOf(hints[k], 0)
    })
    return total > 65536 || size > 65536
  }
  // Everything held in a value, however deep (a hint can be a list or a map of
  // anything), stopping as soon as it's clearly too much.
  function overtakeSizeOf(v, depth) {
    if (typeof v === "string") return v.length
    if (!v || typeof v !== "object") return 8
    if (v.byteLength !== undefined) return v.byteLength
    if (depth > 8) return 1048576
    var keys = Object.keys(v), total = keys.length
    // A map, a struct, an object path or a signature reaches QML as an object with
    // nothing to read: its size can't be known, so it's taken as too big. (No Omarchy
    // or common app's hint is one.)
    if (v.length === 0) return 0   // (an empty list)
    if (!keys.length && !Array.isArray(v)) return 1048576
    for (var i = 0; i < keys.length && total <= 65536; i++) total += keys[i].length + overtakeSizeOf(v[keys[i]], depth + 1)
    return total
  }
  property var overtakePictures: ({})   // card key -> true
  function overtakePictureFits(key, row) {
    if (!/^image:\\/\\/qsimage\\//.test(String(row.image || ""))) {
      delete overtakePictures[key]
      return true
    }
    if (overtakePictures[key]) return true
    if (Object.keys(overtakePictures).length >= overtakeMaxPictures) return false
    overtakePictures[key] = true
    return true
  }'''),
      ("Service.qml",
'''    runClip(["wl-copy", "--sensitive", "--", value])''',
'''    overtakeCodeClip.send(value)   // Overtake Mode: on stdin, not in argv'''),
      # A link from the message text: see overtakeOpenLink.
      ("Service.qml",
'''      else if (String(row.link || "")) Security.openExternalUrl(String(row.link))
      else if (String(row.app || "")) Util.execArgv(["omarchy-hyprland-focus-app", String(row.app)])''',
'''      else if (String(row.link || "")) service.overtakeOpenLink(String(row.link))   // Overtake Mode
      else if (String(row.app || "")) overtakeFocusApp.send(String(row.app))   // Overtake Mode: on stdin, not in argv'''),
      ("Service.qml",
'''              onLinkOpened: service.stopKeyboard()''',
'''              onLinkOpened: function(url) { service.stopKeyboard(); service.overtakeOpenLink(url) }   // Overtake Mode'''),
      # Overtake Mode: no picture a sender supplies is ever decoded, and the card
      # shows the installed icon for the app instead. On this Qt, a small PNG with
      # compressed text chunks allocates gigabytes (a named file), and image-data
      # claiming more pixels than it sends segfaults Qt's image loader (both
      # measured), and this is the shared shell. An installed app's Icon= naming a file
      # goes the same way (a sender selects it by naming the app): names only here.
      ("Toast.qml",
'''        readonly property string sent: /^image:\\/\\/qsimage\\/[0-9]+\\/[0-9]+$/.test(String(card.row.image || ""))
                                       ? String(card.row.image) : Security.localImageUrl(card.row.image)''',
'''        readonly property string sent: ""   // Overtake Mode: no picture a sender supplies'''),
      ("Toast.qml",
'''          return value.charAt(0) === "/" ? Util.fileUrl(value) : value ? Quickshell.iconPath(value, true) : ""''',
'''          return card.overtakeIcon(value)   // Overtake Mode'''),
      ("Toast.qml",
'''firstOf(want.themed, function(name) { return Quickshell.iconPath(name, true) })''',
'''firstOf(want.themed, function(name) { return card.overtakeIcon(name) })'''),
      ("Toast.qml",
'''  property var row: ({})
''',
'''  property var row: ({})
  // Overtake Mode: icons by name, through the service's UserIcons (the same component
  // as plugins/overtake.taskbar/UserIcons.qml, written beside this file by the patch)
  function overtakeIcon(name) {
    return scene ? scene.overtakeIcons.source(name) : ""
  }
'''),
      ("Service.qml",
'''  function storeRecord(row, reason) {
    var now = Date.now() / 1000
    historyEntries = Store.addHistory(historyEntries, Store.closedEntry(row, reason, now), now)''',
'''  function storeRecord(row, reason) {
    var now = Date.now() / 1000
    // (Overtake Mode: one row to a key, whichever file came back first after a restart)
    historyEntries = Store.addHistory(historyEntries.filter(function(e) { return String(e.key) !== String(row.key) }), Store.closedEntry(row, reason, now), now)'''),
      ("Service.qml",
'''    var entry = Store.liveEntry(liveEntries, key)
    if (!entry) return
    storeDrop(key)
    storeRecord(entry, reason)''',
'''    var entry = Store.liveEntry(liveEntries, key)
    if (!entry) return
    overtakeUnfiled[String(key)] = entry   // Overtake Mode
    storeDrop(key)
    storeRecord(entry, reason)'''),
      ("Service.qml",
'''      liveFile.setText(Store.serialise(liveEntries))''',
'''      liveFile.setText(Store.serialise(overtakeLiveRows()))   // Overtake Mode'''),
      ("Toast.qml",
'''  signal linkOpened()''',
'''  signal linkOpened(string url)   // Overtake Mode: the service decides what opens'''),
      ("Toast.qml",
'''          onLinkActivated: function(url) { card.linkOpened(); Security.openExternalUrl(url) }''',
'''          onLinkActivated: function(url) { card.linkOpened(url) }   // Overtake Mode: full link to the clipboard, only the site opens'''),
      # Overtake Mode: the card's picture is no longer counted once it's gone.
      ("Service.qml",
'''    if (!liveKeys[key]) return
    delete liveKeys[key]''',
'''    if (!liveKeys[key]) return
    delete overtakePictures[key]   // Overtake Mode
    delete liveKeys[key]'''),
      ("Service.qml",
'''    copySecret(value)
    // A copied code finishes its card''',
'''    overtakeCodeClip.forKey = String(key)   // Overtake Mode
    copySecret(value)
    // A copied code finishes its card'''),
      # Overtake Mode: on text a sender chooses, this pattern takes quadratic time
      # in the shell every plugin shares (measured: over a second for 32 KB of "<",
      # for each notification, in stock too). So a body is cut to 8 KB, and "<" no
      # longer restarts the search.
      ("Store.js",
'''              body: Security.bounded(n.body, Security.MAX_BODY) }''',
'''              body: Security.bounded(n.body, 8192) }   // Overtake Mode: see apply.py'''),
      ("Store.js",
'''.replace(/<[^>]+>/g, " ")''',
'''.replace(/<[^<>]*>/g, " ")'''),
      # The minute-later check reads at most a code's length of the
      # clipboard (whatever was copied since could be any size).
      ("Service.qml",
'''    command: ["wl-paste", "--no-newline"]''',
'''    // Overtake Mode: only as much as a code's length, whatever was copied since
    command: ["sh", "-c", "wl-paste --no-newline 2>/dev/null | head -c 65"]'''),
      ("Service.qml",
'''  readonly property int lowDuration: 5000
  readonly property int normalDuration: 8000''',
'''  // Overtake Mode on? (its flag file). Overtake switches this copy on only
  // with Classic or Studio; the check keeps it behaving like Omarchy's own in
  // the moment around a switch.
  property bool overtakeOn: false
  FileView {   // "on" or "off", kept by `overtake` (watched, not polled)
    path: Quickshell.env("HOME") + "/.local/state/overtake/mode"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: { var v = text().trim(); if (v) service.overtakeOn = v === "on" }
    onLoadFailed: service.overtakeOn = false
  }
  // Overtake Mode: per-app settings from the notification center,
  // ~/.config/overtake/notifications.json: {"apps": {"<app>": "quiet" | "off"}}.
  property var overtakeAppModes: ({})
  FileView {
    path: Quickshell.env("HOME") + "/.config/overtake/notifications.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        var apps = (JSON.parse(text()) || {}).apps
        service.overtakeAppModes = apps && typeof apps === "object" && !Array.isArray(apps) ? apps : ({})
      } catch (e) { service.overtakeAppModes = ({}) }
    }
    onLoadFailed: service.overtakeAppModes = ({})
  }
  // Overtake Mode: what it does to this row ("" for nothing). "off" drops the
  // app's notifications unrecorded; "bypass" lets a critical battery alert
  // (BatteryAlerts, sent as "Battery") through Do Not Disturb; "quiet" files
  // the app's notifications in history without a card, like Do Not Disturb
  // for that app alone.
  function overtakeModeFor(row) {
    if (!overtakeOn) return ""
    var app = String(row.app || "")
    if (app === "omarchy-action") return ""
    var mode = Object.prototype.hasOwnProperty.call(overtakeAppModes, app) ? String(overtakeAppModes[app]) : ""
    if (mode === "off") return "off"
    if (app === "Battery" && Number(row.urgency) === NotificationUrgency.Critical) return "bypass"
    return mode === "quiet" ? "quiet" : ""
  }
  // Overtake Mode: why this row gets no card ("" when it gets one): Do Not
  // Disturb, then the app's setting. Still shown through Do Not Disturb, as in
  // Omarchy: a verification code, Omarchy's own toasts, and a bare notify-send
  // marked critical; and here a critical battery alert. A quiet app's card that
  // can't be kept (ephemeral) still shows, as there'd be nothing to file.
  function overtakeMuted(row) {
    var muted = Delivery.quietReason(row, doNotDisturb)
    var overtakeMode = service.overtakeModeFor(row)
    if (overtakeMode === "off") muted = "off"
    else if (overtakeMode === "bypass") muted = ""
    else if (overtakeMode === "quiet" && !muted && !Delivery.bypassesQuiet(row)
             && !String(row.code || "") && !Delivery.isEphemeral(row)) muted = "silenced"
    return muted
  }
  // Overtake Mode: a card coming back after a restart is held to the same rules
  // as a new one: past its day it's gone (a card stays on screen for seconds,
  // and this row hasn't been listed as history), and under Do Not Disturb or a
  // quiet app it goes to history instead of popping up. True if it stays off
  // screen.
  function overtakeRestoreHeldBack(row) {
    // (history got it just before a stop: it isn't a card again)
    if (historyEntries.some(function(e) { return String(e.key) === String(row.key) })) return true
    if (Number(row.ts) <= Date.now() / 1000 - Store.RETENTION_HOURS * 3600) return true
    var muted = overtakeMuted(row)
    if (!muted) return false
    if (muted !== "off" && !Delivery.isEphemeral(row)) storeRecord(row, muted)
    return true
  }

  readonly property int lowDuration: 5000
  readonly property int normalDuration: overtakeOn ? 10000 : 8000  // Overtake Mode: 10 s'''),
      ("Service.qml",
'''    if (urgency === NotificationUrgency.Critical) return 0''',
'''    if (urgency === NotificationUrgency.Critical) return service.overtakeOn ? 15000 : 0  // Overtake Mode: then it waits in the notification center'''),
      ("Service.qml",
'''    var muted = Delivery.quietReason(row, doNotDisturb)
    if (muted) {
      if (!Delivery.isEphemeral(row)) storeRecord(row, muted)''',
'''    // Overtake Mode: see overtakePictureFits
    if (service.overtakeOversized(notification) || !service.overtakePictureFits(key, row)) { row.image = ""; service.release(key) }
    var muted = service.overtakeMuted(row)   // Overtake Mode: Do Not Disturb, then the app's setting
    if (muted) {
      if (muted !== "off" && !Delivery.isEphemeral(row)) storeRecord(row, muted)'''),
      # A restored critical card (after a shell restart) would wait forever too.
      ("Service.qml",
'''      var row = Store.restored(rows[i])
      if (!row) continue''',
'''      var row = Store.restored(rows[i])
      if (!row) continue
      if (!replay && service.overtakeRestoreHeldBack(row)) continue  // Overtake Mode
      if (service.overtakeOn && row.urgency === NotificationUrgency.Critical) row.duration = 15000  // Overtake Mode'''),
      # Do Not Disturb has to be known before a card is restored, and the files
      # load in no fixed order. So live.json waits for quiet.json.
      ("Service.qml",
'''  function loadLive(text) {
    if (liveLoaded) return
    var stored = Store.parseLive(text)''',
'''  property var overtakeLiveWaiting: null   // Overtake Mode: live.json, read before quiet.json
  function loadLive(text) {
    if (liveLoaded) return
    if (!quietLoaded) { overtakeLiveWaiting = String(text); return }   // Overtake Mode
    var stored = Store.parseLive(text)'''),
      ("Service.qml",
'''    quietLoaded = true
    if (unsaved.quiet) saveSoon("quiet")''',
'''    quietLoaded = true
    if (unsaved.quiet) saveSoon("quiet")
    if (overtakeLiveWaiting !== null) { var waiting = overtakeLiveWaiting; overtakeLiveWaiting = null; loadLive(waiting) }   // Overtake Mode'''),
      # Do Not Disturb is read back too: a write that fails at commit (disk
      # full) is still reported as saved. It's written again until the file
      # says the same; the center tells the user if it can't be saved.
      ("Service.qml",
'''    id: quietFile
    path: service.storeReady ? service.stateDir + "/quiet.json" : ""
    atomicWrites: true
    printErrors: false
    onLoaded: service.loadQuiet(text())
    onLoadFailed: service.loadQuiet("")
  }''',
'''    id: quietFile
    path: service.storeReady ? service.stateDir + "/quiet.json" : ""
    atomicWrites: true
    printErrors: false
    onSaved: overtakeQuietCheck.restart()       // Overtake Mode
    onSaveFailed: overtakeQuietCheck.restart()
    onLoaded: { service.overtakeCheckQuiet(text()); service.loadQuiet(text()) }
    onLoadFailed: { service.overtakeCheckQuiet(""); service.loadQuiet("") }
  }
  Timer {
    id: overtakeQuietCheck
    interval: 1000
    onTriggered: service.overtakeWhenPrepared(service.overtakeReadQuietBack)
  }
  Timer {
    id: overtakeQuietRetry
    interval: 5000
    onTriggered: service.saveSoon("quiet")
  }
  function overtakeReadQuietBack() { quietFile.reload() }
  function overtakeCheckQuiet(text) {
    if (!quietLoaded) return
    var read = Store.parseQuiet(text)
    if ((read ? read.dnd : false) === doNotDisturb) overtakeQuietRetry.stop()
    else overtakeQuietRetry.restart()
  }'''),
      # live.json is read back after every write as well, so a card that closed
      # while the disk was full is taken out of the file then, and a removed
      # row can't come back through it after a restart.
      ("Service.qml",
'''    id: liveFile
    path: service.storeReady ? service.stateDir + "/live.json" : ""
    atomicWrites: true
    printErrors: false
    onLoaded: service.loadLive(text())''',
'''    id: liveFile
    path: service.storeReady ? service.stateDir + "/live.json" : ""
    atomicWrites: true
    printErrors: false
    onSaved: overtakeLiveReadBack.restart()       // Overtake Mode
    onSaveFailed: overtakeLiveReadBack.restart()
    onLoaded: service.loadLive(text())'''),
      # Omarchy prepares the folder once, at startup. If it's deleted while the
      # shell runs, the next write would recreate it with default permissions
      # (FileView makes missing folders itself): 0755, with a 0644 file in it.
      # So every write now waits for the same preparation to finish first.
      ("Service.qml",
'''  function flushStore() {
    if (unsaved.live && liveLoaded) {''',
'''  function flushStore() {
    // Overtake Mode: nothing is written until the folder is known to be private
    if ((unsaved.live && liveLoaded) || (unsaved.history && historyLoaded) || (unsaved.quiet && quietLoaded))
      overtakeWhenPrepared(overtakeWriteStore)
  }
  function overtakeWriteStore() {
    if (unsaved.live && liveLoaded) {'''),
      ("Service.qml",
'''    command: ["bash", "-c",
      "umask 077\\n" +
      "dir=$1\\n" +
      "mkdir -p -- \\"$dir\\" && chmod 700 -- \\"$dir\\" || exit 1\\n" +
      "for name in live.json history.json quiet.json; do\\n" +
      "  file=$dir/$name\\n" +
      "  if [[ -L $file ]]; then rm -f -- \\"$file\\"; fi\\n" +
      "  if [[ -f $file ]]; then chmod 600 -- \\"$file\\"; elif [[ ! -e $file ]]; then : >\\"$file\\"; fi\\n" +
      "done\\n",
      "omarchy-notifications-state", service.stateDir]
    onExited: function(code) { service.storeReady = code === 0 }
  }

  Component.onCompleted: storePrepare.running = true
  // A reload or a clean exit inside the save delay still writes.
  Component.onDestruction: flushStore()''',
'''    command: ["bash", "-c", service.overtakePrepareScript, "omarchy-notifications-state", service.stateDir]
    onExited: function(code) { service.overtakePrepareExited(code) }   // Overtake Mode
  }
  // Overtake Mode: Omarchy's script, except that a file it can't create is a
  // failure (a write after that would create it with default permissions).
  readonly property string overtakePrepareScript:
      "umask 077\\n" +
      "dir=$1\\n" +
      "mkdir -p -- \\"$dir\\" && chmod 700 -- \\"$dir\\" || exit 1\\n" +
      "for name in live.json history.json quiet.json; do\\n" +
      "  file=$dir/$name\\n" +
      "  if [[ -L $file ]]; then rm -f -- \\"$file\\"; fi\\n" +
      "  if [[ -f $file ]]; then chmod 600 -- \\"$file\\" || exit 1; elif [[ ! -e $file ]]; then : >\\"$file\\" || exit 1; fi\\n" +
      "done\\n"

  // Overtake Mode: the folder made private (again) before each write and each
  // read-back. A write held here runs when the script has finished, and is
  // tried again every 5 s while the script fails. It runs once more for
  // whatever asked while it was already running, as the folder may have gone
  // since it looked.
  property var overtakePrepareNext: []
  property var overtakePrepareNow: []
  property bool overtakePrepareFailed: false
  function overtakeWhenPrepared(run) {
    if (overtakePrepareNext.indexOf(run) === -1) overtakePrepareNext.push(run)
    overtakeStartPrepare()
  }
  function overtakeStartPrepare() {
    if (storePrepare.running || overtakePrepareRetry.running) return
    overtakePrepareNow = overtakePrepareNext
    overtakePrepareNext = []
    storePrepare.running = true
  }
  function overtakePrepareExited(code) {
    var ran = overtakePrepareNow
    overtakePrepareNow = []
    overtakePrepareFailed = code !== 0
    if (code !== 0) {
      overtakePrepareNext = ran.concat(overtakePrepareNext.filter(function(run) { return ran.indexOf(run) === -1 }))
      if (overtakePrepareNext.length) overtakePrepareRetry.restart()
      return
    }
    storeReady = true
    ran.forEach(function(run) { run() })
    if (overtakePrepareNext.length) overtakeStartPrepare()
  }
  Timer {
    id: overtakePrepareRetry
    interval: 5000
    onTriggered: service.overtakeStartPrepare()
  }
  // What the center hears when history hasn't loaded: still starting, or the
  // folder can't be prepared (a read-only home), which waiting won't fix. It's
  // tried again now, in case that has changed.
  function overtakeNotLoadedReply() {
    if (!overtakePrepareFailed) return "notready"
    overtakeStartPrepare()
    return "unwritable"
  }
  // No process can be waited for at exit, so a write still due goes now, and a
  // detached copy of the script puts the permissions right just after it, in
  // case the folder was deleted a moment ago.
  function overtakeFlushAtExit() {
    if (!((unsaved.live && liveLoaded) || (unsaved.history && historyLoaded) || (unsaved.quiet && quietLoaded))) return
    Quickshell.execDetached(["bash", "-c", "sleep 0.3\\n" + overtakePrepareScript, "omarchy-notifications-state", stateDir])
    overtakeWriteStore()
  }

  Component.onCompleted: storePrepare.running = true
  // A reload or a clean exit inside the save delay still writes.
  Component.onDestruction: overtakeFlushAtExit()   // Overtake Mode'''),
      ("Service.qml",
'''    function count(): string { return String(toasts.count) }''',
'''    function count(): string { return String(toasts.count) }

    // Overtake Mode: the notification center's remove and Clear all (history
    // keys, space separated). Written at once, not after the usual quarter
    // second, so a shutdown right after can't lose it.
    function forget(keys: string): string {
      var drop = String(keys || "").split(" ").filter(function(k) { return k !== "" })
      if (!service.historyLoaded) return service.overtakeNotLoadedReply()   // (not read yet: it would come back)
      if (!drop.length) return "none"
      var kept = service.historyEntries.filter(function(e) { return drop.indexOf(String(e.key)) === -1 })
      if (kept.length === service.historyEntries.length) return "none"
      service.historyEntries = kept
      service.overtakeInPlace.reload()   // onLoaded takes the rows out of what's on disk now
      service.overtakeLiveInPlace.reload()   // (a row that closed while the disk was full may still be in live.json)
      service.saveSoon("history")
      service.flushStore()
      return "ok"
    }

    // Overtake Mode: Clear all is everything up to now, whether or not the
    // center has shown it yet: a copy Do Not Disturb or a quiet app filed a
    // moment ago (or while a full disk kept it out of the file), and every
    // card still on screen or on its way out, which would otherwise file
    // itself into history as it closes. (Those stay on screen until they
    // time out, but leave nothing behind.)
    function forgetAll(): string {
      // (both read first: a card restored after this would come back)
      if (!service.historyLoaded || !service.liveLoaded) return service.overtakeNotLoadedReply()
      service.liveEntries.map(function(e) { return String(e.key) })
        .forEach(function(key) { service.storeDrop(key) })
      service.overtakeLiveInPlace.reload()
      if (!service.historyEntries.length) return "none"
      return forget(service.historyEntries.map(function(e) { return String(e.key) }).join(" "))
    }
'''),
      # History past its day leaves on time (every minute), not only when the
      # next notification arrives; and every history write is checked
      # against the file and written again until the file matches (Quickshell
      # reports a write that fails at commit as saved, and skips writing the
      # same text twice; a reload inside its save signals does nothing).
      ("Service.qml",
'''  // Started, never restarted, so a flood still writes every quarter second.
  Timer {
    id: saveTimer
    interval: 250
    onTriggered: service.flushStore()
  }''',
'''  // Started, never restarted, so a flood still writes every quarter second.
  Timer {
    id: saveTimer
    interval: 250
    onTriggered: service.flushStore()
  }

  // Overtake Mode: history past its day leaves on time (Omarchy prunes it
  // only when a notification arrives or the shell starts).
  Timer {
    id: overtakeExpiry
    interval: 60000
    repeat: true
    running: service.historyLoaded
    onTriggered: service.currentHistory()
  }
  // Overtake Mode: a second after each history write the file is read back
  // (from this timer: a reload inside FileView's save signals does nothing),
  // because a write that fails at commit (disk full) is still reported as
  // saved. If the file doesn't match what's in memory, memory is written
  // again 5 s later, and checked again, until it does.
  Timer {
    id: overtakeVerify
    interval: 1000
    onTriggered: service.overtakeWhenPrepared(service.overtakeReadHistoryBack)
  }
  function overtakeReadHistoryBack() { historyFile.reload() }
  function overtakeCheckFile(text) {
    if (!historyLoaded) return
    overtakeInPlaceFile.reload()
    var mine = Store.serialise(historyEntries), disk = String(text)
    // (the slow compare only for a text that has an unpaired half)
    var lone = /[\\ud800-\\udbff](?![\\udc00-\\udfff])|(?:^|[^\\ud800-\\udbff])[\\udc00-\\udfff]/
    if (mine === disk || ((lone.test(mine) || lone.test(disk)) && overtakeComparable(mine) === overtakeComparable(disk))) overtakeSaveRetry.stop()
    else overtakeSaveRetry.restart()
  }
  // Without unpaired UTF-16 halves (a body cut mid-emoji keeps one; the
  // write drops it), or such a history would never match and be rewritten
  // every few seconds.
  function overtakeComparable(s) {
    return s.replace(/[\\ud800-\\udbff][\\udc00-\\udfff]|[\\ud800-\\udfff]/g, function(m) { return m.length === 2 ? m : "" })   // (a pair stays, a lone half goes)
  }
  Timer {
    id: overtakeSaveRetry
    interval: 5000
    onTriggered: service.saveSoon("history")
  }
  // A row taken out (remove, Clear all, past its day) is also taken out of
  // the file in place, right after the removal and at each read-back: on a
  // full disk the usual write (a new file renamed over it) gets no space, so
  // a restart would read the row again. reload() is asynchronous, so this
  // happens when the file has been read: the file as it stands less the rows
  // no longer in memory.
  //
  // FileView can't do this write safely: without atomicWrites it opens the file
  // truncated, so if the disk then refuses the write, the other rows are gone
  // too. This small script overwrites without truncating instead. See its
  // comments for why a refused write leaves every row in place.
  readonly property string overtakeInPlaceScript:
      "LC_ALL=C\\n" +              // (lengths below are in bytes)
      "file=$1\\n" +
      // The text comes on stdin, never as an argument.
      "new=$(cat; printf x); new=${new%x}\\n" +
      // Never creates the file, or follows a link.
      "[[ -f $file && ! -L $file ]] || exit 3\\n" +
      "old=$(cat -- \\"$file\\"; printf x) || exit 1; old=${old%x}\\n" +
      "[[ $(stat -c %s -- \\"$file\\") == \\"${#old}\\" ]] || exit 3\\n" +
      // Only ever shorter, so it can reuse the file's own space.
      "(( ${#new} <= ${#old} )) || exit 3\\n" +
      // Spaces up to the old length: JSON allows them, so the file is complete
      // JSON whether or not the cut at the end works.
      "printf -v pad '%*s' \\"$(( ${#old} - ${#new} ))\\" ''\\n" +
      "write() { dd of=\\"$file\\" oflag=nofollow conv=notrunc,nocreat bs=1M iflag=fullblock status=none 2>/dev/null; }\\n" +
      // A write cut short leaves new text in front of old: the old text goes
      // back over it, in the space that write already got.
      "if ! printf '%s%s' \\"$new\\" \\"$pad\\" | write; then printf '%s' \\"$old\\" | write; exit 1; fi\\n" +
      "truncate -s \\"${#new}\\" -- \\"$file\\" 2>/dev/null\\n" +
      "exit 0\\n"
  component OvertakeInPlaceWrite: Process {
    property string script: ""
    property string file: ""
    property string value: ""
    property string next: ""
    property bool queued: false
    function send(text) {
      if (running) { next = text; queued = true; return }
      value = text
      stdinEnabled = true
      running = true
    }
    command: ["bash", "-c", script, "overtake-in-place", file]
    onStarted: { write(value); value = ""; stdinEnabled = false }
    onExited: if (queued) { queued = false; send(next); next = "" }
  }
  OvertakeInPlaceWrite { id: overtakeHistoryWrite; script: service.overtakeInPlaceScript; file: historyFile.path }
  OvertakeInPlaceWrite { id: overtakeLiveWrite; script: service.overtakeInPlaceScript; file: liveFile.path }
  property alias overtakeInPlace: overtakeInPlaceFile
  FileView {   // (only ever read)
    id: overtakeInPlaceFile
    path: historyFile.path
    printErrors: false
    onLoaded: if (service.historyLoaded) service.overtakeRemoveInPlace(text())
  }
  // The same for the cards on screen (live.json), after each write and at each
  // removal: otherwise a card comes back after a restart on a full disk and
  // files itself as it closes.
  // Rows closed, with what they looked like on screen, until history's file has
  // them: until then live.json holds them too, or a disk with room for that small
  // file and not for history would lose them.
  property var overtakeUnfiled: Object.create(null)
  function overtakeLiveRows() {
    var rows = liveEntries.slice(), inHistory = Object.create(null), live = Object.create(null)
    historyEntries.forEach(function(e) { inHistory[String(e.key)] = true })
    liveEntries.forEach(function(e) { live[String(e.key)] = true })
    Object.keys(overtakeUnfiled).forEach(function(k) {
      if (inHistory[k] === true && live[k] !== true) rows.push(overtakeUnfiled[k])
      else if (inHistory[k] !== true) delete overtakeUnfiled[k]   // (removed: gone at once)
    })
    return rows
  }
  property alias overtakeLiveInPlace: overtakeLiveInPlaceFile
  FileView {   // (only ever read)
    id: overtakeLiveInPlaceFile
    path: liveFile.path
    printErrors: false
    onLoaded: {
      if (!service.liveLoaded) return
      var raw = String(text()), rows, keep = Object.create(null)
      try { rows = JSON.parse(raw.trim() || "[]") } catch (e) { return }
      if (!Array.isArray(rows)) return
      service.liveEntries.forEach(function(e) { keep[String(e.key)] = true })
      // Closed, but history's file doesn't have it yet. (A row you removed or
      // cleared isn't in history at all, and goes at once.)
      service.overtakeLiveRows().forEach(function(e) { keep[String(e.key)] = true })
      var left = rows.filter(function(e) { return !!e && typeof e === "object" && keep[String(e.key)] === true })
      // A row no longer in memory: out of the file, then read again a second
      // later (about every 6 s if it's still there).
      if (left.length !== rows.length) {
        overtakeLiveWrite.send(service.overtakeComparable(JSON.stringify(left) + "\\n"))
        if (overtakeLiveReadBack.removals++ === 0) overtakeLiveReadBack.restart()
        else overtakeLiveRetry.restart()
        return
      }
      overtakeLiveReadBack.removals = 0
      // A card that arrived as this was read, or whose write didn't land, can
      // be missing from the file: written again from memory (reloaded first:
      // FileView skips the text it last wrote), and then about every 6 s until
      // the file has it.
      var have = Object.create(null)
      left.forEach(function(e) { have[String(e.key)] = true })
      var missing = service.liveEntries.some(function(e) { return have[String(e.key)] !== true })
      if (missing && overtakeLiveReadBack.tries++ === 0) overtakeLiveRetry.triggered()
      else if (missing) overtakeLiveRetry.restart()
      else overtakeLiveReadBack.tries = 0
    }
  }
  Timer {
    id: overtakeLiveReadBack
    property int tries: 0
    property int removals: 0
    interval: 1000
    onTriggered: service.overtakeWhenPrepared(service.overtakeReadLiveBack)
  }
  Timer {
    id: overtakeLiveRetry
    interval: 5000
    onTriggered: { liveFile.reload(); service.saveSoon("live"); overtakeLiveReadBack.restart() }
  }
  function overtakeReadLiveBack() { overtakeLiveInPlaceFile.reload() }
  function overtakeRemoveInPlace(diskText) {
    var rows, keep = Object.create(null)   // (a key may be "__proto__")
    try { rows = JSON.parse(String(diskText)) } catch (e) { return }
    if (!Array.isArray(rows)) return
    // What history's file really holds: a closed card leaves live.json only once
    // it's in here.
    var landed = false
    rows.forEach(function(e) {
      if (e && typeof e === "object" && overtakeUnfiled[String(e.key)]) { delete overtakeUnfiled[String(e.key)]; landed = true }
    })
    if (landed) overtakeLiveInPlaceFile.reload()
    historyEntries.forEach(function(e) { keep[String(e.key)] = true })
    var left = rows.filter(function(e) { return !!e && typeof e === "object" && keep[String(e.key)] === true })
    if (left.length !== rows.length) overtakeHistoryWrite.send(overtakeComparable(JSON.stringify(left) + "\\n"))
  }'''),
      ("Service.qml",
'''    id: historyFile
    path: service.storeReady ? service.stateDir + "/history.json" : ""
    atomicWrites: true
    printErrors: false
    onLoaded: service.loadHistory(text())''',
'''    id: historyFile
    path: service.storeReady ? service.stateDir + "/history.json" : ""
    atomicWrites: true
    printErrors: false
    // Overtake Mode: each write checked against the file
    onSaved: overtakeVerify.restart()
    onSaveFailed: overtakeVerify.restart()
    onLoaded: { service.overtakeCheckFile(text()); service.loadHistory(text()) }'''),
      ("Service.qml",
'''    onLoadFailed: service.loadHistory("")
  }

  FileView {
    id: quietFile''',
'''    onLoadFailed: { service.overtakeCheckFile(""); service.loadHistory("") }
  }

  FileView {
    id: quietFile'''),
      ("UserIcons.qml", None, USER_ICONS_QML)],
    # Overtake Mode's battery alerts (per device, levels you choose) replace
    # Omarchy's single 10% laptop warning; power profiles still switch here.
    "battery": ("Service.qml",
'''  function checkBattery() {
    var state''',
'''  // Overtake Mode on? (its flag file). Overtake switches this copy on only
  // with Classic or Studio; while the flag is off it warns as Omarchy's own.
  property bool overtakeOn: false
  FileView {   // "on" or "off", kept by `overtake` (watched, not polled)
    path: Quickshell.env("HOME") + "/.local/state/overtake/mode"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: { var v = text().trim(); if (v) root.overtakeOn = v === "on" }
    onLoadFailed: root.overtakeOn = false
  }

  function checkBattery() {
    if (root.overtakeOn) return  // Overtake Mode: BatteryAlerts in overtake.taskbar sends battery warnings
    var state'''),
}

name, plugin_dir = sys.argv[1], sys.argv[2]
patches = PATCHES[name]
if isinstance(patches, tuple):
    patches = [patches]
# Check every replacement before writing any.
texts = {}
for filename, old, new in patches:
    path = os.path.join(plugin_dir, filename)
    if old is None:   # a file the patch adds, which Omarchy's plugin mustn't have
        if os.path.lexists(path):
            sys.exit(3)
        texts[path] = new
        continue
    text = texts.get(path) or open(path).read()
    if text.count(old) != 1:   # missing, or no longer one place to change
        sys.exit(3)   # (3: the patch doesn't fit; any other failure is something else)
    texts[path] = text.replace(old, new, 1)
for path, text in texts.items():
    # (`with`: a write that fails at close is an error here, not a cut-off copy
    # and exit 0, as Python only warns when a file left open fails to close)
    with open(path, "w") as out:
        out.write(text)
