import QtQuick
import Quickshell
import Quickshell.Io

// Overtake Mode's always-loaded pieces: the min/max/close controls on the
// focused window, the desktop icons, battery alerts, and the Settings window.
// The controls, icons and alerts work only while Overtake Mode is on
// (~/.local/bin/overtake creates the flag file); Settings opens on request.
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

  WindowControls {
    modeOn: root.modeOn
  }

  DesktopIcons {
    modeOn: root.modeOn
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
