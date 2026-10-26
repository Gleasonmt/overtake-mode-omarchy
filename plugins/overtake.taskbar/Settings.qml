import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Settings window for Overtake Mode (Start > Settings, Super+I,
// `overtake settings [page]`). A sidebar of categories; each page is cards
// of settings that read and change Omarchy's own state through its commands.
// A few deep tasks (picking a Wi-Fi network, pairing Bluetooth) open
// Omarchy's panels for those, which are the GUI that already exists.
//
// Row types: toggle (state: exit 0 = on), choice (options + current + set
// with {} for the value), info (value from a command), link (runs a command),
// list (one row per output line "<key>\t<state>\t<title>"; states map each
// state to its detail, button and argv, which gets the key, checked against
// keyPattern, appended; nothing from the line itself is run), themes,
// battery (each battery device's alert levels, from BatteryAlerts).
Item {
  id: root

  property bool open: false
  property string page: "system"
  property string query: ""
  property var batteryAlerts: null

  function show(which) {
    if (which && pageById(which)) page = which
    query = ""
    open = true
  }

  readonly property color fg: Commons.Color.foreground
  readonly property color bg: Commons.Color.background
  readonly property color accent: Commons.Color.accent
  readonly property string fontFamily: Style.font.family
  readonly property string user: {
    var name = Quickshell.env("USER") || "User"
    return name.charAt(0).toUpperCase() + name.slice(1)
  }

  function sh(command) { Quickshell.execDetached(["sh", "-c", command]) }

  readonly property var pages: [
    { id: "system", name: "System", glyph: "", sections: [
      { title: "Display", rows: [
        { type: "toggle", title: "Night light", detail: "Warmer colours to help you sleep",
          state: "omarchy-toggle-nightlight --status | jq -e .enabled", on: "omarchy-toggle-nightlight", off: "omarchy-toggle-nightlight" },
        { type: "info", title: "Displays", value: "hyprctl monitors -j | jq -r 'map(\"\\(.description | split(\" \")[0:2] | join(\" \")) \\(.width)x\\(.height) @ \\(.refreshRate | floor)Hz\") | join(\", \")'" },
        { type: "link", title: "Advanced display settings", detail: "Resolution, scaling and arrangement (opens the config file)", run: "omarchy-launch-config-editor ~/.config/hypr/monitors.lua" }
      ]},
      { title: "Sound", rows: [
        { type: "info", title: "Output", value: "wpctl inspect @DEFAULT_AUDIO_SINK@ | sed -n 's/.*node.description = \"\\(.*\\)\"/\\1/p' | head -1" },
        { type: "link", title: "Volume and devices", detail: "Output, input and app volume", run: "omarchy-shell omarchy.audio open" }
      ]},
      { title: "Notifications", rows: [
        { type: "toggle", title: "Do not disturb", detail: "Silence notification pop-ups",
          state: "[ \"$(omarchy-shell notifications isDnd)\" = on ]", on: "omarchy-shell notifications setDnd true", off: "omarchy-shell notifications setDnd false" },
        { type: "link", title: "Notification center", detail: "Notifications that have left the screen, and each app's settings (the bell on the taskbar)", run: "omarchy-shell overtake.notification-center open" }
      ]},
      { title: "Power & battery", rows: [
        { type: "link", title: "Power & battery", detail: "Power mode, battery and the alerts for each device's battery", run: "overtake settings battery" }
      ]},
      { title: "About", rows: [
        { type: "info", title: "Device name", value: "cat /etc/hostname" },
        { type: "info", title: "Model", value: "cat /sys/class/dmi/id/sys_vendor /sys/class/dmi/id/product_name | paste -sd ' '" },
        { type: "info", title: "Processor", value: "sed -n 's/^model name\\s*: //p' /proc/cpuinfo | head -1" },
        { type: "info", title: "Memory", value: "free -h | awk '/Mem:/{print $2}'" },
        { type: "info", title: "System", value: "echo Omarchy $(omarchy-version)" },
        { type: "link", title: "More about this PC", run: "omarchy-launch-about" }
      ]}
    ]},
    { id: "battery", name: "Power & battery", glyph: "\uf240", sections: [
      { title: "Power", rows: [
        { type: "choice", title: "Power mode", detail: "Balance battery life and performance",
          options: "powerprofilesctl list | sed -n 's/^[* ] *\\([a-z-]*\\):$/\\1/p'", current: "powerprofilesctl get", set: "omarchy-powerprofiles-set {}" },
        { type: "info", title: "Battery", value: "upower -i $(upower -e | grep BAT | head -1) | awk '/percentage/{p=$2} /state/{s=$2} END{print p\"  \"s}'" },
        { type: "link", title: "Battery and device charge", run: "omarchy-shell omarchy.power open" }
      ]},
      { title: "Battery alerts", rows: [
        { type: "battery", title: "Battery alerts", detail: "A notification when a device drops to its Low level, and again at Critical. Every device with a battery shows up here once connected." }
      ]}
    ]},
    { id: "screensaver", name: "Screensaver & lock", glyph: "\uf26c", sections: [
      { title: "Screensaver", rows: [
        { type: "toggle", title: "Screensaver", detail: "Show the screensaver when the computer has been idle",
          state: "overtake screensaver enabled", on: "overtake screensaver on", off: "overtake screensaver off" },
        { type: "choice", title: "Start after", detail: "How long the computer is idle before it starts",
          options: "printf '60\\n120\\n150\\n300\\n600\\n900\\n1800\\n'", current: "overtake screensaver start", set: "overtake screensaver start {}",
          labels: { "60": "1 minute", "120": "2 minutes", "150": "2½ minutes", "300": "5 minutes", "600": "10 minutes", "900": "15 minutes", "1800": "30 minutes" } },
        { type: "link", title: "Preview", detail: "Start it now (move the mouse or press a key to stop it)", run: "overtake screensaver preview" }
      ]},
      { title: "What it shows", rows: [
        { type: "info", title: "Showing", value: "overtake screensaver showing" },
        { type: "link", title: "Omarchy logo", detail: "The screensaver Omarchy comes with", run: "overtake screensaver show omarchy" },
        { type: "link", title: "Your wallpaper", detail: "Turns the wallpaper you're using now into screensaver art", run: "overtake screensaver show wallpaper" },
        { type: "link", title: "From an image…", detail: "Pick a PNG or SVG to turn into screensaver art", run: "overtake screensaver show image" },
        { type: "link", title: "Your own text…", detail: "Write or paste text or ASCII art", run: "overtake screensaver show text" }
      ]},
      { title: "Lock", rows: [
        { type: "choice", title: "Lock after", detail: "Lock the screen after the computer has been idle this long",
          options: "printf '120\\n300\\n600\\n900\\n1800\\n3600\\n0\\n'", current: "overtake screensaver lock", set: "overtake screensaver lock {}",
          labels: { "120": "2 minutes", "300": "5 minutes", "600": "10 minutes", "900": "15 minutes", "1800": "30 minutes", "3600": "1 hour", "0": "Never" } },
        { type: "link", title: "Lock now", run: "omarchy-system-lock" }
      ]}
    ]},
    { id: "bluetooth", name: "Bluetooth & devices", glyph: "", sections: [
      { title: "Bluetooth", rows: [
        { type: "toggle", title: "Bluetooth", detail: "Turning this off disconnects Bluetooth keyboards and mice",
          state: "bluetoothctl show | grep -q 'Powered: yes'", on: "rfkill unblock bluetooth; sleep 1; bluetoothctl power on", off: "bluetoothctl power off" },
        // Rows are "<address>\t<yes|no>\t<name>": the name (which the device itself
        // sets) is only ever shown; the command is built from fixed parts and
        // an address that must look like one.
        { type: "list", title: "Your devices",
          lines: "bluetoothctl devices Paired | while read -r _ mac name; do c=no; bluetoothctl info \"$mac\" | grep -q 'Connected: yes' && c=yes; printf '%s\\t%s\\t%s\\n' \"$mac\" \"$c\" \"$name\"; done",
          keyPattern: "^[0-9A-Fa-f]{2}(:[0-9A-Fa-f]{2}){5}$",
          states: { yes: { detail: "Connected", button: "Disconnect", argv: ["bluetoothctl", "disconnect"] },
                    no: { detail: "Not connected", button: "Connect", argv: ["bluetoothctl", "connect"] } } },
        { type: "link", title: "Add a device", detail: "Pair a new keyboard, mouse, headset…", run: "omarchy-shell omarchy.bluetooth open" }
      ]},
      { title: "Input", rows: [
        { type: "link", title: "Turn touchpad on or off", when: "omarchy-hw-touchpad", run: "omarchy-toggle-touchpad" },
        { type: "link", title: "Keyboard and mouse settings", detail: "Repeat rate, layout, sensitivity (opens the config file)", run: "omarchy-launch-config-editor ~/.config/hypr/input.lua" }
      ]},
      { title: "Printers", rows: [
        { type: "link", title: "Printers & scanners", when: "command -v system-config-printer", run: "uwsm-app -- system-config-printer" }
      ]}
    ]},
    { id: "network", name: "Network & internet", glyph: "", sections: [
      { title: "Status", rows: [
        { type: "info", title: "Connected to", value: "nmcli -t -f NAME,TYPE connection show --active | grep -v ':loopback' | head -1 | cut -d: -f1 | grep . || echo 'Not connected'" }
      ]},
      { title: "Wi-Fi", rows: [
        { type: "toggle", title: "Wi-Fi", state: "nmcli radio wifi | grep -q enabled", on: "nmcli radio wifi on", off: "nmcli radio wifi off" },
        { type: "link", title: "Show available networks", run: "omarchy-shell omarchy.network open" }
      ]},
      { title: "Advanced", rows: [
        { type: "choice", title: "DNS", detail: "Which DNS servers to use", options: "printf 'DHCP\\nCloudflare\\nGoogle\\n'", current: "omarchy-dns", set: "omarchy-dns {}" }
      ]}
    ]},
    { id: "personalization", name: "Personalization", glyph: "", sections: [
      { title: "Themes", rows: [ { type: "themes" } ]},
      { title: "Background", rows: [
        { type: "choice", title: "Wallpaper", detail: "Rotate through the set every 15 minutes, or follow the sun",
          options: "printf 'rotate\\nday-night\\n'", labels: { "rotate": "Rotate", "day-night": "Day & Night" },
          current: "overtake wallpaper-mode", set: "overtake wallpaper-mode {}" },
        { type: "link", title: "Next wallpaper", run: "overtake next-wallpaper" }
      ]},
      { title: "Fonts", rows: [
        { type: "choice", title: "Font", detail: "Used by the bar, menus and terminals", options: "omarchy-font-list", current: "omarchy-font-current", set: "omarchy-font-set '{}'" }
      ]},
      { title: "Desktop", rows: [
        { type: "link", title: "Desktop icons", detail: "Choose which icons show on the desktop", run: "omarchy-launch-editor ~/.config/overtake/desktop-icons.txt" }
      ]}
    ]},
    { id: "apps", name: "Apps", glyph: "", sections: [
      { title: "Apps", rows: [
        { type: "link", title: "Installed apps", detail: "Remove apps", run: "omarchy-menu toggle remove" },
        { type: "link", title: "Install apps", detail: "Add apps, web apps and more", run: "omarchy-menu toggle install" }
      ]},
      { title: "Default apps", rows: [
        { type: "choice", title: "Web browser", options: "for p in chromium:chromium chrome:google-chrome-stable brave:brave edge:microsoft-edge-stable firefox:firefox zen:zen-browser; do command -v ${p#*:} >/dev/null && echo ${p%%:*}; done", current: "omarchy-default-browser", set: "omarchy-default-browser {}" },
        { type: "choice", title: "Terminal", options: "for t in alacritty foot ghostty kitty; do command -v $t >/dev/null && echo $t; done", current: "omarchy-default-terminal", set: "omarchy-default-terminal {}" }
      ]}
    ]},
    { id: "accounts", name: "Accounts", glyph: "", sections: [
      { title: "Your info", rows: [
        { type: "info", title: "User name", value: "id -un" },
        { type: "link", title: "Change password", run: "omarchy-launch-floating-terminal-with-presentation passwd" },
        { type: "link", title: "Set up fingerprint sign-in", when: "omarchy-hw-fingerprint", run: "omarchy-launch-floating-terminal-with-presentation omarchy-setup-security-fingerprint" }
      ]}
    ]},
    { id: "time", name: "Time & language", glyph: "", sections: [
      { title: "Date & time", rows: [
        { type: "info", title: "Time zone", value: "timedatectl show -p Timezone --value" },
        { type: "toggle", title: "Set time automatically", state: "timedatectl show -p NTP --value | grep -q yes", on: "timedatectl set-ntp true", off: "timedatectl set-ntp false" }
      ]},
      { title: "Language & region", rows: [
        { type: "info", title: "Keyboard layout", value: "hyprctl devices -j | jq -r '[.keyboards[] | select(.main) | .active_keymap][0] // \"English (US)\"'" },
        { type: "link", title: "Keyboard layouts", detail: "Add or remove layouts (opens the config file)", run: "omarchy-launch-config-editor ~/.config/hypr/input.lua" }
      ]}
    ]},
    { id: "overtake", name: "Overtake Mode", glyph: "\uf0ec", sections: [
      { title: "Overtake Mode", rows: [
        { type: "link", title: "Switch to Omarchy", detail: "Go back to Omarchy's own layout (Super+Ctrl+Shift+W switches either way)", run: "overtake off" }
      ]},
      { title: "Start & taskbar", rows: [
        { type: "link", title: "Start menu pins", detail: "Or right-click any app in Start", run: "omarchy-launch-editor ~/.config/overtake/start-pinned.txt" },
        { type: "link", title: "Apps that keep their own buttons", detail: "Apps that don't get Overtake Mode's title bar", run: "omarchy-launch-editor ~/.config/overtake/no-controls.txt" }
      ]},
      { title: "Snap", rows: [
        { type: "toggle", title: "Fill free snap spots", detail: "A window opened next to snapped windows goes into the half or quarter they leave free", state: "test ! -e ~/.local/state/overtake/no-fill", on: "rm -f ~/.local/state/overtake/no-fill", off: "mkdir -p ~/.local/state/overtake && touch ~/.local/state/overtake/no-fill" }
      ]},
      { title: "Keyboard shortcuts", rows: [
        { type: "info", title: "Start", value: "echo 'Super key, or Super+S to search'" },
        { type: "info", title: "Quick links menu", value: "echo 'Super+X'" },
        { type: "info", title: "File Explorer · Settings · Run", value: "echo 'Super+E · Super+I · Super+R'" },
        { type: "info", title: "Snap windows", value: "echo 'Super+Z, Super+Left/Right, Super+Up/Down'" },
        { type: "info", title: "Show desktop · Lock · Clipboard", value: "echo 'Super+D · Super+L · Super+V'" },
        { type: "info", title: "Task Manager · Close window", value: "echo 'Ctrl+Shift+Esc · Alt+F4'" }
      ]}
    ]},
    { id: "update", name: "Update", glyph: "", sections: [
      { title: "Omarchy update", rows: [
        { type: "info", title: "Version", value: "echo $(omarchy-version) · $(omarchy-version-channel 2>/dev/null || echo stable)" },
        { type: "link", title: "Check for updates", detail: "Updates Omarchy and your apps", run: "omarchy-launch-floating-terminal-with-presentation omarchy-update" },
        { type: "link", title: "Update firmware", run: "omarchy-launch-floating-terminal-with-presentation omarchy-update-firmware" }
      ]}
    ]}
  ]

  function pageById(id) {
    for (var i = 0; i < pages.length; i++) if (pages[i].id === id) return pages[i]
    return null
  }

  // Search: every row whose title or detail matches, under one heading.
  readonly property var searchSections: {
    var q = query.trim().toLowerCase()
    if (!q) return []
    var rows = []
    pages.forEach(function(p) {
      p.sections.forEach(function(s) {
        s.rows.forEach(function(r) {
          var text = ((r.title || "") + " " + (r.detail || "") + " " + s.title + " " + p.name).toLowerCase()
          if (r.type !== "themes" && text.indexOf(q) !== -1) rows.push(r)
        })
      })
    })
    return [{ title: rows.length ? rows.length + " results" : "No settings match", rows: rows }]
  }

  readonly property var currentPage: pageById(page) || pages[0]
  readonly property var shownSections: query.trim() ? searchSections : currentPage.sections

  FloatingWindow {
    id: window
    title: "Settings"
    visible: root.open
    color: root.bg
    implicitWidth: 1000
    implicitHeight: 700
    minimumSize: Qt.size(720, 480)
    onVisibleChanged: if (!visible) root.open = false

    // Sidebar
    Item {
      id: sidebar
      width: 280
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      anchors.left: parent.left

      Column {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 6

        Row {
          spacing: 12
          height: 64
          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 48
            height: 48
            radius: 24
            color: root.accent
            Text {
              textFormat: Text.PlainText
              anchors.centerIn: parent
              text: root.user.charAt(0)
              color: root.bg
              font.family: root.fontFamily
              font.pixelSize: 20
              font.bold: true
            }
          }
          Column {
            anchors.verticalCenter: parent.verticalCenter
            Text { textFormat: Text.PlainText; text: root.user; color: root.fg; font.family: root.fontFamily; font.pixelSize: 15; font.bold: true }
            Text { textFormat: Text.PlainText; text: "Local account"; color: root.fg; opacity: 0.6; font.family: root.fontFamily; font.pixelSize: 12 }
          }
        }

        TextField {
          width: parent.width
          placeholderText: "Find a setting"
          text: root.query
          onTextChanged: root.query = text
        }

        Item { width: 1; height: 6 }

        Repeater {
          model: root.pages
          Item {
            required property var modelData
            readonly property bool current: !root.query.trim() && root.page === modelData.id
            width: parent.width
            height: 38

            Rectangle {
              anchors.fill: parent
              radius: 6
              color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, navArea.containsMouse ? 0.1 : (parent.current ? 0.08 : 0))
            }
            Rectangle {
              visible: parent.current
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              width: 3
              height: 16
              radius: 2
              color: root.accent
            }
            Row {
              anchors.verticalCenter: parent.verticalCenter
              anchors.left: parent.left
              anchors.leftMargin: 14
              spacing: 12
              Text { textFormat: Text.PlainText; width: 18; text: modelData.glyph; color: root.fg; font.family: root.fontFamily; font.pixelSize: 15 }
              Text { textFormat: Text.PlainText; text: modelData.name; color: root.fg; font.family: root.fontFamily; font.pixelSize: 14 }
            }
            MouseArea {
              id: navArea
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: { root.query = ""; root.page = modelData.id }
            }
          }
        }
      }
    }

    // Page
    Flickable {
      id: pageFlick
      anchors.left: sidebar.right
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      contentHeight: pageColumn.implicitHeight + 48
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      ScrollBar.vertical: ScrollBar {}

      Column {
        id: pageColumn
        x: 24
        y: 20
        width: pageFlick.width - 56
        spacing: 8

        Text {
          textFormat: Text.PlainText
          text: root.query.trim() ? "Search results" : root.currentPage.name
          color: root.fg
          font.family: root.fontFamily
          font.pixelSize: 28
          font.bold: true
          bottomPadding: 8
        }

        Repeater {
          model: root.shownSections
          Column {
            required property var modelData
            width: pageColumn.width
            spacing: 4

            Text {
              textFormat: Text.PlainText
              text: modelData.title
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: 14
              font.bold: true
              topPadding: 12
              bottomPadding: 4
            }

            Repeater {
              model: modelData.rows
              SettingRow {
                required property var modelData
                width: pageColumn.width
                row: modelData
              }
            }
          }
        }
      }
    }
  }

  // ---------- One setting card ----------
  component SettingRow: Item {
    id: card
    property var row: ({})
    property bool shown: true
    property bool stateOn: false
    property string value: ""
    property var options: []
    property var listItems: []
    property bool expanded: false
    visible: shown
    height: shown ? body.height : 0

    function refresh() {
      if (row.when) whenProbe.exec(["sh", "-c", row.when])
      if (row.type === "toggle") stateProbe.exec(["sh", "-c", row.state])
      if (row.type === "info" || row.type === "choice") valueProbe.exec(["sh", "-c", row.type === "info" ? row.value : row.current])
      if (row.type === "choice") optionsProbe.exec(["sh", "-c", row.options])
      if (row.type === "list") listProbe.exec(["sh", "-c", row.lines])
      // themes: "omarchy|<name>" or "custom|<name>" per line, for the two sections
      if (row.type === "themes") {
        themesProbe.exec(["sh", "-c", "omarchy-theme-list | while IFS= read -r n; do d=$(printf '%s' \"$n\" | tr 'A-Z ' 'a-z-'); if [ -d \"${OMARCHY_PATH:-/usr/share/omarchy}/themes/$d\" ]; then echo \"omarchy|$n\"; else echo \"custom|$n\"; fi; done"])
        valueProbe.exec(["omarchy-theme-current"])
      }
    }
    Component.onCompleted: refresh()
    Timer { id: refreshLater; interval: 900; onTriggered: card.refresh() }
    function act(command) { root.sh(command); refreshLater.restart() }
    function label(option) { return row.labels && row.labels[option] ? row.labels[option] : option }

    Process { id: whenProbe; onExited: function(code) { card.shown = code === 0 } }
    Process { id: stateProbe; onExited: function(code) { card.stateOn = code === 0 } }
    Process { id: valueProbe; stdout: StdioCollector { onStreamFinished: card.value = text.trim() } }
    Process { id: optionsProbe; stdout: StdioCollector { onStreamFinished: card.options = text.split("\n").filter(function(l) { return l.trim() }) } }
    Process { id: themesProbe; stdout: StdioCollector { onStreamFinished: card.options = text.split("\n").filter(function(l) { return l.trim() }) } }
    Process {
      id: listProbe
      stdout: StdioCollector {
        onStreamFinished: card.listItems = text.split("\n").filter(function(l) { return l.trim() }).map(function(l) {
          var p = l.split("\t"), key = p[0] || "", state = (card.row.states || {})[p[1]]
          if (!state || !new RegExp(card.row.keyPattern || "^$").test(key)) return null
          return { title: p.slice(2).join(" "), detail: state.detail, button: state.button, argv: state.argv.concat([key]) }
        }).filter(function(item) { return item !== null })
      }
    }

    Rectangle {
      id: body
      width: parent.width
      height: content.height + 24
      radius: 8
      color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, cardArea.containsMouse && (card.row.type === "link" || card.row.type === "choice") ? 0.09 : 0.05)
      border.width: 1
      border.color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.06)

      MouseArea {
        id: cardArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: card.row.type === "link" || card.row.type === "choice" || card.row.type === "toggle" ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: {
          if (card.row.type === "link") card.act(card.row.run)
          else if (card.row.type === "choice") card.expanded = !card.expanded
          else if (card.row.type === "toggle") { card.act(card.stateOn ? card.row.off : card.row.on); card.stateOn = !card.stateOn }
        }
      }

      Column {
        id: content
        x: 16
        y: 12
        width: parent.width - 32
        spacing: 10

        // Title line with the control on the right.
        Item {
          visible: card.row.type !== "themes"
          width: parent.width
          height: Math.max(titleColumn.implicitHeight, 28)

          Column {
            id: titleColumn
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - control.width - 16
            Text { textFormat: Text.PlainText; width: parent.width; text: card.row.title || ""; color: root.fg; font.family: root.fontFamily; font.pixelSize: 14; elide: Text.ElideRight }
            Text {
              textFormat: Text.PlainText
              visible: !!card.row.detail
              width: parent.width
              text: card.row.detail || ""
              color: root.fg
              opacity: 0.6
              wrapMode: Text.WordWrap
              font.family: root.fontFamily
              font.pixelSize: 12
            }
          }

          Item {
            id: control
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: controlRow.implicitWidth
            height: controlRow.implicitHeight

            Row {
              id: controlRow
              spacing: 10

              // toggle
              Text {
                textFormat: Text.PlainText
                visible: card.row.type === "toggle"
                anchors.verticalCenter: parent.verticalCenter
                text: card.stateOn ? "On" : "Off"
                color: root.fg
                font.family: root.fontFamily
                font.pixelSize: 13
              }
              Rectangle {
                visible: card.row.type === "toggle"
                anchors.verticalCenter: parent.verticalCenter
                width: 40
                height: 20
                radius: 10
                color: card.stateOn ? root.accent : "transparent"
                border.width: card.stateOn ? 0 : 1
                border.color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.6)
                Rectangle {
                  width: 12
                  height: 12
                  radius: 6
                  anchors.verticalCenter: parent.verticalCenter
                  x: card.stateOn ? parent.width - width - 4 : 4
                  color: card.stateOn ? root.bg : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.8)
                  Behavior on x { NumberAnimation { duration: 120 } }
                }
              }

              // info / choice value
              Text {
                textFormat: Text.PlainText
                visible: card.row.type === "info" || card.row.type === "choice"
                anchors.verticalCenter: parent.verticalCenter
                text: card.row.type === "choice" ? card.label(card.value) : card.value
                width: Math.min(implicitWidth, card.width * 0.45)
                elide: Text.ElideRight
                color: root.fg
                opacity: card.row.type === "info" ? 0.75 : 1
                font.family: root.fontFamily
                font.pixelSize: 13
              }

              // chevron for links and choices
              Text {
                textFormat: Text.PlainText
                visible: card.row.type === "link" || card.row.type === "choice"
                anchors.verticalCenter: parent.verticalCenter
                text: card.row.type === "choice" ? (card.expanded ? "" : "") : ""
                color: root.fg
                opacity: 0.6
                font.family: root.fontFamily
                font.pixelSize: 11
              }
            }
          }
        }

        // choice: the options, when expanded
        Flow {
          visible: card.row.type === "choice" && card.expanded
          width: parent.width
          spacing: 8
          Repeater {
            model: card.row.type === "choice" ? card.options : []
            Rectangle {
              required property var modelData
              readonly property bool selected: modelData === card.value
              width: optionText.implicitWidth + 28
              height: 32
              radius: 6
              color: selected ? root.accent : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, optionArea.containsMouse ? 0.14 : 0.07)
              Text {
                textFormat: Text.PlainText
                id: optionText
                anchors.centerIn: parent
                text: card.label(modelData)
                color: parent.selected ? root.bg : root.fg
                font.family: root.fontFamily
                font.pixelSize: 13
              }
              MouseArea {
                id: optionArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: { card.act(card.row.set.replace("{}", modelData)); card.value = modelData }
              }
            }
          }
        }

        // list: one line per item with a button
        Repeater {
          model: card.row.type === "list" ? card.listItems : []
          Item {
            required property var modelData
            width: content.width
            height: 40
            Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.08) }
            Column {
              anchors.verticalCenter: parent.verticalCenter
              Text { text: modelData.title; textFormat: Text.PlainText; color: root.fg; font.family: root.fontFamily; font.pixelSize: 13 }
              Text { text: modelData.detail; textFormat: Text.PlainText; color: root.fg; opacity: 0.6; font.family: root.fontFamily; font.pixelSize: 12 }
            }
            Rectangle {
              visible: modelData.button !== ""
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              width: buttonText.implicitWidth + 28
              height: 30
              radius: 6
              color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, listButton.containsMouse ? 0.16 : 0.08)
              Text { textFormat: Text.PlainText; id: buttonText; anchors.centerIn: parent; text: modelData.button; color: root.fg; font.family: root.fontFamily; font.pixelSize: 13 }
              MouseArea {
                id: listButton
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: { Quickshell.execDetached(modelData.argv); refreshLater.interval = 2500; refreshLater.restart() }
              }
            }
          }
        }

        // battery: each device's alert levels
        Column {
          visible: card.row.type === "battery"
          width: parent.width
          spacing: 8

          Text {
            textFormat: Text.PlainText
            visible: !root.batteryAlerts || root.batteryAlerts.deviceList.length === 0
            text: "No battery devices found yet."
            color: root.fg
            opacity: 0.6
            font.family: root.fontFamily
            font.pixelSize: 12
          }

          Repeater {
            model: card.row.type === "battery" && root.batteryAlerts ? root.batteryAlerts.deviceList : []

            Rectangle {
              id: device
              required property var modelData
              width: parent.width
              height: deviceColumn.implicitHeight + 20
              radius: 6
              color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.04)

              Column {
                id: deviceColumn
                x: 12
                y: 10
                width: parent.width - 24
                spacing: 8

                // name, charge, on/off
                Item {
                  width: parent.width
                  height: Math.max(deviceName.implicitHeight + deviceState.implicitHeight, 24)

                  Text {
                    textFormat: Text.PlainText
                    id: deviceGlyph
                    anchors.verticalCenter: parent.verticalCenter
                    width: 26
                    text: ({ Laptop: "\uf109", Mouse: "\uf245", Keyboard: "\uf11c", Headset: "\uf025", Headphones: "\uf025",
                             GamingInput: "\uf11b", Phone: "\uf10b", Tablet: "\uf10a" })[device.modelData.kind] || "\uf240"
                    color: root.fg
                    opacity: device.modelData.connected ? 0.9 : 0.4
                    font.family: root.fontFamily
                    font.pixelSize: 16
                  }
                  Column {
                    anchors.left: deviceGlyph.right
                    anchors.leftMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    Text {
                      textFormat: Text.PlainText
                      id: deviceName
                      text: device.modelData.name
                      color: root.fg
                      opacity: device.modelData.connected ? 1 : 0.6
                      font.family: root.fontFamily
                      font.pixelSize: 13
                      font.bold: true
                    }
                    Text {
                      textFormat: Text.PlainText
                      id: deviceState
                      text: device.modelData.connected
                        ? device.modelData.percent + "%" + (device.modelData.charging ? " · charging" : "") + " · " + device.modelData.kind
                        : "Not connected · " + device.modelData.kind
                      color: root.fg
                      opacity: 0.6
                      font.family: root.fontFamily
                      font.pixelSize: 12
                    }
                  }
                  Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 10
                    Text {
                      textFormat: Text.PlainText
                      anchors.verticalCenter: parent.verticalCenter
                      text: device.modelData.enabled ? "Alerts on" : "Alerts off"
                      color: root.fg
                      font.family: root.fontFamily
                      font.pixelSize: 12
                    }
                    Rectangle {
                      anchors.verticalCenter: parent.verticalCenter
                      width: 40
                      height: 20
                      radius: 10
                      color: device.modelData.enabled ? root.accent : "transparent"
                      border.width: device.modelData.enabled ? 0 : 1
                      border.color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.6)
                      Rectangle {
                        width: 12
                        height: 12
                        radius: 6
                        anchors.verticalCenter: parent.verticalCenter
                        x: device.modelData.enabled ? parent.width - width - 4 : 4
                        color: device.modelData.enabled ? root.bg : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.8)
                      }
                      MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.batteryAlerts.setLevel(device.modelData.key, "enabled", !device.modelData.enabled)
                      }
                    }
                  }
                }

                // Low and Critical levels
                Row {
                  visible: device.modelData.enabled
                  x: 32
                  spacing: 24
                  LevelStepper {
                    label: "Low"
                    hint: "heads-up"
                    value: device.modelData.low
                    onStep: function(delta) { root.batteryAlerts.setLevel(device.modelData.key, "low", device.modelData.low + delta) }
                  }
                  LevelStepper {
                    label: "Critical"
                    hint: "urgent alert"
                    value: device.modelData.critical
                    onStep: function(delta) { root.batteryAlerts.setLevel(device.modelData.key, "critical", device.modelData.critical + delta) }
                  }
                }
              }
            }
          }
        }

        // themes: a gallery of previews in two sections, yours first, then
        // Omarchy's own; click a section's title to fold it away
        Column {
          visible: card.row.type === "themes"
          width: parent.width
          spacing: 10
          Repeater {
            model: card.row.type === "themes" ? [["custom", "Your themes"], ["omarchy", "Omarchy themes"]] : []
            Column {
              id: themeSection
              required property var modelData
              readonly property var names: card.options.filter(function(o) { return o.indexOf(modelData[0] + "|") === 0 })
                .map(function(o) { return o.slice(o.indexOf("|") + 1) })
              visible: names.length > 0
              width: parent.width
              spacing: 8
              property bool folded: false
              Text {
                textFormat: Text.PlainText
                text: (themeSection.folded ? "\uf054  " : "\uf078  ") + themeSection.modelData[1] + "  ·  " + themeSection.names.length
                color: root.fg
                opacity: sectionArea.containsMouse ? 0.9 : 0.6
                font.family: root.fontFamily
                font.pixelSize: 12
                font.bold: true
                MouseArea {
                  id: sectionArea
                  anchors.fill: parent
                  anchors.margins: -4
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: themeSection.folded = !themeSection.folded
                }
              }
              Grid {
                visible: !themeSection.folded
                width: parent.width
                columns: 4
                spacing: 12
                Repeater {
                  model: themeSection.names
                  Item {
                    required property var modelData   // the theme's name
                    readonly property string dir: modelData.toLowerCase().replace(/ /g, "-")
                    readonly property bool selected: modelData === card.value
                    width: (content.width - 36) / 4
                    height: width * 0.62 + 26
                    Rectangle {
                      id: frame
                      width: parent.width
                      height: parent.width * 0.62
                      radius: 6
                      color: "transparent"
                      border.width: parent.selected ? 3 : (themeArea.containsMouse ? 2 : 0)
                      border.color: parent.selected ? root.accent : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.4)
                      Image {
                        anchors.fill: parent
                        anchors.margins: 3
                        fillMode: Image.PreserveAspectCrop
                        sourceSize.width: 320
                        asynchronous: true
                        // Omarchy's own themes in its folder; yours in ~/.config/omarchy/themes,
                        // preview.jpg (as these themes ship) or preview.png
                        readonly property string mine: "file://" + Quickshell.env("HOME") + "/.config/omarchy/themes/" + parent.parent.dir
                        source: themeSection.modelData[0] === "custom" ? mine + "/preview.jpg"
                                                                       : "file:///usr/share/omarchy/themes/" + parent.parent.dir + "/preview.png"
                        onStatusChanged: if (status === Image.Error && source.toString() === mine + "/preview.jpg") source = mine + "/preview.png"
                      }
                    }
                    Text {
                      textFormat: Text.PlainText
                      anchors.top: frame.bottom
                      anchors.topMargin: 4
                      width: parent.width
                      horizontalAlignment: Text.AlignHCenter
                      text: modelData
                      elide: Text.ElideRight
                      color: root.fg
                      font.family: root.fontFamily
                      font.pixelSize: 12
                      font.bold: parent.selected
                    }
                    MouseArea {
                      id: themeArea
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: { card.act("omarchy-theme-set '" + modelData + "'"); card.value = modelData }
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

  // −  20%  +   for a battery alert level (steps of 5)
  component LevelStepper: Row {
    id: stepper
    property string label: ""
    property string hint: ""
    property int value: 0
    signal step(int delta)
    spacing: 8
    Column {
      anchors.verticalCenter: parent.verticalCenter
      Text { textFormat: Text.PlainText; text: stepper.label; color: root.fg; font.family: root.fontFamily; font.pixelSize: 12 }
      Text { textFormat: Text.PlainText; text: stepper.hint; color: root.fg; opacity: 0.5; font.family: root.fontFamily; font.pixelSize: 10 }
    }
    Repeater {
      model: [-5, 0, 5]
      Item {
        required property int modelData
        anchors.verticalCenter: parent.verticalCenter
        width: modelData === 0 ? 44 : 26
        height: 26
        Rectangle {
          visible: parent.modelData !== 0
          anchors.fill: parent
          radius: 13
          color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, stepArea.containsMouse ? 0.16 : 0.07)
        }
        Text {
          textFormat: Text.PlainText
          anchors.centerIn: parent
          text: parent.modelData === 0 ? stepper.value + "%" : (parent.modelData < 0 ? "\u2212" : "+")
          color: parent.modelData === 0 ? root.accent : root.fg
          font.family: root.fontFamily
          font.pixelSize: parent.modelData === 0 ? 14 : 15
          font.bold: parent.modelData === 0
        }
        MouseArea {
          id: stepArea
          visible: parent.modelData !== 0
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: stepper.step(parent.modelData)
        }
      }
    }
  }
}
