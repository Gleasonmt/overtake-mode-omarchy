#!/usr/bin/env python3
"""Patch a copy of an Omarchy bar widget for Overtake Mode.

  apply.py <workspaces|bluetooth|audio> <plugin-dir>

Each patch is one exact replacement. If Omarchy has changed the code it
expects, nothing is written and it exits 1, so the installer can fall back to
Omarchy's own widget instead of shipping a broken one.
"""
import sys, os

PATCHES = {
    "workspaces": ("Workspaces.qml",
'''  function workspaceIds() {
    var ids = [1, 2, 3, 4, 5]
    var values = Hyprland.workspaces.values

    for (var i = 0; i < values.length; i++) {
      var id = values[i].id
      if (id > 0 && id <= 10 && ids.indexOf(id) === -1) ids.push(id)
    }

    ids.sort(function(left, right) { return left - right })
    return ids
  }''',
'''  // Overtake Mode: 1 through the highest workspace in use (at least 5), with
  // no gaps. Omarchy's own list skips empty ones past 5, so 8 could show
  // without 6 and 7, which reads as missing workspaces.
  function workspaceIds() {
    var highest = 5
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      var id = values[i].id
      if (id > highest && id <= 10) highest = id
    }
    var ids = []
    for (var n = 1; n <= highest; n++) ids.push(n)
    return ids
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
}

name, plugin_dir = sys.argv[1], sys.argv[2]
filename, old, new = PATCHES[name]
path = os.path.join(plugin_dir, filename)
text = open(path).read()
if old not in text:
    sys.exit(1)
open(path, "w").write(text.replace(old, new, 1))
