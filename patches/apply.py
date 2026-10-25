#!/usr/bin/env python3
"""Patch a copy of an Omarchy plugin for Overtake Mode.

  apply.py <workspaces|bluetooth|audio|notifications> <plugin-dir>

Each patch is one or more exact replacements. If Omarchy has changed any code
one expects, nothing is written and it exits 1, so the installer can fall back
to Omarchy's own plugin instead of shipping a broken one.
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
    "notifications": [
      ("components/NotificationCard.qml",
'''  ColumnLayout {
    id: mainColumn''',
'''  // Overtake Mode: a close button like a desktop toast's. It shows while the
  // pointer is over the card, and always on critical notifications, which
  // never time out (right-click still closes any card too).
  Item {
    id: closeButton
    z: 2
    anchors.top: parent.top
    anchors.right: parent.right
    anchors.topMargin: root.borderTop + Style.space(5)
    anchors.rightMargin: root.borderRight + Style.space(5)
    width: Style.space(22)
    height: Style.space(22)
    visible: root.hovered || root.urgency === 2

    Rectangle {
      anchors.fill: parent
      radius: width / 2
      color: closeMouse.containsMouse ? Qt.rgba(Commons.Color.notifications.text.r, Commons.Color.notifications.text.g, Commons.Color.notifications.text.b, 0.16) : "transparent"
    }
    Text {
      anchors.centerIn: parent
      text: "\\uf00d"
      font.family: root.fontFamily
      font.pixelSize: Style.space(12)
      color: closeMouse.containsMouse ? Commons.Color.notifications.text : root.dimColor
    }
    MouseArea {
      id: closeMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.closeRequested()
    }
  }

  ColumnLayout {
    id: mainColumn'''),
      ("components/NotificationCard.qml",
'''      Layout.rightMargin: Style.space(12)''',
'''      Layout.rightMargin: Style.space(30)  // Overtake Mode: room for the close button'''),
    ],
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
    if old not in text:
        sys.exit(1)
    texts[path] = text.replace(old, new, 1)
for path, text in texts.items():
    open(path, "w").write(text)
