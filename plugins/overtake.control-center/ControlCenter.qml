import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Studio's two menu bar buttons: Spotlight (the magnifier) and Control
// Center (the switches), which drops down quick settings:
//
//   Wi-Fi, Bluetooth, Focus (do not disturb), Night Light, Stay Awake and
//   Screen Recording as tiles (click the switch to toggle, the name to open
//   Omarchy's panel for it), Display and Sound sliders, and what's playing.
//
// `overtake ui control-center` opens it.
Panel {
  id: root
  moduleName: "overtake.control-center"

  readonly property bool vertical: bar ? bar.vertical : false
  readonly property int barSize: bar ? bar.barSize : Style.bar.sizeHorizontal
  readonly property color fg: root.bar ? root.bar.barForeground : Commons.Color.foreground
  readonly property string fontFamily: root.bar ? root.bar.fontFamily : Style.font.family

  function sh(command) { Quickshell.execDetached(["sh", "-c", command]) }

  // ---------- State (read while the panel is open) ----------
  property bool wifiOn: false
  property string wifiName: ""
  property bool btOn: false
  property bool dndOn: false
  property bool nightOn: false
  property bool awakeOn: false
  property bool recording: false
  property real brightness: -1   // 0..1, or -1 without a backlight

  Process {
    id: probe
    command: ["sh", "-c", [
      "nmcli radio wifi 2>/dev/null | grep -q enabled && echo wifi=1 || echo wifi=0",
      "echo \"ssid=$(nmcli -t -f NAME,TYPE connection show --active 2>/dev/null | grep -m1 ':802-11-wireless$' | sed 's/:802-11-wireless$//')\"",
      "bluetoothctl show 2>/dev/null | grep -q 'Powered: yes' && echo bt=1 || echo bt=0",
      "[ \"$(omarchy-shell notifications isDnd 2>/dev/null)\" = on ] && echo dnd=1 || echo dnd=0",
      "omarchy-toggle-nightlight --status 2>/dev/null | jq -e .enabled >/dev/null && echo night=1 || echo night=0",
      "omarchy-toggle-idle status 2>/dev/null | jq -e .enabled >/dev/null && echo awake=1 || echo awake=0",
      "pgrep -f '^gpu-screen-recorder' >/dev/null && echo rec=1 || echo rec=0",
      "echo \"bright=$(brightnessctl -m 2>/dev/null | head -1 | cut -d, -f4 | tr -d %)\""
    ].join("; ")]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        text.split("\n").forEach(function(line) {
          var i = line.indexOf("=")
          if (i < 0) return
          var k = line.slice(0, i), v = line.slice(i + 1)
          if (k === "wifi") root.wifiOn = v === "1"
          else if (k === "ssid") root.wifiName = v
          else if (k === "bt") root.btOn = v === "1"
          else if (k === "dnd") root.dndOn = v === "1"
          else if (k === "night") root.nightOn = v === "1"
          else if (k === "awake") root.awakeOn = v === "1"
          else if (k === "rec") root.recording = v === "1"
          else if (k === "bright") root.brightness = v === "" ? -1 : Number(v) / 100
        })
      }
    }
  }
  Timer {
    interval: 2000
    repeat: true
    running: root.opened
    triggeredOnStart: true
    onTriggered: probe.running = true
  }
  // After a toggle, look again shortly.
  function act(command) {
    sh(command)
    reprobe.restart()
  }
  Timer { id: reprobe; interval: 700; onTriggered: probe.running = true }

  // ---------- Sound ----------
  readonly property var sink: Pipewire.defaultAudioSink
  PwObjectTracker { objects: root.sink ? [root.sink] : [] }

  // ---------- Now playing ----------
  readonly property var player: {
    var list = Mpris.players.values || []
    return list.find(function(p) { return p.isPlaying }) || list[0] || null
  }

  // `overtake ui control-center` (the focused monitor's bar opens it).
  property string lastUiRequest: ""
  property bool uiRequestSeen: false
  FileView {
    path: Quickshell.env("HOME") + "/.local/state/overtake/ui-request"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      var value = text().trim()
      if (!value || value === root.lastUiRequest) { root.uiRequestSeen = true; return }
      var seen = root.uiRequestSeen
      root.lastUiRequest = value
      root.uiRequestSeen = true
      var w = root.QsWindow.window
      var onFocusedMonitor = w && w.screen && Hyprland.focusedMonitor && Hyprland.focusedMonitor.name === w.screen.name
      if (seen && onFocusedMonitor && value.split(" ")[0] === "control-center") root.toggle()
    }
    onLoadFailed: root.uiRequestSeen = true
  }

  visible: !root.vertical
  implicitWidth: visible ? buttons.implicitWidth : 0
  implicitHeight: root.barSize

  Row {
    id: buttons
    anchors.verticalCenter: parent.verticalCenter

    BarGlyph {
      glyph: ""
      tip: "Spotlight (Super+Space)"
      onClicked: Quickshell.execDetached(["overtake", "ui", "spotlight"])
    }
    BarGlyph {
      id: ccButton
      glyph: ""
      tip: "Control Center"
      lit: root.opened
      onClicked: root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: ccButton
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keys
    contentWidth: Style.space(360)
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keys
      anchors.fill: parent
      onCloseRequested: root.close()

      Column {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Style.space(8)

        // Wi-Fi, Bluetooth and Focus in one card; the small toggles beside it.
        Row {
          width: parent.width
          spacing: Style.space(8)

          Card {
            width: (parent.width - Style.space(8)) * 0.5
            height: Style.space(150)
            Column {
              anchors.fill: parent
              anchors.margins: Style.space(10)
              spacing: Style.space(6)
              BigToggle {
                width: parent.width
                glyph: ""; label: "Wi-Fi"; sub: root.wifiOn ? (root.wifiName || "On") : "Off"
                on: root.wifiOn
                onToggled: root.act(root.wifiOn ? "nmcli radio wifi off" : "nmcli radio wifi on")
                onOpened: { root.close(); root.sh("omarchy-shell omarchy.network open") }
              }
              BigToggle {
                width: parent.width
                glyph: ""; label: "Bluetooth"; sub: root.btOn ? "On" : "Off"
                on: root.btOn
                onToggled: root.act(root.btOn ? "bluetoothctl power off" : "rfkill unblock bluetooth; sleep 1; bluetoothctl power on")
                onOpened: { root.close(); root.sh("omarchy-shell omarchy.bluetooth open") }
              }
              BigToggle {
                width: parent.width
                glyph: ""; label: "Focus"; sub: root.dndOn ? "Do Not Disturb" : "Off"
                on: root.dndOn
                onToggled: root.act("omarchy-shell notifications setDnd " + (root.dndOn ? "false" : "true"))
                onOpened: { root.close(); root.sh("omarchy-shell overtake.notification-center open") }
              }
            }
          }

          Grid {
            columns: 2
            spacing: Style.space(8)
            readonly property real cell: ((parent.width - Style.space(8)) * 0.5 - Style.space(8)) / 2
            SmallToggle { width: parent.cell; height: Style.space(71); glyph: ""; label: "Night Light"; on: root.nightOn; onToggled: root.act("omarchy-toggle-nightlight") }
            SmallToggle { width: parent.cell; height: Style.space(71); glyph: ""; label: "Stay Awake"; on: root.awakeOn; onToggled: root.act("omarchy-toggle-idle toggle") }
            SmallToggle {
              width: parent.cell; height: Style.space(71); glyph: ""; label: root.recording ? "Stop Recording" : "Record"; on: root.recording
              onToggled: { root.close(); root.sh(root.recording ? "omarchy-capture-screenrecording --stop-recording" : "omarchy-menu toggle trigger.capture.screenrecord") }
            }
            SmallToggle { width: parent.cell; height: Style.space(71); glyph: ""; label: "Screenshot"; on: false; onToggled: { root.close(); root.sh("sleep 0.3; omarchy-capture-screenshot region") } }
          }
        }

        // Display brightness (laptops and backlights brightnessctl knows).
        Card {
          visible: root.brightness >= 0
          width: parent.width
          height: Style.space(62)
          SliderRow {
            anchors.fill: parent
            anchors.margins: Style.space(10)
            title: "Display"
            glyph: ""
            value: Math.max(0, root.brightness)
            onMoved: function(v) {
              root.brightness = v
              root.sh("brightnessctl -q set " + Math.max(1, Math.round(v * 100)) + "%")
            }
          }
        }

        Card {
          visible: !!root.sink && !!root.sink.audio
          width: parent.width
          height: Style.space(62)
          SliderRow {
            anchors.fill: parent
            anchors.margins: Style.space(10)
            title: "Sound"
            glyph: root.sink && root.sink.audio && root.sink.audio.muted ? "" : ""
            value: root.sink && root.sink.audio ? Math.min(1, root.sink.audio.volume) : 0
            onMoved: function(v) { if (root.sink && root.sink.audio) { root.sink.audio.muted = false; root.sink.audio.volume = v } }
            onGlyphClicked: if (root.sink && root.sink.audio) root.sink.audio.muted = !root.sink.audio.muted
            onTitleClicked: { root.close(); root.sh("omarchy-shell omarchy.audio open") }
          }
        }

        // What's playing.
        Card {
          visible: root.player !== null
          width: parent.width
          height: Style.space(64)
          Image {
            id: art
            anchors.left: parent.left
            anchors.leftMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(44); height: width
            source: root.player && root.player.trackArtUrl ? root.player.trackArtUrl : ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            Rectangle { anchors.fill: parent; visible: art.status !== Image.Ready; radius: 6; color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.12)
              Text { anchors.centerIn: parent; textFormat: Text.PlainText; text: ""; color: root.fg; font.family: root.fontFamily; font.pixelSize: Style.font.body } }
          }
          Column {
            anchors.left: art.right
            anchors.leftMargin: Style.space(10)
            anchors.right: controls.left
            anchors.rightMargin: Style.space(6)
            anchors.verticalCenter: parent.verticalCenter
            Text { width: parent.width; textFormat: Text.PlainText; text: root.player ? (root.player.trackTitle || root.player.identity || "") : ""; elide: Text.ElideRight; color: root.fg; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall; font.bold: true }
            Text { width: parent.width; textFormat: Text.PlainText; text: root.player ? (root.player.trackArtist || root.player.identity || "") : ""; elide: Text.ElideRight; color: root.fg; opacity: 0.6; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
          }
          Row {
            id: controls
            anchors.right: parent.right
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)
            MediaButton { glyph: ""; onClicked: if (root.player && root.player.canGoPrevious) root.player.previous() }
            MediaButton { glyph: root.player && root.player.isPlaying ? "" : ""; onClicked: if (root.player) root.player.togglePlaying() }
            MediaButton { glyph: ""; onClicked: if (root.player && root.player.canGoNext) root.player.next() }
          }
        }
      }
    }
  }

  // ---------- Pieces ----------
  component BarGlyph: Item {
    id: barGlyph
    property string glyph: ""
    property string tip: ""
    property bool lit: false
    signal clicked()
    width: Style.space(30)
    height: root.barSize
    Rectangle {
      anchors.fill: parent
      anchors.topMargin: Style.space(3)
      anchors.bottomMargin: Style.space(3)
      radius: Style.space(5)
      color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, barGlyph.lit ? 0.2 : (glyphMouse.containsMouse ? 0.1 : 0))
    }
    Text {
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: barGlyph.glyph
      color: root.fg
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
    MouseArea {
      id: glyphMouse
      anchors.fill: parent
      hoverEnabled: true
      onClicked: barGlyph.clicked()
      onEntered: if (root.bar && barGlyph.tip) root.bar.showTooltip(barGlyph, barGlyph.tip)
      onExited: if (root.bar) root.bar.hideTooltip(barGlyph)
    }
  }

  component Card: Rectangle {
    radius: Style.space(14)
    color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.07)
    border.width: 1
    border.color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.1)
  }

  // A round switch, then the name (click the name for the full panel).
  component BigToggle: Item {
    id: big
    property string glyph: ""
    property string label: ""
    property string sub: ""
    property bool on: false
    signal toggled()
    signal opened()
    height: Style.space(40)
    Rectangle {
      id: disc
      width: Style.space(30); height: width; radius: width / 2
      anchors.verticalCenter: parent.verticalCenter
      color: big.on ? Commons.Color.accent : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, discMouse.containsMouse ? 0.22 : 0.14)
      Text { anchors.centerIn: parent; textFormat: Text.PlainText; text: big.glyph; color: big.on ? Commons.Color.background : root.fg; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall }
      MouseArea { id: discMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: big.toggled() }
    }
    Column {
      anchors.left: disc.right
      anchors.leftMargin: Style.space(8)
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      Text { width: parent.width; textFormat: Text.PlainText; text: big.label; elide: Text.ElideRight; color: root.fg; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall; font.bold: true }
      Text { width: parent.width; textFormat: Text.PlainText; text: big.sub; elide: Text.ElideRight; color: root.fg; opacity: 0.6; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
    }
    MouseArea {
      anchors.left: disc.right
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      cursorShape: Qt.PointingHandCursor
      onClicked: big.opened()
    }
  }

  component SmallToggle: Rectangle {
    id: small
    property string glyph: ""
    property string label: ""
    property bool on: false
    signal toggled()
    radius: Style.space(14)
    color: small.on ? Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.85)
                    : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, smallMouse.containsMouse ? 0.12 : 0.07)
    border.width: 1
    border.color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.1)
    Text { anchors.horizontalCenter: parent.horizontalCenter; y: parent.height * 0.18; textFormat: Text.PlainText; text: small.glyph; color: small.on ? Commons.Color.background : root.fg; font.family: root.fontFamily; font.pixelSize: Style.font.body }
    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: parent.height * 0.12
      width: parent.width - Style.space(8)
      horizontalAlignment: Text.AlignHCenter
      textFormat: Text.PlainText
      text: small.label
      elide: Text.ElideRight
      color: small.on ? Commons.Color.background : root.fg
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
    MouseArea { id: smallMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: small.toggled() }
  }

  component SliderRow: Item {
    id: slider
    property string title: ""
    property string glyph: ""
    property real value: 0
    signal moved(real v)
    signal glyphClicked()
    signal titleClicked()
    Text {
      id: sliderTitle
      textFormat: Text.PlainText
      text: slider.title
      color: root.fg
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.bold: true
      MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: slider.titleClicked() }
    }
    Rectangle {
      id: track
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      height: Style.space(22)
      radius: height / 2
      color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.14)
      Rectangle {
        width: Math.max(track.height, track.width * slider.value)
        height: parent.height
        radius: parent.radius
        color: root.fg
        opacity: 0.85
      }
      Text {
        x: Style.space(7)
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: slider.glyph
        color: Commons.Color.background
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        MouseArea { anchors.fill: parent; anchors.margins: -4; onClicked: slider.glyphClicked() }
      }
      MouseArea {
        anchors.fill: parent
        anchors.leftMargin: Style.space(22)
        onPressed: function(m) { slider.moved(Math.max(0, Math.min(1, (m.x + Style.space(22)) / track.width))) }
        onPositionChanged: function(m) { if (pressed) slider.moved(Math.max(0, Math.min(1, (m.x + Style.space(22)) / track.width))) }
      }
    }
  }

  component MediaButton: Item {
    id: media
    property string glyph: ""
    signal clicked()
    width: Style.space(28); height: width
    Rectangle { anchors.fill: parent; radius: width / 2; color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, mediaMouse.containsMouse ? 0.12 : 0) }
    Text { anchors.centerIn: parent; textFormat: Text.PlainText; text: media.glyph; color: root.fg; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall }
    MouseArea { id: mediaMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: media.clicked() }
  }
}
