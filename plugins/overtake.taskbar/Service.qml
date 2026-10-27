import QtQuick
import Quickshell
import Quickshell.Io

// Overtake Mode's always-loaded pieces: the title bar on the focused window,
// the desktop icons, battery alerts, and the Settings window; in the Studio
// look also the Dock, Spotlight, the App Switcher, Mission Control and Force
// Quit. They work only while Overtake Mode is on (~/.local/bin/overtake
// creates the flag file); Settings opens on request.
Item {
  id: root

  property var shell: null

  readonly property string flagPath: Quickshell.env("HOME") + "/.local/state/overtake/enabled"
  property bool modeOn: false

  Timer {
    interval: 1500
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: flagCheck.running = true
  }

  Process {
    id: flagCheck
    command: ["test", "-f", root.flagPath]
    onExited: function(code) { root.modeOn = code === 0 }
  }

  // The look: "classic" or "studio" (~/.config/overtake/style, set by
  // `overtake style`), and Studio's options (~/.config/overtake/studio.json).
  property string style: "classic"
  readonly property bool studio: modeOn && style === "studio"
  FileView {
    path: Quickshell.env("HOME") + "/.config/overtake/style"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.style = text().trim() === "studio" ? "studio" : "classic"
    onLoadFailed: root.style = "classic"
  }
  property var studioSettings: ({})
  FileView {
    path: Quickshell.env("HOME") + "/.config/overtake/studio.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: { try { root.studioSettings = JSON.parse(text() || "{}") } catch (e) { root.studioSettings = {} } }
    onLoadFailed: root.studioSettings = {}
  }

  WindowControls {
    modeOn: root.modeOn
    studio: root.studio
  }

  DesktopIcons {
    modeOn: root.modeOn
    studio: root.studio
  }

  AppModel { id: apps }
  Dock { active: root.studio; settings: root.studioSettings; apps: apps }
  Spotlight { id: spotlight; active: root.studio; appModel: apps }
  AppSwitcher { id: switcher; active: root.studio; apps: apps }
  MissionControl { id: missionControl; active: root.studio; apps: apps }
  ForceQuit { id: forceQuit; active: root.studio; apps: apps }

  // `overtake ui <what>` writes "<what> <time>" here (Studio's shortcuts).
  // The menu bar and Control Center watch the same file for their own.
  property string lastUiRequest: ""
  property bool uiRequestSeen: false
  FileView {
    path: Quickshell.env("HOME") + "/.local/state/overtake/ui-request"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      var value = text().trim()
      if (!value) { root.uiRequestSeen = true; return }
      if (value === root.lastUiRequest) return
      root.lastUiRequest = value
      var seen = root.uiRequestSeen
      root.uiRequestSeen = true
      if (!seen || !root.studio) return
      switch (value.split(" ")[0]) {
        case "spotlight": spotlight.show("search"); break
        case "apps": spotlight.show("apps"); break
        case "switcher": switcher.step(1); break
        case "switcher-back": switcher.step(-1); break
        case "switcher-commit": switcher.commit(); break
        case "switcher-cancel": switcher.cancel(); break
        case "switcher-quick": if (!switcher.open) switcher.step(1); switcher.commit(); break
        case "app-windows": switcher.nextAppWindow(); break
        case "mission-control": missionControl.toggle(); break
        case "force-quit": forceQuit.show(); break
      }
    }
    onLoadFailed: root.uiRequestSeen = true
  }

  BatteryAlerts {
    id: batteryAlerts
    modeOn: root.modeOn
  }

  Settings {
    id: settings
    batteryAlerts: batteryAlerts
  }

  // `overtake settings [page]` writes "<page> <time>" here. A rewrite
  // arrives as two changes (truncate, then write), so only a new non-empty
  // value counts, and the first value seen is just startup.
  property string lastSettingsRequest: ""
  property bool settingsRequestSeen: false
  FileView {
    path: Quickshell.env("HOME") + "/.local/state/overtake/settings-request"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      var value = text().trim()
      if (!value) { root.settingsRequestSeen = true; return }
      if (value === root.lastSettingsRequest) return
      if (root.settingsRequestSeen) settings.show(value.split(" ")[0])
      root.lastSettingsRequest = value
      root.settingsRequestSeen = true
    }
    onLoadFailed: root.settingsRequestSeen = true
  }
}
