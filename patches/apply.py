#!/usr/bin/env python3
"""Patch a copy of an Omarchy plugin for Overtake Mode.

  apply.py <workspaces|bluetooth|audio|notifications|battery> <plugin-dir>

Each patch is one or more exact replacements. If Omarchy has changed any code
one expects, nothing is written and it exits 3, so the installer can fall back
to Omarchy's own plugin instead of shipping a broken one.
"""
import sys, os

PATCHES = {
    "workspaces": ("Workspaces.qml",
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
    function send(v) {
      running = false
      value = v
      stdinEnabled = true
      running = true
    }
    command: ["wl-copy", "--sensitive"]
    onStarted: { write(value); value = ""; stdinEnabled = false }
  }'''),
      ("Service.qml",
'''    runClip(["wl-copy", "--sensitive", "--", value])''',
'''    overtakeCodeClip.send(value)   // Overtake Mode: on stdin, not in argv'''),
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

  readonly property int lowDuration: 5000
  readonly property int normalDuration: overtakeOn ? 10000 : 8000  // Overtake Mode: 10 s'''),
      ("Service.qml",
'''    if (urgency === NotificationUrgency.Critical) return 0''',
'''    if (urgency === NotificationUrgency.Critical) return service.overtakeOn ? 15000 : 0  // Overtake Mode: then it waits in the notification center'''),
      ("Service.qml",
'''    var muted = Delivery.quietReason(row, doNotDisturb)
    if (muted) {
      if (!Delivery.isEphemeral(row)) storeRecord(row, muted)''',
'''    var muted = Delivery.quietReason(row, doNotDisturb)
    // Overtake Mode: the app's setting from the notification center, and a
    // critical battery alert past Do Not Disturb. A quiet app's card that
    // can't be kept (ephemeral) still shows, as there'd be nothing to file.
    var overtakeMode = service.overtakeModeFor(row)
    if (overtakeMode === "off") muted = "off"
    else if (overtakeMode === "bypass") muted = ""
    else if (overtakeMode === "quiet" && !muted && !Delivery.bypassesQuiet(row)
             && !String(row.code || "") && !Delivery.isEphemeral(row)) muted = "silenced"
    if (muted) {
      if (muted !== "off" && !Delivery.isEphemeral(row)) storeRecord(row, muted)'''),
      # A restored critical card (after a shell restart) would wait forever too.
      ("Service.qml",
'''      var row = Store.restored(rows[i])
      if (!row) continue''',
'''      var row = Store.restored(rows[i])
      if (!row) continue
      if (service.overtakeOn && row.urgency === NotificationUrgency.Critical) row.duration = 15000  // Overtake Mode'''),
      ("Service.qml",
'''    function count(): string { return String(toasts.count) }''',
'''    function count(): string { return String(toasts.count) }

    // Overtake Mode: the notification center's remove and Clear all (history
    // keys, space separated). Written at once, not after the usual quarter
    // second, so a shutdown right after can't lose it.
    function forget(keys: string): string {
      var drop = String(keys || "").split(" ").filter(function(k) { return k !== "" })
      if (!service.historyLoaded) return "notready"   // (not read yet: it would come back)
      if (!drop.length) return "none"
      var kept = service.historyEntries.filter(function(e) { return drop.indexOf(String(e.key)) === -1 })
      if (kept.length === service.historyEntries.length) return "none"
      service.historyEntries = kept
      service.overtakeInPlace.reload()   // onLoaded takes the rows out of what's on disk now
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
      if (!service.historyLoaded) return "notready"
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
    onTriggered: historyFile.reload()
  }
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
    var out = ""
    for (var i = 0; i < s.length; i++) {
      var c = s.charCodeAt(i)
      if (c >= 0xd800 && c <= 0xdbff && i + 1 < s.length && (s.charCodeAt(i + 1) & 0xfc00) === 0xdc00) { out += s.substr(i, 2); i++ }
      else if ((c & 0xf800) !== 0xd800) out += s[i]
    }
    return out
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
  // no longer in memory, never longer than what it overwrites, so it reuses
  // the file's own space; cut short, it is no JSON, which the loader reads as
  // no history, never as a removed row.
  property alias overtakeInPlace: overtakeInPlaceFile
  FileView {
    id: overtakeInPlaceFile
    path: historyFile.path
    atomicWrites: false
    printErrors: false
    onLoaded: if (service.historyLoaded) service.overtakeRemoveInPlace(text())
  }
    // The same for the cards on screen (live.json), at Clear all: otherwise one
  // comes back after a restart on a full disk and files itself as it closes.
  property alias overtakeLiveInPlace: overtakeLiveInPlaceFile
  FileView {
    id: overtakeLiveInPlaceFile
    path: liveFile.path
    atomicWrites: false
    printErrors: false
    onLoaded: {
      if (!service.liveLoaded) return
      var rows, keep = Object.create(null)
      try { rows = JSON.parse(String(text())) } catch (e) { return }
      if (!Array.isArray(rows)) return
      service.liveEntries.forEach(function(e) { keep[String(e.key)] = true })
      var left = rows.filter(function(e) { return !!e && typeof e === "object" && keep[String(e.key)] === true })
      if (left.length !== rows.length) setText(JSON.stringify(left) + "\\n")
    }
  }
  function overtakeRemoveInPlace(diskText) {
    var rows, keep = Object.create(null)   // (a key may be "__proto__")
    try { rows = JSON.parse(String(diskText)) } catch (e) { return }
    if (!Array.isArray(rows)) return
    historyEntries.forEach(function(e) { keep[String(e.key)] = true })
    var left = rows.filter(function(e) { return !!e && typeof e === "object" && keep[String(e.key)] === true })
    if (left.length !== rows.length) overtakeInPlaceFile.setText(JSON.stringify(left) + "\\n")
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
    ],
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
    text = texts.get(path) or open(path).read()
    if text.count(old) != 1:   # missing, or no longer one place to change
        sys.exit(3)   # (3: the patch doesn't fit; any other failure is something else)
    texts[path] = text.replace(old, new, 1)
for path, text in texts.items():
    open(path, "w").write(text)
