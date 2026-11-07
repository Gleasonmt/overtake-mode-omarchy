// Pure functions from the QML plugins, extracted from the real files and run
// against hostile input: names apps and devices choose ("__proto__",
// "constructor", "laptop"), notification markup, and site lookups.
//   node tests/t-qml-logic.js
"use strict"
const fs = require("fs")
const path = require("path")
const repo = path.join(__dirname, "..")

// The text of `function <name>(...) { ... }` in a QML file, braces matched.
function extract(file, name) {
  const src = fs.readFileSync(path.join(repo, file), "utf8")
  const start = src.indexOf("function " + name + "(")
  if (start < 0) throw new Error(`${name} not found in ${file}`)
  let depth = 0, i = src.indexOf("{", start)
  for (; i < src.length; i++) {
    if (src[i] === "{") depth++
    else if (src[i] === "}" && --depth === 0) break
  }
  return src.slice(start, i + 1)
}

let failed = 0
const bash = require("child_process")
function check(what, ok) {
  console.log((ok ? "ok - " : "FAIL: ") + what)
  if (!ok) failed++
}

// Battery alerts: device keys can't reach built-ins or take the laptop's slot.
{
  const keyOf = new Function(extract("plugins/overtake.taskbar/BatteryAlerts.qml", "keyOf") + "; return keyOf")()
  const ownOf = new Function(extract("plugins/overtake.taskbar/BatteryAlerts.qml", "ownOf") + "; return ownOf")()
  for (const model of ["__proto__", "constructor", "toString", "hasOwnProperty", "laptop"])
    check(`device named "${model}" gets its own key (${keyOf({ model })})`, keyOf({ model }) !== model && keyOf({ model }) !== "laptop")
  check(`the laptop battery keeps "laptop"`, keyOf({ isLaptopBattery: true, model: "x" }) === "laptop")
  check(`an ordinary device keeps its name`, keyOf({ model: "MX Master 3" }) === "MX Master 3")
  check(`ownOf ignores inherited names`, ownOf({}, "constructor") === undefined && ownOf({ a: 1 }, "a") === 1)
  const before = Object.keys(Object.prototype).length
  const devices = {}
  const key = keyOf({ model: "__proto__" })
  const own = ownOf(devices, key) || (devices[key] = {})
  own.name = "polluted?"
  check(`a "__proto__" device can't pollute Object.prototype`, ({}).name === undefined && Object.keys(Object.prototype).length === before)
}

// Notification center: markup decoded like Omarchy's, entities as own keys only.
{
  const file = "plugins/overtake.notification-center/Panel.qml"
  const root = { entities: { amp: "&", lt: "<", gt: ">", quot: "\"", apos: "'", nbsp: " " } }
  const decodeOnce = new Function("root", extract(file, "decodeOnce") + "; return decodeOnce")(root)
  root.decodeOnce = decodeOnce
  const plainBody = new Function("root", "decodeOnce", extract(file, "plainBody") + "; return plainBody")(root, decodeOnce)
  check(`"Tom &amp; Jerry" → "Tom & Jerry"`, plainBody("Tom &amp; Jerry") === "Tom & Jerry")
  check(`"1 < 2 and 3 > 2" kept`, plainBody("if 1 < 2 and 3 > 2") === "if 1 < 2 and 3 > 2")
  check(`<b>/<a>/<img> tags dropped`, plainBody('<b>Hi</b> <a href="x">there</a><img src="http://e/x.png">') === "Hi there")
  check(`"&constructor;" stays literal`, plainBody("&constructor;") === "&constructor;")
  const webHost = new Function(extract(file, "webHost") + "; return webHost")()
  check(`a browser's web group opens its site`, webHost({ groupKey: "web:example.com" }) === "example.com")
  check(`an app name is never treated as a site`, webHost({ groupKey: "app:org.gnome.nautilus", source: "org.gnome.Nautilus" }) === "")
  check(`a numeric "host" is refused`, webHost({ groupKey: "web:0x7f.0x0.0x0.0x1" }) === "")
}

// Spotlight's file list: NUL ends a name, so a newline can't split one.
{
  const split = new Function(extract("plugins/overtake.taskbar/Spotlight.qml", "splitFileList") + "; return splitFileList")()
  const list = split("/home/a\n/etc/shadow\0/home/b\0/home/cut-of")
  check(`a newline stays inside its name`, list.length === 2 && list[0] === "/home/a\n/etc/shadow" && list[1] === "/home/b")
  check(`a name cut off at the size limit is dropped`, !list.includes("/home/cut-of"))
  const src = fs.readFileSync(path.join(repo, "plugins/overtake.taskbar/Spotlight.qml"), "utf8")
  check(`fd ends names with NUL`, /"fd -0 /.test(src))
}

// Mission Control: `drag` belongs to the thumbnail's MouseArea. Outside its
// handlers a bare `drag` is a ReferenceError, and a dragged thumbnail isn't raised.
{
  const src = fs.readFileSync(path.join(repo, "plugins/overtake.taskbar/MissionControl.qml"), "utf8")
  check(`the thumbnail's z reads its MouseArea's drag`, /\n\s*z: thumbMouse\.drag\.active \? 10 : 0\n/.test(src) && /id: thumbMouse\n/.test(src))
}


// An icon by name: a plain name only, and every lookup goes through UserIcons.
{
  const safe = new Function("return (" + extract("plugins/overtake.taskbar/UserIcons.qml", "safe") + ")")()
  for (const bad of ["/home/me/x.png", "/tmp/fifo", "file:///x.png", "image://icon/x", "../x", "a/b", "", null, "x".repeat(200), "a b"])
    check(`Icon=${String(bad).slice(0, 20)} is no icon name`, !safe(bad))
  for (const good of ["firefox", "org.gnome.Nautilus", "google-chrome", "libreoffice-writer", "gtk+"])
    check(`Icon=${good} is an icon name`, safe(good))
  const userIcons = fs.readFileSync(path.join(repo, "plugins/overtake.taskbar/UserIcons.qml"), "utf8")
  check("both plugins use the same UserIcons", userIcons === fs.readFileSync(path.join(repo, "plugins/overtake.notification-center/UserIcons.qml"), "utf8"))
  const embedded = fs.readFileSync(path.join(repo, "patches/apply.py"), "utf8").match(/\nUSER_ICONS_QML = r'''([\s\S]*?)'''\n/)
  check("the notifications copy gets the same UserIcons", !!embedded && embedded[1] === userIcons)
  // Quickshell.iconPath only with a name written here: any other goes through UserIcons.
  const dirs = ["plugins/overtake.taskbar", "plugins/overtake.menubar", "plugins/overtake.notification-center", "plugins/overtake.control-center"]
  const tables = { "Dock.qml": "icon", "StartMenu.qml": ["icon", "name"] }   // (from their own tables of names)
  for (const dir of dirs) for (const f of fs.readdirSync(path.join(repo, dir)).filter(n => n.endsWith(".qml") && n !== "UserIcons.qml")) {
    fs.readFileSync(path.join(repo, dir, f), "utf8").split("\n").forEach((line, n) => {
      for (const m of line.matchAll(/iconPath\(\s*([^,)]*)/g)) {
        const literal = /^["']/.test(m[1]) || /^(root\.trashFull|dir) \? "/.test(m[1]) || [].concat(tables[f] || []).includes(m[1])
        check(`${f}:${n + 1} looks up only a written name: ${m[1]}`, literal)
      }
    })
  }
}

// The center's click: the app's name stays out of the command.
{
  const panel = fs.readFileSync(path.join(repo, "plugins/overtake.notification-center/Panel.qml"), "utf8")
  const lines = panel.split("\n").filter(l => /notification-open/.test(l))
  check("the center runs notification-open with no name in it", lines.length > 0 && lines.every(l => /command: \["overtake", "notification-open"\]/.test(l)))
}

// A drag: the move animation goes off only after it's been read, or "off" is saved as yours.
{
  const fn = extract("plugins/overtake.taskbar/WindowControls.qml", "setMoveAnimation")
  const calls = [], read = { running: false }
  const Q = { root: { moveAnimation: { enabled: true, speed: 1, bezier: "x" } }, Quickshell: { execDetached: a => calls.push(a[2]) }, moveAnimationRead: read, moveAnimationOffNext: false }
  const run = new Function("Q", "with (Q) { return (" + fn + ") }")(Q)
  run(false)
  check("starting a drag only reads the animation", read.running && calls.length === 0 && Q.moveAnimationOffNext)
  run(true)
  check("a drag ended before the read doesn't switch it off afterwards", !Q.moveAnimationOffNext && calls.length === 1 && /enabled = true/.test(calls[0]))
}

// A theme folder comes from git, and its name reaches sh -c through shq.
{
  const shq = new Function("return (" + extract("plugins/overtake.taskbar/Settings.qml", "shq") + ")")()
  const dir = fs.mkdtempSync(path.join(process.env.TMPDIR || "/tmp", "shq"))
  process.on("exit", () => fs.rmSync(dir, { recursive: true, force: true }))
  for (const name of ["$(touch pwned)", "`touch pwned`", "'; touch pwned; '", "a b", "'", "--help", "x\ny"]) {
    const out = bash.spawnSync("sh", ["-c", "printf %s " + shq(name)], { cwd: dir, encoding: "utf8" }).stdout
    check(`shq keeps ${JSON.stringify(name)} as one literal word`, (name === "--help" || out === name) && !fs.existsSync(path.join(dir, "pwned")))
  }
}

// recently-used.xbel: read right, and no shape of it takes minutes.
{
  const of = new Function("return (" + extract("plugins/overtake.taskbar/StartMenu.qml", "bookmarkOf") + ")")()
  const parse = body => body.split("<bookmark ").map(of).filter(Boolean).map(m => m[1] + " " + m[2] + " " + m[3])
  const two = '<xbel><bookmark href="file:///a" modified="2026-01-01"><info><mime:mime-type type="text/plain"/></info></bookmark>\n<bookmark href="file:///b" modified="2026-01-02"><mime:mime-type type="image/png"/></bookmark></xbel>'
  check("both bookmarks are read", JSON.stringify(parse(two)) === '["file:///a 2026-01-01 text/plain","file:///b 2026-01-02 image/png"]')
  for (const [what, body] of [["unfinished bookmarks", '<bookmark href="x" modified="y">'.repeat(40000)], ["one piece of repeated dates", '<bookmark href="x" ' + 'modified="y" '.repeat(100000)], ["a mime type never closed", '<bookmark href="x" modified="y"><mime:mime-type type="' + "z".repeat(1000000)]]) {
    const t = Date.now(); parse(body)
    check(`${what} are quick (${Date.now() - t} ms)`, Date.now() - t < 1000)
  }
}

process.exit(failed ? 1 : 0)
