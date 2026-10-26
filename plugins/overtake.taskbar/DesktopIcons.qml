import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import "DesktopList.js" as DesktopList

// The desktop in Overtake Mode: a full-screen surface on the layer just above
// the wallpaper, so windows cover it and it shows on empty workspaces and with
// Super+D. Icons sit in a column on the left of each screen: click selects,
// double-click opens, right-click gives Open, Pin to Start, Pin to taskbar,
// Remove desktop icon, Rename and Move up / down (and Empty Trash on the
// Trash). Right-click on the desktop itself gives the view options (icon size,
// sort, show icons), Add a shortcut, background and theme, screensaver,
// Personalize, Display settings and a terminal. A plain click on the desktop
// minimizes the windows on that screen's workspace.
//
// The icons live in ~/.config/overtake/desktop-icons.txt ("<id> | <label>").
// Besides desktop entry ids it understands "trash", "browser" (your default
// browser) and "terminal" (your default terminal); apps that aren't installed
// are skipped. View options live in ~/.config/overtake/desktop.json.
Item {
  id: root

  property bool modeOn: false
  property var icons: []
  property string iconsText: ""
  property string selected: ""
  property string renaming: ""        // icon id being renamed
  property var view: ({ iconSize: "medium", showIcons: true })

  // The open right-click menu: which screen, where, and its rows.
  property string menuScreen: ""
  property point menuPos: Qt.point(0, 0)
  property var menuRows: []
  property var confirm: null          // { text, button, run } while asking

  readonly property string configDir: Quickshell.env("HOME") + "/.config/overtake"
  readonly property real iconScale: ({ small: 0.8, medium: 1, large: 1.3 })[view.iconSize] || 1

  FileView {
    id: iconsFile
    path: root.configDir + "/desktop-icons.txt"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.parseIcons(text())
  }
  function parseIcons(text) {
    iconsText = text
    icons = DesktopList.lines(text).filter(DesktopList.isIcon)
      .map(function(line) { return { id: DesktopList.idOf(line), label: DesktopList.labelOf(line) } })
      .filter(function(icon) { return root.builtIn[icon.id] || DesktopEntries.byId(icon.id) })
  }
  function writeIcons(text) {
    iconsFile.setText(text)
    parseIcons(text)
  }

  FileView {
    id: viewFile
    path: root.configDir + "/desktop.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: { try { root.view = Object.assign({ iconSize: "medium", showIcons: true }, JSON.parse(text())) } catch (e) {} }
  }
  function setView(key, value) {
    var next = Object.assign({}, view)
    next[key] = value
    view = next
    viewFile.setText(JSON.stringify(next, null, 2) + "\n")
  }

  // Icons that aren't a desktop entry: what they open and how they look.
  readonly property var builtIn: ({
    trash: { icon: "user-trash", label: "Trash", command: ["uwsm-app", "--", "nautilus", "trash:///"] },
    browser: { icon: "web-browser", label: "Browser", command: ["omarchy-launch-browser"] },
    terminal: { icon: "utilities-terminal", label: "Terminal", command: ["uwsm-app", "--", "omarchy-launch-terminal"] }
  })

  function entryFor(icon) {
    return root.builtIn[icon.id] ? null : DesktopEntries.byId(icon.id)
  }

  function labelFor(icon) {
    if (icon.label) return icon.label
    if (root.builtIn[icon.id]) return root.builtIn[icon.id].label
    var entry = entryFor(icon)
    return entry ? entry.name : icon.id
  }

  function iconSource(icon) {
    var name = root.builtIn[icon.id] ? root.builtIn[icon.id].icon : (entryFor(icon) ? entryFor(icon).icon : "")
    var source = name ? Quickshell.iconPath(name, true) : ""
    return source || Quickshell.iconPath("application-x-executable", true)
  }

  function open(icon) {
    if (root.builtIn[icon.id]) Quickshell.execDetached(root.builtIn[icon.id].command)
    else Quickshell.execDetached(["uwsm-app", "--", "gtk-launch", icon.id + ".desktop"])
    root.selected = ""
  }

  function run(command) { Quickshell.execDetached(["sh", "-c", command]) }

  // ---------- Start pins (for the icon menu) ----------
  property var startPins: []
  FileView {
    id: pinsFile
    path: root.configDir + "/start-pinned.txt"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.startPins = text().split("\n").map(function(l) { return l.trim() }).filter(function(l) { return l && l.charAt(0) !== "#" })
  }
  function toggleStartPin(id) {
    var next = startPins.slice(), i = next.indexOf(id)
    if (i === -1) next.push(id)
    else next.splice(i, 1)
    startPins = next
    pinsFile.setText("# Start menu pins, one desktop entry id per line (managed by the Start menu).\n" + next.join("\n") + "\n")
  }

  // ---------- Taskbar pins (for the icon menu) ----------
  // The taskbar keeps its pins in the shell's settings; it applies the
  // changes asked for in ~/.local/state/overtake/taskbar-pin-request.
  property var taskbarPins: []
  FileView {
    path: Quickshell.env("HOME") + "/.config/omarchy/shell.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      var pins = null
      function find(node) {
        if (pins || !node || typeof node !== "object") return
        if (node.id === "overtake.taskbar" && Array.isArray(node.pinned)) { pins = node.pinned; return }
        for (var k in node) find(node[k])
      }
      try { find(JSON.parse(text())) } catch (e) {}
      root.taskbarPins = (pins || ["chromium", "org.gnome.Nautilus", "foot"]).map(String)
    }
  }
  FileView { id: pinRequestFile; path: Quickshell.env("HOME") + "/.local/state/overtake/taskbar-pin-request"; printErrors: false }
  function setTaskbarPin(id, pin) {
    pinRequestFile.setText((pin ? "pin " : "unpin ") + id + " " + Date.now() + "\n")
  }

  // ---------- Right-click menus ----------
  function closeMenu() { menuRows = []; confirm = null }

  function showMenu(screenName, pos, rows) {
    confirm = null
    menuScreen = screenName
    menuPos = pos
    menuRows = rows
  }

  function iconMenu(icon) {
    var isApp = !root.builtIn[icon.id]
    var at = -1
    for (var i = 0; i < icons.length; i++) if (icons[i].id === icon.id) at = i
    var rows = [{ glyph: "", label: "Open", run: function() { root.open(icon) } }]
    if (icon.id === "trash") rows.push({ glyph: "", label: "Empty Trash…", run: function() {
      root.confirm = { text: "Permanently delete everything in the Trash?", button: "Empty Trash", run: function() { root.run("gio trash --empty") } }
    }, keepOpen: true })
    if (isApp) rows.push({ glyph: "", label: startPins.indexOf(icon.id) !== -1 ? "Unpin from Start" : "Pin to Start",
                           run: function() { root.toggleStartPin(icon.id) } })
    if (isApp) rows.push({ glyph: "", label: taskbarPins.indexOf(icon.id) !== -1 ? "Unpin from taskbar" : "Pin to taskbar",
                           run: function() { root.setTaskbarPin(icon.id, taskbarPins.indexOf(icon.id) === -1) } })
    rows.push({ separator: true })
    rows.push({ glyph: "", label: "Remove desktop icon", run: function() { root.writeIcons(DesktopList.remove(root.iconsText, icon.id)) } })
    rows.push({ glyph: "", label: "Rename", run: function() { root.renaming = icon.id } })
    if (at > 0) rows.push({ glyph: "", label: "Move up", run: function() { root.writeIcons(DesktopList.move(root.iconsText, icon.id, -1)) } })
    if (at >= 0 && at < icons.length - 1) rows.push({ glyph: "", label: "Move down", run: function() { root.writeIcons(DesktopList.move(root.iconsText, icon.id, 1)) } })
    return rows
  }

  function desktopMenu() {
    var size = view.iconSize
    return [
      { header: "View" },
      { glyph: "", label: "Large icons", checked: size === "large", run: function() { root.setView("iconSize", "large") } },
      { glyph: "", label: "Medium icons", checked: size === "medium", run: function() { root.setView("iconSize", "medium") } },
      { glyph: "", label: "Small icons", checked: size === "small", run: function() { root.setView("iconSize", "small") } },
      { glyph: "", label: "Show desktop icons", checked: view.showIcons !== false, run: function() { root.setView("showIcons", view.showIcons === false) } },
      { glyph: "", label: "Sort by name", run: function() {
        root.writeIcons(DesktopList.sortBy(root.iconsText, function(id, label) { return root.labelFor({ id: id, label: label }) }))
      } },
      { glyph: "", label: "Refresh", run: function() { iconsFile.reload(); viewFile.reload() } },
      { separator: true },
      { glyph: "", label: "Add a shortcut…", run: function() { root.run("overtake start all") } },
      { glyph: "", label: "Open in Terminal", run: function() { Quickshell.execDetached(["uwsm-app", "--", "omarchy-launch-terminal"]) } },
      { separator: true },
      { glyph: "", label: "Next desktop background", run: function() { root.run("overtake next-wallpaper") } },
      { glyph: "", label: "Change background…", run: function() { root.run("background=$(omarchy-theme-bg-switcher); [[ -n $background ]] && omarchy-theme-bg-set \"$background\"") } },
      { glyph: "", label: "Change theme…", run: function() { root.run("omarchy-menu toggle theme") } },
      { glyph: "\uf26c", label: "Screensaver settings…", run: function() { root.run("overtake settings screensaver") } },
      { glyph: "", label: "Personalize", run: function() { root.run("overtake settings personalization") } },
      { glyph: "", label: "Display settings", run: function() { root.run("overtake settings system") } }
    ]
  }

  // Clicking into a window (focus moving) closes the menu and any rename,
  // as clicking away from a desktop menu does.
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event.name === "activewindowv2" && String(event.data) !== "" && (root.menuRows.length || root.renaming)) {
        root.closeMenu()
        root.renaming = ""
      }
    }
  }

  // ---------- One full-screen desktop per screen ----------
  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: desk
      required property var modelData

      screen: modelData
      visible: root.modeOn
      color: "transparent"
      exclusionMode: ExclusionMode.Normal
      WlrLayershell.namespace: "overtake-desktop"
      WlrLayershell.layer: WlrLayer.Bottom
      // Keyboard only while renaming an icon.
      WlrLayershell.keyboardFocus: root.renaming !== "" ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
      anchors { top: true; bottom: true; left: true; right: true }

      readonly property bool menuHere: root.menuRows.length > 0 && root.menuScreen === modelData.name

      // The desktop itself.
      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        // A click on the desktop itself minimizes this screen's windows, a quick
        // way to the desktop (one that only closes a menu or a rename doesn't).
        onClicked: function(mouse) {
          var busy = root.menuRows.length > 0 || root.renaming !== ""
          root.selected = ""
          root.renaming = ""
          if (mouse.button === Qt.RightButton) root.showMenu(desk.modelData.name, Qt.point(mouse.x, mouse.y), root.desktopMenu())
          else {
            root.closeMenu()
            if (!busy) Quickshell.execDetached(["overtake", "minimize-all", desk.modelData.name])
          }
        }
      }

      Column {
        id: iconColumn
        x: Style.space(16)
        y: Style.space(16)
        spacing: Style.space(6) * root.iconScale
        visible: root.view.showIcons !== false

        Repeater {
          model: root.icons

          Item {
            id: tile
            required property var modelData
            readonly property bool isSelected: root.selected === modelData.id
            readonly property bool isRenaming: root.renaming === modelData.id

            width: Style.space(92) * root.iconScale
            height: Style.space(88) * root.iconScale

            Rectangle {
              anchors.fill: parent
              radius: Style.space(4)
              color: tile.isSelected ? Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.35)
                                     : Qt.rgba(1, 1, 1, area.containsMouse ? 0.12 : 0)
              border.width: tile.isSelected || area.containsMouse ? 1 : 0
              border.color: Qt.rgba(1, 1, 1, 0.25)
            }

            Image {
              id: image
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.top: parent.top
              anchors.topMargin: Style.space(8) * root.iconScale
              width: Style.space(44) * root.iconScale
              height: width
              sourceSize.width: width * 2
              sourceSize.height: height * 2
              source: root.iconSource(tile.modelData)
              smooth: true
              asynchronous: true
            }

            MouseArea {
              id: area
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              acceptedButtons: Qt.LeftButton | Qt.RightButton
              onClicked: function(mouse) {
                root.renaming = ""
                root.selected = tile.modelData.id
                if (mouse.button === Qt.RightButton) {
                  var p = tile.mapToItem(null, mouse.x, mouse.y)
                  root.showMenu(desk.modelData.name, Qt.point(p.x, p.y), root.iconMenu(tile.modelData))
                } else root.closeMenu()
              }
              onDoubleClicked: function(mouse) { if (mouse.button === Qt.LeftButton) root.open(tile.modelData) }
            }

            Text {
              visible: !tile.isRenaming
              anchors.top: image.bottom
              anchors.topMargin: Style.space(6) * root.iconScale
              anchors.horizontalCenter: parent.horizontalCenter
              width: parent.width - Style.space(8)
              horizontalAlignment: Text.AlignHCenter
              textFormat: Text.PlainText
              text: root.labelFor(tile.modelData)
              color: "#ffffff"
              style: Text.Outline
              styleColor: Qt.rgba(0, 0, 0, 0.6)
              wrapMode: Text.WordWrap
              maximumLineCount: 2
              elide: Text.ElideRight
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
            }

            // Rename in place: Enter saves (empty goes back to the app's own
            // name), Escape or a click elsewhere cancels.
            Rectangle {
              visible: tile.isRenaming
              anchors.top: image.bottom
              anchors.topMargin: Style.space(4)
              anchors.horizontalCenter: parent.horizontalCenter
              width: Math.max(parent.width, nameInput.contentWidth + Style.space(12))
              height: nameInput.implicitHeight + Style.space(6)
              radius: Style.space(3)
              color: Commons.Color.background
              border.width: 1
              border.color: Commons.Color.accent
              TextInput {
                id: nameInput
                anchors.fill: parent
                anchors.margins: Style.space(3)
                horizontalAlignment: TextInput.AlignHCenter
                color: Commons.Color.foreground
                selectionColor: Commons.Color.accent
                selectedTextColor: Commons.Color.background
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                onVisibleChanged: if (visible) {
                  text = root.labelFor(tile.modelData)
                  forceActiveFocus()
                  selectAll()
                }
                Keys.onPressed: function(event) {
                  if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    var label = text.trim()
                    var own = root.labelFor({ id: tile.modelData.id, label: "" })
                    root.writeIcons(DesktopList.rename(root.iconsText, tile.modelData.id, label === own ? "" : label))
                    root.renaming = ""
                    event.accepted = true
                  } else if (event.key === Qt.Key_Escape) {
                    root.renaming = ""
                    event.accepted = true
                  }
                }
              }
            }
          }
        }
      }

      // The right-click menu.
      Rectangle {
        id: menu
        visible: desk.menuHere
        readonly property real menuWidth: Style.space(250)
        x: Math.max(0, Math.min(root.menuPos.x, desk.width - width - Style.space(4)))
        y: Math.max(0, Math.min(root.menuPos.y, desk.height - height - Style.space(4)))
        width: menuWidth
        height: menuColumn.implicitHeight + Style.space(12)
        radius: Style.space(8)
        color: Commons.Color.popups.background
        border.width: 1
        border.color: Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.2)

        // swallow clicks on the menu's own padding
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.LeftButton | Qt.RightButton }

        Column {
          id: menuColumn
          x: Style.space(6)
          y: Style.space(6)
          width: parent.width - Style.space(12)

          // Asking before something that can't be undone.
          Column {
            visible: root.confirm !== null
            width: parent.width
            spacing: Style.space(8)
            padding: Style.space(6)
            Text {
              textFormat: Text.PlainText
              width: parent.width - Style.space(12)
              wrapMode: Text.Wrap
              text: root.confirm ? root.confirm.text : ""
              color: Commons.Color.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
            }
            Row {
              spacing: Style.space(8)
              Repeater {
                model: root.confirm ? [root.confirm.button, "Cancel"] : []
                Rectangle {
                  required property string modelData
                  required property int index
                  width: label.implicitWidth + Style.space(20)
                  height: Style.space(28)
                  radius: Style.space(5)
                  color: index === 0 ? Commons.Color.urgent : Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, choiceArea.containsMouse ? 0.16 : 0.08)
                  Text {
                    textFormat: Text.PlainText
                    id: label
                    anchors.centerIn: parent
                    text: parent.modelData
                    color: parent.index === 0 ? Commons.Color.background : Commons.Color.foreground
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall
                    font.bold: parent.index === 0
                  }
                  MouseArea {
                    id: choiceArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                      if (parent.index === 0 && root.confirm) root.confirm.run()
                      root.closeMenu()
                    }
                  }
                }
              }
            }
          }

          Repeater {
            model: root.confirm === null ? root.menuRows : []

            Item {
              id: row
              required property var modelData
              width: menuColumn.width
              height: modelData.separator ? Style.space(9) : (modelData.header ? Style.space(24) : Style.space(30))

              Rectangle {
                visible: !!row.modelData.separator
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: 1
                color: Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.12)
              }

              Text {
                textFormat: Text.PlainText
                visible: !!row.modelData.header
                anchors.verticalCenter: parent.verticalCenter
                x: Style.space(8)
                text: row.modelData.header || ""
                color: Commons.Color.foreground
                opacity: 0.5
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                font.bold: true
              }

              Rectangle {
                visible: !row.modelData.separator && !row.modelData.header
                anchors.fill: parent
                radius: Style.space(5)
                color: rowArea.containsMouse ? Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.1) : "transparent"

                Text {
                  textFormat: Text.PlainText
                  id: rowGlyph
                  x: Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(20)
                  horizontalAlignment: Text.AlignHCenter
                  text: row.modelData.glyph || ""
                  color: Commons.Color.foreground
                  opacity: 0.8
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                }
                Text {
                  textFormat: Text.PlainText
                  anchors.left: rowGlyph.right
                  anchors.leftMargin: Style.space(10)
                  anchors.right: check.left
                  anchors.verticalCenter: parent.verticalCenter
                  text: row.modelData.label || ""
                  elide: Text.ElideRight
                  color: Commons.Color.foreground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                }
                Text {
                  textFormat: Text.PlainText
                  id: check
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(10)
                  anchors.verticalCenter: parent.verticalCenter
                  text: row.modelData.checked ? "" : ""
                  color: Commons.Color.accent
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                }
                MouseArea {
                  id: rowArea
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    var keep = row.modelData.keepOpen
                    if (row.modelData.run) row.modelData.run()
                    if (!keep) root.closeMenu()
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
