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
    function send(v, sayDone, sayFailed) {
      running = false
      value = v
      done = sayDone
      failed = sayFailed
      stdinEnabled = true
      running = true
    }
    command: ["wl-copy", "--sensitive"]
    onStarted: { write(value); value = ""; stdinEnabled = false }
    onExited: function(code) { service.showPlaceholder(code === 0 ? done : failed) }
    // (couldn't start at all: no exit comes, and the value was never taken)
    onRunningChanged: if (!running && value !== "") { value = ""; service.showPlaceholder(failed) }
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

  // Overtake Mode: omarchy-hyprland-focus-app reads its argument as a regular
  // expression, and here it's a name the sender chose: ".*" would match any
  // window, and a crafted pattern could tie up jq. So the name goes as literal
  // text. It still matches anywhere in a window's class, as Omarchy's does.
  function overtakeLiteral(name) {
    return String(name).replace(/[\\\\^$.|?*+()[\\]{}]/g, "\\\\$&")
  }

  // Overtake Mode: a sender's raw picture (the image-data hint) stays in memory
  // for as long as its card does, up to the bus's 64 MiB for each picture, and
  // nothing tells this code its size. So only this many cards may hold one;
  // past that, a card keeps its text and icon, and the sender's object is let
  // go, which takes its buttons with it. A picture bigger than a card could use
  // (see Toast.qml) is dropped once it has loaded, and the card keeps its buttons.
  readonly property int overtakeMaxPictures: 8
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
  }
  function overtakeDropPicture(key) {
    var at = rowIndexFor(key)
    if (at >= 0) toasts.setProperty(at, "image", "")
  }'''),
      ("Service.qml",
'''    runClip(["wl-copy", "--sensitive", "--", value])''',
'''    overtakeCodeClip.send(value)   // Overtake Mode: on stdin, not in argv'''),
      # A link from the message text: see overtakeOpenLink.
      ("Service.qml",
'''      else if (String(row.link || "")) Security.openExternalUrl(String(row.link))
      else if (String(row.app || "")) Util.execArgv(["omarchy-hyprland-focus-app", String(row.app)])''',
'''      else if (String(row.link || "")) service.overtakeOpenLink(String(row.link))   // Overtake Mode
      else if (String(row.app || "")) Util.execArgv(["omarchy-hyprland-focus-app", service.overtakeLiteral(String(row.app))])   // Overtake Mode'''),
      ("Service.qml",
'''              onLinkOpened: service.stopKeyboard()''',
'''              onLinkOpened: function(url) { service.stopKeyboard(); service.overtakeOpenLink(url) }   // Overtake Mode
              onPictureTooBig: service.overtakeDropPicture(model.key)   // Overtake Mode'''),
      # Overtake Mode: a local file named by a sender is never read. On this Qt,
      # a small PNG with compressed text chunks allocates gigabytes before the
      # size limit below applies, and this is the shared shell. Pixels the
      # sender handed over (qsimage) and the installed icons below still show.
      ("Toast.qml",
'''                                       ? String(card.row.image) : Security.localImageUrl(card.row.image)''',
'''                                       ? String(card.row.image) : ""   // Overtake Mode: no file a sender names'''),
      ("Toast.qml",
'''  signal linkOpened()''',
'''  signal linkOpened(string url)   // Overtake Mode: the service decides what opens
  signal pictureTooBig()          // Overtake Mode'''),
      ("Toast.qml",
'''          onLinkActivated: function(url) { card.linkOpened(); Security.openExternalUrl(url) }''',
'''          onLinkActivated: function(url) { card.linkOpened(url) }   // Overtake Mode: full link to the clipboard, only the site opens'''),
      ("Toast.qml",
'''          onStatusChanged: if (status === Image.Error && thumb.failed < thumb.sources.length) thumb.failed += 1''',
'''          onStatusChanged: {
            if (status === Image.Error && thumb.failed < thumb.sources.length) thumb.failed += 1
            // Overtake Mode: more than a megapixel in a 40-pixel slot only costs memory
            if (status === Image.Ready && thumb.photo && implicitWidth * implicitHeight > 1048576) card.pictureTooBig()
          }'''),
      # Overtake Mode: the card's picture is no longer counted once it's gone.
      ("Service.qml",
'''    if (!liveKeys[key]) return
    delete liveKeys[key]''',
'''    if (!liveKeys[key]) return
    delete overtakePictures[key]   // Overtake Mode
    delete liveKeys[key]'''),
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
    if (!service.overtakePictureFits(key, row)) { row.image = ""; service.release(key) }
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
      var left = rows.filter(function(e) { return !!e && typeof e === "object" && keep[String(e.key)] === true })
      var gone = left.length !== rows.length
      if (gone) overtakeLiveWrite.send(service.overtakeComparable(JSON.stringify(left) + "\\n"))
      // A card that arrived as this was read, or whose write didn't land, can
      // be missing from the file: written again from memory (reloaded first:
      // FileView skips the text it last wrote), and then about every 6 s until
      // the file has it.
      var have = Object.create(null)
      left.forEach(function(e) { have[String(e.key)] = true })
      var missing = service.liveEntries.some(function(e) { return have[String(e.key)] !== true })
      if (missing && overtakeLiveReadBack.tries++ === 0) overtakeLiveRetry.triggered()
      else if (missing || gone) overtakeLiveRetry.restart()
      else overtakeLiveReadBack.tries = 0
    }
  }
  Timer {
    id: overtakeLiveReadBack
    property int tries: 0
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
