// The notification history kept by Overtake's copy of Omarchy's notifications
// service, against the orderings the maintainer reviews notification plugins
// for: Clear all must stick (also through a failed write, and with a shutdown
// right after), nothing past its day stays on disk or in the center, and
// nothing is removed before history has loaded. Runs Omarchy's real Store.js
// and the service's own functions, timers and history FileView handlers, taken
// from a copy built as bin/overtake builds it.
//   node tests/t-notifications.js <built copy> <repo>
"use strict"
const fs = require("fs"), vm = require("vm"), path = require("path")
const [copy, repo] = process.argv.slice(2)

const libs = {}
function load(name) {   // a QML .pragma library, with its .imports
  if (libs[name]) return libs[name]
  const ctx = { console }
  let src = fs.readFileSync(path.join(copy, name + ".js"), "utf8")
  src = src.replace(/^\.pragma library$/m, "")
           .replace(/^\.import "(\w+)\.js" as (\w+)$/mg, (m, f, as) => { ctx[as] = load(f); return "" })
  vm.createContext(ctx); vm.runInContext(src, ctx)
  return (libs[name] = ctx)
}
const Store = load("Store")
function extract(src, name) {   // a QML function, as a JS function expression
  const start = src.indexOf("function " + name + "(")
  if (start < 0) return null
  let d = 0, i = src.indexOf("{", start)
  for (; i < src.length; i++) { if (src[i] === "{") d++; else if (src[i] === "}" && --d === 0) break }
  return src.slice(start, i + 1).replace(/\((\w+): \w+\): \w+/, "($1)").replace(/\(\): \w+/, "()")
}
function block(src, head) {      // the { … } that follows `head`
  const start = src.indexOf(head)
  if (start < 0) return ""
  let d = 0, i = src.lastIndexOf("{", start)   // the block's own opening brace
  const from = i
  for (; i < src.length; i++) { if (src[i] === "{") d++; else if (src[i] === "}" && --d === 0) break }
  return src.slice(from, i + 1)
}
const svc = fs.readFileSync(path.join(copy, "Service.qml"), "utf8")
const historyFileQml = block(svc, "id: historyFile")
// a handler line (`onSaved: …`, possibly `{ …; … }`) from the history FileView
function handler(name) {
  const m = historyFileQml.match(new RegExp("^\\s*" + name + ": (.+)$", "m"))
  return m ? m[1].replace(/\s+\/\/ .*$/, "").replace(/^\{(.*)\}\s*$/, "$1") : ""
}
// the Timers the service declares: id → { interval, onTriggered, repeat }
function timers() {
  const out = {}
  const re = /Timer \{([^{}]*)\}/g
  let m
  while ((m = re.exec(svc))) {
    const b = m[1], id = (b.match(/id: (\w+)/) || [])[1]
    if (!id) continue
    out[id] = { interval: +(b.match(/interval: (\d+)/) || [])[1],
                repeat: /repeat: true/.test(b),
                onTriggered: (b.match(/onTriggered: (.+)/) || [])[1] || "" }
  }
  return out
}

// A clock, and Timers running on it.
function Clock() {
  const c = { now: 0, list: [] }
  c.timer = (spec, S) => {
    const t = { running: false, due: 0, spec,
      start() { if (!this.running) this.restart() },
      restart() { this.running = true; this.due = c.now + spec.interval },
      stop() { this.running = false } }
    c.list.push(t); return t
  }
  c.advance = ms => {
    const end = c.now + ms
    for (;;) {
      const next = c.list.filter(t => t.running && t.due <= end).sort((a, b) => a.due - b.due)[0]
      if (!next) break
      c.now = next.due
      if (next.spec.repeat) next.due += next.spec.interval; else next.running = false
      next.fire()
    }
    c.now = end
  }
  return c
}

// A FileView as Quickshell 0.3 behaves (measured with a real `qs`, see
// REVIEWING): setText of the text it last tried to write is skipped; a
// failed write still counts as tried; a write refused at open (permissions)
// emits saveFailed, but one that fails at commit (disk full) only logs and
// emits saved; reload() from inside a save signal does nothing, and from
// anywhere else reads the file, makes it the reference and emits loaded.
function FileView(disk, S) {
  const f = { cmp: disk.text, fail: "", inSignal: false }
  const emit = (name, arg) => { f.inSignal = true; try { S.handlers[name](arg) } finally { f.inSignal = false } }
  f.setText = t => {
    if (t === f.cmp) return
    f.cmp = t
    if (f.fail === "open") return emit("onSaveFailed")
    if (f.fail !== "commit") disk.text = t
    emit("onSaved")
  }
  f.reload = () => {
    if (f.inSignal) return
    f.cmp = disk.text
    emit("onLoaded", disk.text)
  }
  return f
}

function Service(disk) {
  const clock = Clock()
  const S = { Store, service: null, handlers: {},
              historyLoaded: false, historyEntries: [], unsaved: {}, liveLoaded: false, quietLoaded: false }
  S.service = S
  const fn = src => src ? new Function("S", "with (S) { return (" + src + ") }")(S) : undefined
  for (const name of ["saveSoon", "flushStore", "loadHistory", "currentHistory", "forget", "overtakeCheckFile", "overtakeSaveFailed"])
    S[name] = fn(extract(svc, name))
  for (const [name, arg] of [["onSaved", ""], ["onSaveFailed", ""], ["onLoaded", "text"], ["onLoadFailed", ""]]) {
    const body = handler(name)
    const run = body ? new Function("S", "t", "with (S) { const text = () => t; " + body + " }") : () => {}
    S.handlers[name] = a => run(S, a)
  }
  for (const [id, spec] of Object.entries(timers())) {
    const t = clock.timer(spec, S)
    t.fire = new Function("S", "with (S) { " + spec.onTriggered + " }").bind(null, S)
    S[id] = t
  }
  S.historyFile = FileView(disk, S)
  S.clock = clock
  S.start = () => S.historyFile.reload()        // the first load
  S.quit = () => {}                              // shell gone: no timer fires again
  return S
}
const row = (k, txt) => Store.normalise({ key: k, app: "Signal", summary: "Alice", body: txt, ts: Date.now() / 1000 })
let failed = 0
const check = (what, ok) => { console.log((ok ? "ok - " : "FAIL: ") + what); if (!ok) failed++ }
const settle = s => s.clock.advance(400)   // the save timer and anything it starts

// 1. Nothing is removed before history has loaded (it would come back).
{
  const s = Service({ text: "" })
  check("forget before history has loaded is refused (\"notready\")", s.forget("nA") === "notready")
}
// 2. Clear all is written at once: a shutdown right after can't lose it.
{
  const disk = { text: "" }, s = Service(disk); s.start(); settle(s)
  s.storeRecord = (k, t) => { s.historyEntries = Store.addHistory(s.historyEntries, Store.closedEntry(row(k, t), "expired", Date.now() / 1000), Date.now() / 1000); s.saveSoon("history") }
  s.storeRecord("nA1", "SECRET-1"); s.storeRecord("nA2", "SECRET-2"); settle(s)
  const r = s.forget("nA1 nA2")      // no timer fires afterwards: the shell is gone
  check("Clear all is on disk at once, without waiting for the save timer", r === "ok" && !/SECRET/.test(disk.text))
}
// 3. A failed write during Clear all is written again until the file matches,
//    both when the write is refused (saveFailed) and when it fails at commit
//    (reported as saved); nothing comes back after a restart.
for (const how of ["open", "commit"]) {
  const disk = { text: "" }, s = Service(disk); s.start(); settle(s)
  s.historyEntries = Store.addHistory(s.historyEntries, Store.closedEntry(row("nB1", "SECRET-3"), "expired", Date.now() / 1000), Date.now() / 1000)
  s.saveSoon("history"); settle(s); s.clock.advance(7000)
  s.historyFile.fail = how                       // disk full / unwritable from here
  s.forget("nB1")
  s.clock.advance(12000)
  check(`(${how}) the failed write left the entry on disk`, /SECRET-3/.test(disk.text))
  s.historyFile.fail = ""                        // room again
  s.clock.advance(12000)
  check(`(${how}) the cleared history is written once the disk has room`, !/SECRET-3/.test(disk.text))
  const pending = s.clock.list.filter(t => t.running && !t.spec.repeat).length
  check(`(${how}) and then nothing is left retrying`, pending === 0)
  const after = Service(disk); after.start()
  check(`(${how}) after a restart the cleared entries stay gone`, after.historyEntries.length === 0)
}
// 4. Nothing past its day stays on disk, even with no new notification.
{
  const disk = { text: "" }, s = Service(disk); s.start(); settle(s)
  const old = Date.now() / 1000 - 25 * 3600
  s.historyEntries = Store.addHistory(s.historyEntries, Store.closedEntry(row("nC1", "SECRET-OLD"), "expired", old), old)
  s.saveSoon("history"); settle(s)
  check("(setup) a 25-hour-old entry is on disk", /SECRET-OLD/.test(disk.text))
  const t = s.overtakeExpiry
  check("an expiry timer runs every minute once history has loaded",
    !!t && t.spec.interval === 60000 && t.spec.repeat && /running: service\.historyLoaded/.test(block(svc, "id: overtakeExpiry")))
  if (t) t.start()
  s.clock.advance(61000)
  check("the expiry check takes a day-old entry off the disk", !/SECRET-OLD/.test(disk.text))
}
// 5. The center never lists an entry past its day, whatever the file holds.
{
  const panel = fs.readFileSync(path.join(repo, "plugins/overtake.notification-center/Panel.qml"), "utf8")
  const root = {}
  const parseHistory = new Function("root", extract(panel, "parseHistory").replace(/lastHiddenKeys = /, "root.lastHiddenKeys = ") + "; return parseHistory")(root)
  const now = Date.now() / 1000
  const shown = parseHistory(JSON.stringify([
    { key: "n1", app: "Signal", ts: now - 60, closed_ts: now - 30 },
    { key: "n2", app: "Signal", ts: now - 90000, closed_ts: now - 89000 },
  ]))
  check("the center leaves out an entry closed more than a day ago", shown.length === 1 && shown[0].key === "n1")
}
process.exit(failed ? 1 : 0)
