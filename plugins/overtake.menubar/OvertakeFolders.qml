import QtQuick
import Quickshell.Io

// Overtake's own folders (~/.config/overtake, ~/.local/state/overtake,
// ~/.cache/overtake) are made, or tightened, owner-only (0700) by
// `overtake status` before anything in this file watches or writes in them.
// A FileView watching a file whose folder is missing never wakes up, and one
// writing there would create the folder with default (0755) permissions, so
// file paths wait for `ready` and every write goes through write(), which
// checks the folders again first (one may have been deleted since).
Item {
  id: gate
  property bool ready: false
  property var queue: []
  function write(view, text) {
    queue = queue.concat([{ view: view, text: text }])
    check.running = true
  }
  Process {
    id: check
    command: ["overtake", "status"]
    running: true
    onExited: function(code) {
      gate.ready = true
      var q = gate.queue
      gate.queue = []
      if (code === 0) q.forEach(function(w) { w.view.setText(w.text) })
    }
  }
}
