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
      ("Service.qml",
'''  readonly property int lowDuration: 5000
  readonly property int normalDuration: 8000''',
'''  // Overtake Mode on? (its flag file). This copy stays loaded in Omarchy mode
  // too, acting like Omarchy's own while the mode is off, so switching modes
  // needs no shell restart.
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
    // keys, space separated). Kept in both modes: it only takes entries out
    // of history.
    function forget(keys: string): string {
      var drop = String(keys || "").split(" ").filter(function(k) { return k !== "" })
      if (!service.historyLoaded) return "notready"   // (not read yet: it would come back)
      if (!drop.length) return "none"
      var kept = service.historyEntries.filter(function(e) { return drop.indexOf(String(e.key)) === -1 })
      if (kept.length === service.historyEntries.length) return "none"
      service.historyEntries = kept
      service.saveSoon("history")
      return "ok"
    }
'''),
    ],
    # Overtake Mode's battery alerts (per device, levels you choose) replace
    # Omarchy's single 10% laptop warning; power profiles still switch here.
    "battery": ("Service.qml",
'''  function checkBattery() {
    var state''',
'''  // Overtake Mode on? (its flag file). This copy stays loaded in Omarchy mode
  // too, warning as Omarchy's own does while the mode is off.
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
