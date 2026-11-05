import QtQuick
import Quickshell
import Quickshell.Io

// The repository's root plugin, for the plugin marketplace. Overtake Mode is
// several plugins plus a command and settings: ./install.sh copies its plugins (plugins/overtake.*) into
// ~/.config/omarchy/plugins, patches copies of a few of Omarchy's own widgets
// and adds its command and Hyprland settings, so `omarchy plugin add` on its
// own can't set it up. If this repository was added that way and the installer
// hasn't run yet, a notification says where to run it (each time the shell
// starts, until it has). `omarchy plugin update` updates this folder but not
// what the installer set up, so the same goes when this folder is newer than
// the version the installer recorded. Otherwise this does nothing.
Item {
  id: root

  property var shell: null

  readonly property string command: Quickshell.env("HOME") + "/.local/bin/overtake"
  readonly property string folder: String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "").replace(/\/$/, "")

  FileView {
    id: installedVersion
    path: Quickshell.env("HOME") + "/.local/share/overtake/version"
    blockLoading: true
    printErrors: false
  }
  FileView {
    id: ownManifest
    path: root.folder + "/manifest.json"
    blockLoading: true
    printErrors: false
  }

  // This folder's version when it is newer than the installed one (or that
  // was never recorded, by a release before 0.1.15), else "".
  function versionToInstall(manifestText, installedText) {
    var own = "", had = String(installedText || "").trim()
    try { own = String(JSON.parse(manifestText).version || "") } catch (e) {}
    if (own === "") return ""
    var a = own.split("."), b = had.split(".")
    for (var i = 0; i < Math.max(a.length, b.length); i++) {
      var d = (parseInt(a[i]) || 0) - (parseInt(b[i]) || 0)
      if (d !== 0) return d > 0 ? own : ""
    }
    return ""
  }

  Process {
    id: installed
    command: ["test", "-x", root.command]
    running: true
    onExited: function(code) {
      if (code === 0) {
        var version = root.versionToInstall(ownManifest.text(), installedVersion.text())
        if (version !== "")
          Quickshell.execDetached(["notify-send", "-a", "Overtake Mode", "--", "Finish updating Overtake Mode",
            "Run ./install.sh again in ~/.config/omarchy/plugins/gleasonmt.overtake-mode to finish updating to " + version + "."])
        return
      }
      Quickshell.execDetached(["notify-send", "-a", "Overtake Mode", "--", "Finish installing Overtake Mode",
        "Run ./install.sh in ~/.config/omarchy/plugins/gleasonmt.overtake-mode (it lists every change and asks first)."])
    }
  }
}
