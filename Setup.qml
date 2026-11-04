import QtQuick
import Quickshell
import Quickshell.Io

// The repository's root plugin, for the plugin marketplace. Overtake Mode is a
// suite: ./install.sh copies its plugins (plugins/overtake.*) into
// ~/.config/omarchy/plugins, patches copies of a few of Omarchy's own widgets
// and adds its command and Hyprland settings, so `omarchy plugin add` on its
// own can't set it up. If this repository was added that way and the installer
// hasn't run yet, a notification says where to run it (each time the shell
// starts, until it has). Otherwise this does nothing.
Item {
  id: root

  property var shell: null

  readonly property string command: Quickshell.env("HOME") + "/.local/bin/overtake"
  readonly property string folder: String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "").replace(/\/$/, "")

  Process {
    id: installed
    command: ["test", "-x", root.command]
    running: true
    onExited: function(code) {
      if (code === 0) return
      Quickshell.execDetached(["notify-send", "-a", "Overtake Mode", "Finish installing Overtake Mode",
        "Run ./install.sh in " + root.folder + " (it lists every change and asks first)."])
    }
  }
}
