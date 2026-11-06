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

process.exit(failed ? 1 : 0)
