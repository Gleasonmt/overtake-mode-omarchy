import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower

// Battery alerts for Overtake Mode. Every device UPower reports a battery for
// (the laptop, and Bluetooth or USB mice, keyboards, headsets, controllers,
// ...) has a Low and a Critical level. Dropping to one sends a notification
// from "Battery", so it also lands in the notification center and can be set
// to Quiet there; each level fires once, and again after the device has charged
// back above it or the shell has restarted. Levels are set in Settings > System > Battery alerts
// and kept in ~/.config/overtake/battery-alerts.json:
//   { "devices": { "laptop": { "low": 20, "critical": 10, "enabled": true },
//                  "MX Master 3S": { "low": 15, "critical": 5, "name": "MX Master 3S", "kind": "Mouse" } } }
// A device seen once stays listed (as not connected) so its levels can be set
// any time. While the mode is on these replace Omarchy's own 10% laptop
// warning (overtake.battery); the battery-low hook still runs at the laptop's
// Critical level.
Item {
  id: root
  OvertakeFolders { id: folders }   // Overtake's folders private before they're used

  property bool modeOn: false

  readonly property string configPath: Quickshell.env("HOME") + "/.config/overtake/battery-alerts.json"
  readonly property var laptopDefaults: ({ low: 20, critical: 10, enabled: true })
  readonly property var deviceDefaults: ({ low: 15, critical: 5, enabled: true })

  property var config: ({ devices: {} })
  property bool configLoaded: false
  // For the Settings page: connected devices first, then remembered ones.
  property var deviceList: []

  PersistentProperties {
    id: persisted
    reloadableId: "overtake-battery-alerts"
    property var fired: ({})   // device key -> "low" | "critical" once alerted
  }

  // ---------- Devices ----------
  function isBattery(d) {
    // (0% is a battery only for a device already known as one: other things report 0 too)
    return !!d && d.type !== UPowerDeviceType.LinePower && (d.isLaptopBattery || d.percentage > 0 || !!ownOf(config.devices, keyOf(d)))
  }
  function liveDevices() { return (UPower.devices.values || []).filter(isBattery) }
  // A device names itself: a name a plain object already has ("__proto__",
  // "constructor", ...) gets a suffix, so it can never reach the shared
  // engine's built-in objects.
  function keyOf(d) {
    if (d.isLaptopBattery) return "laptop"
    var key = String(d.model || d.nativePath || "Battery")
    // ("laptop" is the laptop's own key: a device can't take it over)
    return key === "laptop" || key === "__proto__" || key in Object.prototype ? key + " (device)" : key
  }
  function kindOf(d) { return d.isLaptopBattery ? "Laptop" : String(UPowerDeviceType.toString(d.type) || "Battery") }
  function nameOf(d) { return d.isLaptopBattery ? "Laptop battery" : String(d.model || kindOf(d)) }
  function percentOf(d) { return Math.round(Number(d.percentage || 0) * 100) }
  function isCharging(d) {
    if (d.isLaptopBattery && !UPower.onBattery) return true
    return d.state === UPowerDeviceState.Charging || d.state === UPowerDeviceState.FullyCharged
      || d.state === UPowerDeviceState.PendingCharge
  }

  // (a device may call itself "constructor": only a key of the object's own)
  function ownOf(map, key) { return map && Object.prototype.hasOwnProperty.call(map, key) ? map[key] : undefined }
  function levelsFor(key) {
    var base = key === "laptop" ? laptopDefaults : deviceDefaults
    var own = ownOf(config.devices, key) || {}
    return {
      low: Number(own.low !== undefined ? own.low : base.low),
      critical: Number(own.critical !== undefined ? own.critical : base.critical),
      enabled: own.enabled !== false
    }
  }

  // ---------- Settings ----------
  FileView {
    id: configFile
    path: folders.ready ? root.configPath : ""
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try { root.config = JSON.parse(text()) || { devices: {} } } catch (e) { root.config = { devices: {} } }
      if (!root.config.devices) root.config = { devices: {} }
      root.configLoaded = true
      root.refresh()
    }
    onLoadFailed: { root.config = { devices: {} }; root.configLoaded = true; root.refresh() }
  }
  function save(next) {
    config = next
    folders.write(configFile, JSON.stringify(next, null, 2) + "\n")
    refreshList()
  }

  // Change a device's level ("low" / "critical") or "enabled". Critical stays
  // at least 5 below Low.
  function setLevel(key, field, value) {
    var next = JSON.parse(JSON.stringify(config))
    var own = ownOf(next.devices, key) || (next.devices[key] = {})
    var levels = levelsFor(key)
    if (field === "enabled") {
      own.enabled = !!value
    } else {
      value = Math.round(Number(value))
      if (field === "low") {
        own.low = Math.max(10, Math.min(95, value))
        if (levels.critical > own.low - 5) own.critical = own.low - 5
      } else {
        own.critical = Math.max(5, Math.min(levels.low - 5, value))
      }
    }
    // Moving a level re-arms that device's alerts.
    var f = Object.assign({}, persisted.fired)
    delete f[key]
    persisted.fired = f
    save(next)
    check()
  }

  // Remember devices seen, so they stay in the list while disconnected.
  function rememberDevices() {
    if (!configLoaded) return
    var next = null
    liveDevices().forEach(function(d) {
      var key = keyOf(d)
      var known = ownOf(config.devices, key)
      if (known && known.name) return
      if (!next) next = JSON.parse(JSON.stringify(config))
      var own = ownOf(next.devices, key) || (next.devices[key] = {})
      own.name = String(nameOf(d)).slice(0, 256)   // (a name is the device's to choose)
      own.kind = String(kindOf(d)).slice(0, 64)
    })
    if (next) save(next)
  }

  function refreshList() {
    var seen = Object.create(null), rows = []
    liveDevices().forEach(function(d) {
      var key = keyOf(d)
      if (seen[key]) return
      seen[key] = true
      var lv = levelsFor(key)
      rows.push({ key: key, name: nameOf(d), kind: kindOf(d), connected: true, percent: percentOf(d),
                  charging: isCharging(d), low: lv.low, critical: lv.critical, enabled: lv.enabled })
    })
    rows.sort(function(a, b) { return (a.key === "laptop" ? -1 : 0) - (b.key === "laptop" ? -1 : 0) || a.name.localeCompare(b.name) })
    var gone = []
    Object.keys(config.devices || {}).forEach(function(key) {
      if (seen[key]) return
      var own = ownOf(config.devices, key), lv = levelsFor(key)
      gone.push({ key: key, name: own.name || key, kind: own.kind || "Battery", connected: false, percent: -1,
                  charging: false, low: lv.low, critical: lv.critical, enabled: lv.enabled })
    })
    gone.sort(function(a, b) { return a.name.localeCompare(b.name) })
    deviceList = rows.concat(gone)
  }

  // ---------- Alerts ----------
  function iconFor(kind, level) {
    var icons = { Mouse: "input-mouse", Keyboard: "input-keyboard", Headset: "audio-headset", Headphones: "audio-headphones",
                  GamingInput: "input-gaming", Phone: "phone", Tablet: "input-tablet", Pen: "input-tablet", Touchpad: "input-touchpad" }
    return icons[kind] || (level === "critical" ? "battery-caution" : "battery-low")
  }

  function alert(d, percent, level) {
    var name = nameOf(d), kind = kindOf(d)
    var what = d.isLaptopBattery ? "Battery" : name + " battery"
    var title = what + (level === "critical" ? " critical" : " low")
    var body = level === "critical"
      ? percent + "% left. " + (d.isLaptopBattery ? "Plug in now." : "Charge it now.")
      : percent + "% left. " + (d.isLaptopBattery ? "Plug in soon." : "Charge it soon.")
    // Device names (chosen by the device) go over stdin, never in a command line.
    var note = { app: "Battery", icon: iconFor(kind, level), urgency: level === "critical" ? "critical" : "normal", summary: title, body: body }
    notifier.queue = notifier.queue.concat([JSON.stringify(note)])
    notifier.next()
    // Keep Omarchy's battery-low hook working, at the laptop's Critical level.
    if (d.isLaptopBattery && level === "critical") Quickshell.execDetached(["omarchy-hook", "battery-low", String(percent)])
  }

  Process {
    id: notifier
    property var queue: []
    property string pending: ""
    command: ["overtake", "notify-stdin"]
    stdinEnabled: true
    function next() {
      if (running || !queue.length) return
      pending = queue[0]
      queue = queue.slice(1)
      stdinEnabled = true
      running = true
    }
    onStarted: { write(pending); stdinEnabled = false; pending = "" }
    onExited: next()
  }

  function check() {
    if (!configLoaded) return
    rememberDevices()
    refreshList()
    if (!modeOn) return
    var fired = Object.assign({}, persisted.fired), changed = false
    // One device per key (two laptop batteries, a mouse seen through both its
    // receiver and Bluetooth): the one that most needs charging, so the key's
    // state isn't re-armed by one and fired again by the other.
    var byKey = Object.create(null), laptops = 0
    liveDevices().forEach(function(d) {
      var k = keyOf(d), cur = byKey[k]
      if (d.isLaptopBattery) laptops++
      if (!cur) { byKey[k] = d; return }
      var curCharging = isCharging(cur), charging = isCharging(d)
      if ((curCharging && !charging) || (curCharging === charging && percentOf(d) < percentOf(cur))) byKey[k] = d
    })
    // A laptop with two packs: its combined charge, as Omarchy reads it
    // (UPower's display device), not whichever pack is lowest.
    var whole = UPower.displayDevice
    if (laptops > 1 && whole && whole.isPresent)
      byKey["laptop"] = { isLaptopBattery: true, percentage: whole.percentage, state: whole.state, model: "", type: whole.type, nativePath: "" }
    Object.keys(byKey).forEach(function(k) {
      var d = byKey[k]
      var key = keyOf(d), lv = levelsFor(key), p = percentOf(d)
      var state = ownOf(fired, key) || ""
      var next = state
      if (!lv.enabled || isCharging(d) || p > lv.low + 2) next = ""            // re-armed
      else if (p <= lv.critical) {
        if (state !== "critical") { alert(d, p, "critical"); next = "critical" }
      } else if (p <= lv.low) {
        if (state === "") { alert(d, p, "low"); next = "low" }
        else if (state === "critical" && p > lv.critical + 2) next = "low"      // critical re-armed
      }
      if (next !== state) { fired[key] = next; changed = true }
    })
    if (changed) persisted.fired = fired
  }
  function refresh() { checkLater.restart() }

  Timer { id: checkLater; interval: 400; onTriggered: root.check() }
  Timer { interval: 30000; running: true; repeat: true; onTriggered: root.check() }
  onModeOnChanged: refresh()

  Connections {
    target: UPower
    function onOnBatteryChanged() { root.refresh() }
  }
  Connections {
    target: UPower.devices
    function onValuesChanged() { root.refresh() }
  }
  // Each device's level and charging state, as they change.
  Instantiator {
    model: UPower.devices
    delegate: Connections {
      required property var modelData
      target: modelData
      function onPercentageChanged() { root.refresh() }
      function onStateChanged() { root.refresh() }
    }
  }
}
