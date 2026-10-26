import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "DesktopList.js" as DesktopList

// Start menu (left-click Start, or `overtake start`) and
// the Super+X quick-link menu (right-click Start, or `overtake start quick`).
//
// Start pages: home (Pinned, Folders, Recommended), all apps, search results
// (just type), and a file browser opened from Folders that fills the menu,
// with Back. Each page is built fresh by a Loader when it's shown, and app
// lists hold plain copies of each app's details: swapping one view's model
// between live DesktopEntry lists crashed Quickshell (SIGSEGV in Qt's delegate
// incubation, 2026-10-25). Pins live in ~/.config/overtake/start-pinned.txt.
Item {
  id: root

  required property Item anchorItem
  property Item osAnchorItem: anchorItem
  property QtObject bar: null
  property var taskbarPinned: []
  signal toggleTaskbarPin(string id)
  signal moveTaskbar(string to)
  property string taskbarSection: ""   // the bar section the taskbar is in

  property bool open: false
  property string mode: "start"  // "start", "quick" or "os"
  property bool popoutSwitchClosing: false

  property string query: ""
  property bool showAll: false
  property int cursor: 0
  property bool powerOpen: false
  property var contextApp: null
  property point contextPos: Qt.point(0, 0)

  // File browser: the folder shown, and the folders to go Back to.
  property string filesPath: ""
  property var filesHistory: []

  readonly property color fg: Commons.Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property string home: Quickshell.env("HOME")

  // which: "start", "quick", "os", "all" (Start on All apps) or "files" (on Home).
  function show(which) {
    var target = which === "quick" || which === "os" ? which : "start"
    if (open && mode === target && which !== "all" && which !== "files") { close(); return }
    mode = target
    query = ""
    showAll = which === "all"
    cursor = 0
    powerOpen = false
    contextApp = null
    filesPath = which === "files" ? home : ""
    filesHistory = []
    open = true
  }
  function close() { open = false }
  function closeForPopoutSwitch() {
    popoutSwitchClosing = true
    close()
    Qt.callLater(function() { root.popoutSwitchClosing = false })
  }

  function run(command) {
    Quickshell.execDetached(["sh", "-c", command])
    close()
  }

  function launch(app) {
    if (!app || !app.id) return
    Quickshell.execDetached(["uwsm-app", "--", "gtk-launch", app.id + ".desktop"])
    close()
  }

  function openPath(path) {
    Quickshell.execDetached(["uwsm-app", "--", "xdg-open", path])
    close()
  }

  // ---------- Apps (plain copies) ----------
  function iconSource(name) {
    var source = name ? Quickshell.iconPath(name, true) : ""
    return source || Quickshell.iconPath("application-x-executable", true)
  }

  readonly property var apps: (DesktopEntries.applications.values || [])
    .filter(function(e) { return e && !e.noDisplay && e.name })
    .map(function(e) {
      return {
        id: String(e.id), name: String(e.name), generic: String(e.genericName || ""),
        icon: root.iconSource(e.icon),
        extra: [e.genericName || "", (e.keywords || []).join(" "), e.comment || ""].join(" ").toLowerCase()
      }
    })
    .sort(function(a, b) { return a.name.toLowerCase().localeCompare(b.name.toLowerCase()) })

  readonly property var appsById: {
    var out = {}
    apps.forEach(function(a) { out[a.id] = a })
    return out
  }

  readonly property var defaultPins: [
    "chromium", "org.gnome.Nautilus", "foot", "obsidian", "libreoffice-writer", "libreoffice-calc",
    "libreoffice-impress", "mpv", "imv", "org.gnome.Papers", "localsend", "btop"
  ]
  property var pinIds: defaultPins

  FileView {
    id: pinFile
    path: root.home + "/.config/overtake/start-pinned.txt"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      root.pinIds = text().split("\n").map(function(l) { return l.trim() })
        .filter(function(l) { return l && l.charAt(0) !== "#" })
    }
    onLoadFailed: root.pinIds = root.defaultPins
  }

  // Desktop icons (Add to desktop / Remove from desktop in an app's menu).
  property string desktopIconsText: ""
  FileView {
    id: desktopIconsFile
    path: root.home + "/.config/overtake/desktop-icons.txt"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.desktopIconsText = text()
  }
  function toggleDesktop(app) {
    if (!app) return
    var next = DesktopList.has(desktopIconsText, app.id)
      ? DesktopList.remove(desktopIconsText, app.id)
      : DesktopList.add(desktopIconsText, app.id, app.name)
    desktopIconsText = next
    desktopIconsFile.setText(next)
  }

  readonly property var pinnedApps: pinIds.map(function(id) { return appsById[id] }).filter(function(a) { return !!a })

  function isPinned(app) { return !!app && pinIds.indexOf(app.id) !== -1 }

  function togglePin(app) {
    if (!app) return
    var next = pinIds.slice(), i = next.indexOf(app.id)
    if (i === -1) next.push(app.id)
    else next.splice(i, 1)
    pinIds = next
    pinFile.setText("# Start menu pins, one desktop entry id per line (managed by the Start menu).\n" + next.join("\n") + "\n")
  }

  // Search: name prefix, then word prefix, then anywhere in the name,
  // generic name, keywords or comment; ties alphabetical.
  readonly property var results: {
    var q = query.trim().toLowerCase()
    if (!q) return []
    var scored = []
    for (var i = 0; i < apps.length; i++) {
      var a = apps[i], name = a.name.toLowerCase(), score = 0
      if (name.indexOf(q) === 0) score = 4
      else if ((" " + name).indexOf(" " + q) !== -1) score = 3
      else if (name.indexOf(q) !== -1) score = 2
      else if (a.extra.indexOf(q) !== -1) score = 1
      if (score) scored.push({ app: a, score: score })
    }
    scored.sort(function(x, y) { return y.score - x.score || x.app.name.localeCompare(y.app.name) })
    return scored.slice(0, 40).map(function(s) { return s.app })
  }

  readonly property string page: query.trim() ? "search" : (filesPath ? "files" : (showAll ? "all" : "home"))
  onPageChanged: cursor = 0
  onQueryChanged: cursor = 0

  // What Up/Down/Enter act on.
  readonly property var keyList: page === "search" ? results : (page === "all" ? apps : (page === "home" ? pinnedApps : []))

  function moveCursor(step) {
    var n = keyList.length
    if (n > 0) cursor = Math.max(0, Math.min(n - 1, cursor + step))
  }

  // ---------- Folders and files ----------
  readonly property var folders: [
    { name: "Home", path: home, icon: "user-home" },
    { name: "Documents", path: home + "/Documents", icon: "folder-documents" },
    { name: "Downloads", path: home + "/Downloads", icon: "folder-download" },
    { name: "Pictures", path: home + "/Pictures", icon: "folder-pictures" },
    { name: "Music", path: home + "/Music", icon: "folder-music" },
    { name: "Videos", path: home + "/Videos", icon: "folder-videos" }
  ]

  function folderIcon(icon) {
    return Quickshell.iconPath(icon, true) || Quickshell.iconPath("folder", true)
  }

  function openFolder(path) {
    if (filesPath) filesHistory = filesHistory.concat([filesPath])
    filesPath = path
    cursor = 0
  }

  function filesBack() {
    if (filesHistory.length === 0) { filesPath = ""; return }
    var h = filesHistory.slice()
    filesPath = h.pop()
    filesHistory = h
  }

  function filesUp() {
    if (!filesPath || filesPath === "/") return
    var parent = filesPath.replace(/\/[^\/]+\/?$/, "") || "/"
    openFolder(parent)
  }

  function prettyPath(path) {
    return path.indexOf(home) === 0 ? "Home" + path.slice(home.length) : path
  }

  readonly property var suffixIcons: ({
    pdf: "application-pdf", png: "image-x-generic", jpg: "image-x-generic", jpeg: "image-x-generic",
    gif: "image-x-generic", webp: "image-x-generic", svg: "image-svg+xml", mp3: "audio-x-generic",
    flac: "audio-x-generic", ogg: "audio-x-generic", wav: "audio-x-generic", mp4: "video-x-generic",
    mkv: "video-x-generic", webm: "video-x-generic", mov: "video-x-generic", txt: "text-x-generic",
    md: "text-x-generic", doc: "x-office-document", docx: "x-office-document", odt: "x-office-document",
    xls: "x-office-spreadsheet", xlsx: "x-office-spreadsheet", ods: "x-office-spreadsheet", csv: "x-office-spreadsheet",
    ppt: "x-office-presentation", pptx: "x-office-presentation", odp: "x-office-presentation",
    zip: "package-x-generic", gz: "package-x-generic", xz: "package-x-generic", tar: "package-x-generic",
    sh: "text-x-script", py: "text-x-script", js: "text-x-script", html: "text-html", json: "text-x-generic"
  })

  function fileIcon(isDir, suffix) {
    if (isDir) return Quickshell.iconPath("folder", true)
    var name = suffixIcons[String(suffix).toLowerCase()] || "text-x-generic"
    return Quickshell.iconPath(name, true) || Quickshell.iconPath("text-x-generic", true)
  }

  function fileWhen(date) {
    var d = new Date(date), now = new Date()
    if (d.toDateString() === now.toDateString()) return Qt.formatTime(d, "h:mm AP")
    return Qt.formatDate(d, d.getFullYear() === now.getFullYear() ? "MMM d" : "MMM d, yyyy")
  }

  function fileSize(bytes) {
    if (bytes < 1024) return bytes + " B"
    if (bytes < 1048576) return Math.round(bytes / 1024) + " KB"
    if (bytes < 1073741824) return (bytes / 1048576).toFixed(1) + " MB"
    return (bytes / 1073741824).toFixed(1) + " GB"
  }

  // "Recommended": recently opened files (GTK's recently-used list), newest
  // first, skipping temporary ones.
  property var recentFiles: []
  FileView {
    path: root.home + "/.local/share/recently-used.xbel"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      var out = []
      var re = /<bookmark href="([^"]+)"[^>]*modified="([^"]+)"[\s\S]*?<mime:mime-type type="([^"]+)"/g
      var m
      var body = text()
      while ((m = re.exec(body)) !== null) {
        if (m[1].indexOf("file://") !== 0) continue
        var path = decodeURIComponent(m[1].replace(/^file:\/\//, ""))
        if (path.indexOf("/tmp/") === 0) continue
        out.push({ path: path, name: path.split("/").pop(), modified: m[2], mime: m[3] })
      }
      out.sort(function(a, b) { return a.modified < b.modified ? 1 : -1 })
      root.recentFiles = out.slice(0, 6)
    }
  }

  function recentWhen(iso) {
    var d = new Date(iso), now = new Date()
    if (d.toDateString() === now.toDateString()) return "Today, " + Qt.formatTime(d, "h:mm AP")
    var y = new Date(now.getTime() - 86400000)
    if (d.toDateString() === y.toDateString()) return "Yesterday"
    return Qt.formatDate(d, "MMM d")
  }

  function mimeIcon(mime) {
    return Quickshell.iconPath(mime.replace("/", "-"), true)
      || Quickshell.iconPath(mime.split("/")[0] + "-x-generic", true)
      || Quickshell.iconPath("text-x-generic", true)
  }

  readonly property string userName: {
    var name = Quickshell.env("USER") || "User"
    return name.charAt(0).toUpperCase() + name.slice(1)
  }

  // Shown in the Super+X menu (right-click Start).
  readonly property var quickItems: [
    { glyph: "", label: "Installed apps", command: "omarchy-menu toggle remove" },
    { glyph: "", label: "System", command: "omarchy-launch-about" },
    { glyph: "", label: "Network connections", command: "omarchy-menu toggle setup.network" },
    { glyph: "", label: "Terminal", command: "uwsm-app -- omarchy-launch-terminal" },
    { glyph: "", label: "Task Manager", command: "omarchy-launch-tui btop" },
    { glyph: "", label: "Settings", command: "overtake settings" },
    { glyph: "", label: "File Explorer", command: "uwsm-app -- nautilus --new-window" },
    { glyph: "", label: "Search", start: true },
    { glyph: "", label: "Run", command: "omarchy-menu toggle apps" },
    { separator: true },
    { glyph: "", label: "Lock", command: "omarchy-system-lock" },
    { glyph: "", label: "Sleep", command: "systemctl suspend" },
    { glyph: "", label: "Sign out", command: "omarchy-system-logout" },
    { glyph: "", label: "Restart", command: "omarchy-system-reboot" },
    { glyph: "", label: "Shut down", command: "omarchy-system-shutdown" },
    { separator: true },
    { glyph: "", label: root.taskbarSection === "center" ? "Move taskbar to the left" : "Center the taskbar",
      taskbar: root.taskbarSection === "center" ? "left" : "center" },
    { glyph: "", label: "Desktop", command: "overtake show-desktop" }
  ]

  readonly property var powerItems: [
    { glyph: "", label: "Lock", command: "omarchy-system-lock" },
    { glyph: "", label: "Sleep", command: "systemctl suspend" },
    { glyph: "", label: "Sign out", command: "omarchy-system-logout" },
    { glyph: "", label: "Restart", command: "omarchy-system-reboot" },
    { glyph: "", label: "Shut down", command: "omarchy-system-shutdown" }
  ]

  // ---------- Start menu ----------
  KeyboardPanel {
    id: startPanel
    anchorItem: root.anchorItem
    owner: root
    bar: root.bar
    open: root.open && root.mode === "start"
    focusTarget: search
    contentWidth: fittedContentWidth(Style.space(640))
    contentHeight: fittedContentHeight(Style.space(720))

    Item {
      id: startBody
      anchors.fill: parent

      // Clicks on empty space close the power and right-click menus.
      MouseArea {
        anchors.fill: parent
        onClicked: { root.powerOpen = false; root.contextApp = null }
      }

      TextField {
        id: search
        anchors.top: parent.top
        width: parent.width
        placeholderText: "Type here to search apps"
        text: root.query
        onTextChanged: root.query = text
        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          var cols = root.page === "home" ? 6 : 1
          if (event.key === Qt.Key_Escape) {
            if (root.page === "files") root.filesBack()
            else if (root.page === "all") root.showAll = false
            else root.close()
            event.accepted = true
          }
          else if (event.key === Qt.Key_Backspace && !text && root.page === "files") { root.filesUp(); event.accepted = true }
          else if (event.key === Qt.Key_Down) { root.moveCursor(cols); event.accepted = true }
          else if (event.key === Qt.Key_Up) { root.moveCursor(-cols); event.accepted = true }
          else if (event.key === Qt.Key_Right && cols > 1 && !text) { root.moveCursor(1); event.accepted = true }
          else if (event.key === Qt.Key_Left && cols > 1 && !text) { root.moveCursor(-1); event.accepted = true }
          else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.launch(root.keyList[root.cursor]); event.accepted = true
          }
        }
        Connections {
          target: root
          function onOpenChanged() { if (root.open) search.text = "" }
        }
      }

      Loader {
        id: pageLoader
        anchors.top: search.bottom
        anchors.topMargin: Style.space(12)
        anchors.bottom: footer.top
        anchors.bottomMargin: Style.space(8)
        width: parent.width
        sourceComponent: root.page === "search" ? searchPage
          : root.page === "all" ? allPage
          : root.page === "files" ? filesPage
          : homePage
      }

      // Footer: user on the left; Files, Settings and Power on the right.
      Item {
        id: footer
        anchors.bottom: parent.bottom
        width: parent.width
        height: Style.space(48)

        Rectangle {
          anchors.top: parent.top
          width: parent.width
          height: 1
          color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.12)
        }

        Row {
          anchors.verticalCenter: parent.verticalCenter
          anchors.left: parent.left
          anchors.leftMargin: Style.space(8)
          spacing: Style.space(10)

          Rectangle {
            width: Style.space(30)
            height: width
            radius: width / 2
            color: Commons.Color.accent
            Text {
              anchors.centerIn: parent
              textFormat: Text.PlainText
              text: root.userName.charAt(0)
              color: Commons.Color.background
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
            }
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: root.userName
            color: root.fg
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }
        }

        Row {
          anchors.verticalCenter: parent.verticalCenter
          anchors.right: parent.right
          spacing: Style.space(4)

          IconButton { glyph: ""; tip: "File Explorer"; onClicked: root.run("uwsm-app -- nautilus --new-window") }
          IconButton { glyph: ""; tip: "Settings"; onClicked: root.run("overtake settings") }
          IconButton {
            glyph: ""
            tip: "Power"
            onClicked: { root.powerOpen = !root.powerOpen; root.contextApp = null }
          }
        }
      }

      // Power options, above the power button.
      Rectangle {
        visible: root.powerOpen
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.bottomMargin: footer.height + Style.space(4)
        width: Style.space(180)
        height: powerColumn.implicitHeight + Style.space(12)
        radius: Style.space(8)
        color: Commons.Color.popups.background
        border.width: 1
        border.color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.2)

        Column {
          id: powerColumn
          anchors.fill: parent
          anchors.margins: Style.space(6)
          Repeater {
            model: root.powerItems
            MenuRow {
              required property var modelData
              width: powerColumn.width
              glyph: modelData.glyph
              label: modelData.label
              onClicked: root.run(modelData.command)
            }
          }
        }
      }

      // Right-click menu for an app.
      Rectangle {
        visible: root.contextApp !== null
        x: Math.min(root.contextPos.x, parent.width - width)
        y: Math.min(root.contextPos.y, parent.height - height)
        width: Style.space(210)
        height: contextColumn.implicitHeight + Style.space(12)
        radius: Style.space(8)
        color: Commons.Color.popups.background
        border.width: 1
        border.color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.2)

        Column {
          id: contextColumn
          anchors.fill: parent
          anchors.margins: Style.space(6)
          MenuRow {
            width: contextColumn.width
            glyph: ""
            label: "Open"
            onClicked: root.launch(root.contextApp)
          }
          MenuRow {
            width: contextColumn.width
            glyph: ""
            label: root.isPinned(root.contextApp) ? "Unpin from Start" : "Pin to Start"
            onClicked: { root.togglePin(root.contextApp); root.contextApp = null }
          }
          MenuRow {
            width: contextColumn.width
            glyph: ""
            label: root.contextApp && root.taskbarPinned.indexOf(root.contextApp.id) !== -1 ? "Unpin from taskbar" : "Pin to taskbar"
            onClicked: { root.toggleTaskbarPin(root.contextApp.id); root.contextApp = null }
          }
          MenuRow {
            width: contextColumn.width
            glyph: "\uf108"
            label: root.contextApp && DesktopList.has(root.desktopIconsText, root.contextApp.id) ? "Remove from desktop" : "Add to desktop"
            onClicked: { root.toggleDesktop(root.contextApp); root.contextApp = null }
          }
        }
      }
    }
  }

  function openContext(app, pos) {
    powerOpen = false
    contextPos = pos
    contextApp = app
  }

  // ---------- Pages ----------
  Component {
    id: homePage

    Flickable {
      clip: true
      contentHeight: homeColumn.implicitHeight
      boundsBehavior: Flickable.StopAtBounds

      Column {
        id: homeColumn
        width: parent.width
        spacing: Style.space(8)

        SectionHeader {
          title: "Pinned"
          action: "All apps  ›"
          onActionClicked: root.showAll = true
        }

        Grid {
          id: pinGrid
          columns: 6
          width: parent.width
          readonly property real cellW: Math.floor(width / 6)
          Repeater {
            model: root.pinnedApps.slice(0, 18)
            AppTile {
              required property var modelData
              required property int index
              width: pinGrid.cellW
              app: modelData
              current: root.cursor === index
            }
          }
        }

        SectionHeader {
          title: "Folders"
          action: "File Explorer  ›"
          onActionClicked: root.run("uwsm-app -- nautilus --new-window")
        }

        Grid {
          columns: 6
          width: parent.width
          Repeater {
            model: root.folders
            Item {
              required property var modelData
              width: parent.width / 6
              height: Style.space(64)

              Rectangle {
                anchors.fill: parent
                anchors.margins: Style.space(3)
                radius: Style.space(6)
                color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, folderArea.containsMouse ? 0.12 : 0)
              }
              Image {
                id: folderImg
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: Style.space(8)
                width: Style.space(28)
                height: width
                sourceSize.width: width * 2
                sourceSize.height: height * 2
                source: root.folderIcon(modelData.icon)
                asynchronous: true
              }
              Text {
                anchors.top: folderImg.bottom
                anchors.topMargin: Style.space(4)
                anchors.horizontalCenter: parent.horizontalCenter
                textFormat: Text.PlainText
                text: modelData.name
                color: root.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
              MouseArea {
                id: folderArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.openFolder(modelData.path)
              }
            }
          }
        }

        SectionHeader {
          visible: root.recentFiles.length > 0
          title: "Recommended"
        }

        Grid {
          columns: 2
          width: parent.width
          Repeater {
            model: root.recentFiles
            Item {
              required property var modelData
              width: parent.width / 2
              height: Style.space(48)

              Rectangle {
                anchors.fill: parent
                anchors.margins: Style.space(2)
                radius: Style.space(6)
                color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, recentArea.containsMouse ? 0.12 : 0)
              }
              Row {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: Style.space(10)
                spacing: Style.space(10)
                Image {
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(28)
                  height: width
                  sourceSize.width: width * 2
                  sourceSize.height: height * 2
                  source: root.mimeIcon(modelData.mime)
                  asynchronous: true
                }
                Column {
                  anchors.verticalCenter: parent.verticalCenter
                  Text {
                    width: Style.space(230)
                    textFormat: Text.PlainText
                    text: modelData.name
                    elide: Text.ElideMiddle
                    color: root.fg
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                  }
                  Text {
                    textFormat: Text.PlainText
                    text: root.recentWhen(modelData.modified)
                    color: root.fg
                    opacity: 0.55
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }
              }
              MouseArea {
                id: recentArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.openPath(modelData.path)
              }
            }
          }
        }
      }
    }
  }

  Component {
    id: allPage
    AppListPage { title: "All apps"; action: "‹  Back"; apps: root.apps; onActionClicked: root.showAll = false }
  }

  Component {
    id: searchPage
    AppListPage {
      title: root.results.length ? "Best match" : "No apps match “" + root.query.trim() + "”"
      apps: root.results
      showGeneric: true
    }
  }

  Component {
    id: filesPage

    Item {
      // Header: Back, Up, the folder's path, and Open in File Explorer.
      Item {
        id: filesHeader
        width: parent.width
        height: Style.space(30)

        Row {
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(6)
          SmallButton { label: root.filesHistory.length ? "‹  Back" : "‹  Start"; onClicked: root.filesBack() }
          SmallButton { label: "↑  Up"; visible: root.filesPath !== "/"; onClicked: root.filesUp() }
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          anchors.horizontalCenter: parent.horizontalCenter
          width: parent.width - Style.space(330)
          horizontalAlignment: Text.AlignHCenter
          textFormat: Text.PlainText
          text: root.prettyPath(root.filesPath)
          elide: Text.ElideLeft
          color: root.fg
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: true
        }

        SmallButton {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          label: "Open in File Explorer"
          onClicked: { Quickshell.execDetached(["uwsm-app", "--", "nautilus", "--new-window", root.filesPath]); root.close() }   // argv: a folder name never reaches a shell
        }
      }

      FolderListModel {
        id: folderModel
        folder: "file://" + root.filesPath
        showDirsFirst: true
        showHidden: false
        showDotAndDotDot: false
        sortCaseSensitive: false
      }

      Text {
        visible: folderModel.status === FolderListModel.Ready && folderModel.count === 0
        anchors.centerIn: parent
        textFormat: Text.PlainText
        text: "This folder is empty."
        color: root.fg
        opacity: 0.6
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }

      ListView {
        id: fileList
        anchors.top: filesHeader.bottom
        anchors.topMargin: Style.space(8)
        anchors.bottom: parent.bottom
        width: parent.width
        clip: true
        model: folderModel
        boundsBehavior: Flickable.StopAtBounds

        delegate: Item {
          required property string fileName
          required property string filePath
          required property bool fileIsDir
          required property string fileSuffix
          required property var fileModified
          required property var fileSize
          width: fileList.width
          height: Style.space(36)

          Rectangle {
            anchors.fill: parent
            radius: Style.space(6)
            color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, fileArea.containsMouse ? 0.12 : 0)
          }
          Row {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: Style.space(10)
            spacing: Style.space(10)
            Image {
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(22)
              height: width
              sourceSize.width: width * 2
              sourceSize.height: height * 2
              source: root.fileIcon(fileIsDir, fileSuffix)
              asynchronous: true
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              width: fileList.width - Style.space(230)
              textFormat: Text.PlainText
              text: fileName
              elide: Text.ElideMiddle
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
            anchors.rightMargin: Style.space(10)
            textFormat: Text.PlainText
            text: root.fileWhen(fileModified) + (fileIsDir ? "" : "   " + root.fileSize(Number(fileSize)))
            color: root.fg
            opacity: 0.55
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
          MouseArea {
            id: fileArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: fileIsDir ? root.openFolder(filePath) : root.openPath(filePath)
          }
        }
      }
    }
  }

  // ---------- Building blocks ----------
  component SectionHeader: Item {
    id: header
    property string title: ""
    property string action: ""
    signal actionClicked()
    width: parent ? parent.width : 0
    height: visible ? Style.space(30) : 0

    Text {
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: header.title
      color: root.fg
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      font.bold: true
    }
    SmallButton {
      visible: header.action !== ""
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      label: header.action
      onClicked: header.actionClicked()
    }
  }

  component AppTile: Item {
    id: tile
    property var app: null
    property bool current: false
    height: Style.space(92)

    Rectangle {
      anchors.fill: parent
      anchors.margins: Style.space(3)
      radius: Style.space(6)
      color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, tileArea.containsMouse ? 0.12 : (tile.current ? 0.08 : 0))
    }
    Image {
      id: tileIcon
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.top: parent.top
      anchors.topMargin: Style.space(12)
      width: Style.space(36)
      height: width
      sourceSize.width: width * 2
      sourceSize.height: height * 2
      source: tile.app ? tile.app.icon : ""
      asynchronous: true
    }
    Text {
      anchors.top: tileIcon.bottom
      anchors.topMargin: Style.space(6)
      anchors.horizontalCenter: parent.horizontalCenter
      width: parent.width - Style.space(10)
      horizontalAlignment: Text.AlignHCenter
      textFormat: Text.PlainText
      text: tile.app ? tile.app.name : ""
      elide: Text.ElideRight
      maximumLineCount: 2
      wrapMode: Text.WordWrap
      color: root.fg
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
    MouseArea {
      id: tileArea
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      cursorShape: Qt.PointingHandCursor
      onClicked: function(mouse) {
        if (mouse.button === Qt.RightButton) root.openContext(tile.app, mapToItem(startBody, mouse.x, mouse.y))
        else root.launch(tile.app)
      }
    }
  }

  component AppListPage: Item {
    id: listPage
    property string title: ""
    property string action: ""
    property var apps: []
    property bool showGeneric: false
    signal actionClicked()

    SectionHeader {
      id: listHeader
      width: parent.width
      title: listPage.title
      action: listPage.action
      onActionClicked: listPage.actionClicked()
    }

    ListView {
      id: appList
      anchors.top: listHeader.bottom
      anchors.topMargin: Style.space(6)
      anchors.bottom: parent.bottom
      width: parent.width
      clip: true
      model: listPage.apps
      boundsBehavior: Flickable.StopAtBounds

      Connections {
        target: root
        function onCursorChanged() { appList.positionViewAtIndex(root.cursor, ListView.Contain) }
      }

      delegate: Item {
        required property var modelData
        required property int index
        width: appList.width
        height: Style.space(40)

        Rectangle {
          anchors.fill: parent
          radius: Style.space(6)
          color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, rowArea.containsMouse ? 0.12 : (root.cursor === index ? 0.08 : 0))
        }
        Row {
          anchors.verticalCenter: parent.verticalCenter
          anchors.left: parent.left
          anchors.leftMargin: Style.space(10)
          spacing: Style.space(12)
          Image {
            width: Style.space(26)
            height: width
            sourceSize.width: width * 2
            sourceSize.height: height * 2
            source: modelData.icon
            asynchronous: true
          }
          Column {
            anchors.verticalCenter: parent.verticalCenter
            Text {
              textFormat: Text.PlainText
              text: modelData.name
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }
            Text {
              visible: listPage.showGeneric && modelData.generic !== ""
              textFormat: Text.PlainText
              text: modelData.generic
              color: root.fg
              opacity: 0.55
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }
        MouseArea {
          id: rowArea
          anchors.fill: parent
          hoverEnabled: true
          acceptedButtons: Qt.LeftButton | Qt.RightButton
          cursorShape: Qt.PointingHandCursor
          onClicked: function(mouse) {
            if (mouse.button === Qt.RightButton) root.openContext(modelData, mapToItem(startBody, mouse.x, mouse.y))
            else root.launch(modelData)
          }
        }
      }
    }
  }

  // ---------- Overtake Mode (the button next to Start) ----------
  readonly property var osModes: [
    { name: "Overtake", current: true, glyph: "\ue900", glyphFont: "omarchy",
      detail: "Taskbar, Start menu, window buttons and familiar shortcuts" },
    { name: "Omarchy", current: false, glyph: "\uf00a", command: "overtake off",
      detail: "Omarchy's own desktop: tiling windows, top bar, keyboard first" }
  ]

  KeyboardPanel {
    id: osPanel
    anchorItem: root.osAnchorItem
    owner: root
    bar: root.bar
    open: root.open && root.mode === "os"
    focusTarget: osKeys
    contentWidth: Style.space(330)
    contentHeight: fittedContentHeight(osColumn.implicitHeight)

    PanelKeyCatcher {
      id: osKeys
      anchors.fill: parent
      onCloseRequested: root.close()

      Column {
        id: osColumn
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Style.space(4)

        Text {
          bottomPadding: Style.space(4)
          textFormat: Text.PlainText
          text: "Overtake Mode"
          color: root.fg
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: true
        }

        Repeater {
          model: root.osModes
          Item {
            required property var modelData
            width: osColumn.width
            height: Style.space(56)

            Rectangle {
              anchors.fill: parent
              radius: Style.space(6)
              color: modelData.current ? Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.18)
                                       : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, osArea.containsMouse ? 0.12 : 0.05)
              border.width: modelData.current ? 1 : 0
              border.color: Commons.Color.accent
            }
            Row {
              anchors.verticalCenter: parent.verticalCenter
              anchors.left: parent.left
              anchors.leftMargin: Style.space(12)
              spacing: Style.space(12)
              Text {
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(20)
                textFormat: Text.PlainText
                text: modelData.glyph
                color: root.fg
                font.family: modelData.glyphFont || root.fontFamily
                font.pixelSize: Style.font.body + 4
              }
              Column {
                anchors.verticalCenter: parent.verticalCenter
                Text {
                  textFormat: Text.PlainText
                  text: modelData.name + (modelData.current ? "   \u2713 current" : "")
                  color: root.fg
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  font.bold: true
                }
                Text {
                  width: osColumn.width - Style.space(60)
                  textFormat: Text.PlainText
                  text: modelData.detail
                  wrapMode: Text.WordWrap
                  color: root.fg
                  opacity: 0.65
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }
            }
            MouseArea {
              id: osArea
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: modelData.current ? root.close() : root.run(modelData.command)
            }
          }
        }

        Text {
          topPadding: Style.space(4)
          textFormat: Text.PlainText
          text: "Shortcut: Super + Ctrl + Shift + W"
          color: root.fg
          opacity: 0.5
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }

  // ---------- Super+X quick links ----------
  KeyboardPanel {
    id: quickPanel
    anchorItem: root.anchorItem
    owner: root
    bar: root.bar
    open: root.open && root.mode === "quick"
    focusTarget: quickKeys
    contentWidth: Style.space(250)
    contentHeight: fittedContentHeight(quickColumn.implicitHeight)

    PanelKeyCatcher {
      id: quickKeys
      anchors.fill: parent
      onCloseRequested: root.close()

      Column {
        id: quickColumn
        anchors.left: parent.left
        anchors.right: parent.right

        Repeater {
          model: root.quickItems
          Item {
            required property var modelData
            width: quickColumn.width
            height: modelData.separator ? Style.space(9) : Style.space(30)

            Rectangle {
              visible: !!modelData.separator
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width
              height: 1
              color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.12)
            }

            MenuRow {
              visible: !modelData.separator
              anchors.fill: parent
              glyph: modelData.glyph || ""
              label: modelData.label || ""
              onClicked: {
                if (modelData.start) root.show("start")
                else if (modelData.taskbar) { root.moveTaskbar(modelData.taskbar); root.close() }
                else root.run(modelData.command)
              }
            }
          }
        }
      }
    }
  }

  component MenuRow: Item {
    id: menuRow
    property string glyph: ""
    property string label: ""
    signal clicked()
    height: Style.space(30)

    Rectangle {
      anchors.fill: parent
      radius: Style.space(4)
      color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, rowArea.containsMouse ? 0.12 : 0)
    }
    Row {
      anchors.verticalCenter: parent.verticalCenter
      anchors.left: parent.left
      anchors.leftMargin: Style.space(8)
      spacing: Style.space(10)
      Text {
        width: Style.space(16)
        textFormat: Text.PlainText
        text: menuRow.glyph
        color: root.fg
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }
      Text {
        textFormat: Text.PlainText
        text: menuRow.label
        color: root.fg
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }
    }
    MouseArea {
      id: rowArea
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: menuRow.clicked()
    }
  }

  component IconButton: Item {
    id: iconButton
    property string glyph: ""
    property string tip: ""
    signal clicked()
    width: Style.space(38)
    height: Style.space(38)

    Rectangle {
      anchors.fill: parent
      radius: Style.space(6)
      color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, iconArea.containsMouse ? 0.12 : 0)
    }
    Text {
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: iconButton.glyph
      color: root.fg
      font.family: root.fontFamily
      font.pixelSize: Style.font.body + 2
    }
    MouseArea {
      id: iconArea
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: iconButton.clicked()
    }
  }

  component SmallButton: Item {
    id: smallButton
    property string label: ""
    signal clicked()
    width: smallText.implicitWidth + Style.space(20)
    height: Style.space(26)

    Rectangle {
      anchors.fill: parent
      radius: Style.space(4)
      color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, smallArea.containsMouse ? 0.16 : 0.08)
    }
    Text {
      id: smallText
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: smallButton.label
      color: root.fg
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
    MouseArea {
      id: smallArea
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: smallButton.clicked()
    }
  }
}
