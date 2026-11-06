import QtQuick
import Quickshell
import Quickshell.Io

// The repository's root plugin, for the plugin marketplace. Overtake Mode is
// several plugins plus a command and settings: ./install.sh copies its plugins (plugins/overtake.*) into
// ~/.config/omarchy/plugins, patches copies of a few of Omarchy's own widgets
// and adds its command and Hyprland settings, so `omarchy plugin add` on its
// own can't set it up. If this repository was added that way and the installer
// hasn't run yet, a notification says where to run it (at most once each time
// the shell starts, until it has). `omarchy plugin update` updates this folder
// but not what the installer set up, so the same goes when this folder's
// version is newer than the one the installer recorded, or the same with a
// different command in it. While the installer is running, and otherwise, this
// does nothing.
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
  // was never recorded, by a release before 0.1.15), or the same one when this
  // folder's command differs from the installed one (a change with no new
  // version number), else "".
  function versionToInstall(manifestText, installedText, commandDiffers) {
    var own = "", had = String(installedText || "").trim()
    try { own = String(JSON.parse(manifestText).version || "") } catch (e) {}
    if (own === "") return ""
    var a = own.split("."), b = had.split(".")
    for (var i = 0; i < Math.max(a.length, b.length); i++) {
      var d = (parseInt(a[i]) || 0) - (parseInt(b[i]) || 0)
      if (d !== 0) return d > 0 ? own : ""
    }
    return commandDiffers ? own : ""
  }

  property string reminderTitle: ""
  property string reminderBody: ""

  // Where things stand: "running" (the installer is at work, and the plugin
  // reloads it causes aren't a reason to remind), "missing", "differs" or
  // "same". The installer's marker counts only while that process is alive,
  // so one that was stopped halfway still gets the reminder.
  Process {
    id: installed
    command: ["sh", "-c", "m=\"$HOME/.local/share/overtake/installing\"; " +
      "if [ -s \"$m\" ] && kill -0 \"$(cat \"$m\")\" 2>/dev/null; then echo running; " +
      "elif [ ! -x \"$1\" ]; then echo missing; " +
      "elif cmp -s \"$2/bin/overtake\" \"$1\"; then echo same; else echo differs; fi", "sh", root.command, root.folder]
    running: true
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var state = text.trim()
        if (state === "running") return
        var body = ""
        if (state === "missing") {
          root.reminderTitle = "Finish installing Overtake Mode"
          body = "Run ./install.sh in ~/.config/omarchy/plugins/gleasonmt.overtake-mode (it lists every change and asks first)."
        } else {
          var version = root.versionToInstall(ownManifest.text(), installedVersion.text(), state === "differs")
          if (version === "") return
          root.reminderTitle = "Finish updating Overtake Mode"
          body = "Run ./install.sh again in ~/.config/omarchy/plugins/gleasonmt.overtake-mode to finish updating to " + version + "."
        }
        root.reminderBody = body
        oncePerShell.running = true
      }
    }
  }

  // Omarchy reloads a plugin whenever its plugins change, not only when the
  // shell starts. A folder named for this shell's process id, in the runtime
  // folder, says this shell has already given the reminder (mkdir can't succeed
  // twice, even for two reloads at once). Those of shells that have ended go.
  Process {
    id: oncePerShell
    command: ["sh", "-c", "[ -n \"$XDG_RUNTIME_DIR\" ] || exit 0; f=\"$XDG_RUNTIME_DIR/overtake-reminded.$1\"; " +
      "mkdir \"$f\" 2>/dev/null || exit 1; for d in \"$XDG_RUNTIME_DIR\"/overtake-reminded.*; do kill -0 \"${d##*.}\" 2>/dev/null || rmdir \"$d\" 2>/dev/null; done; exit 0", "sh", String(Quickshell.processId)]
    onExited: function(code) {
      if (code === 0)
        Quickshell.execDetached(["notify-send", "-a", "Overtake Mode", "--", root.reminderTitle, root.reminderBody])
    }
  }
}
