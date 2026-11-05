// The notification history kept by Overtake's copy of Omarchy's notifications
// service, against the orderings the maintainer reviews notification plugins
// for: Clear all must stick (also through a failed write, and with a shutdown
// right after), nothing past its day stays on disk or in the center, and
// nothing is removed before history has loaded. Runs Omarchy's real Store.js
// and the patched Service.qml functions from a copy built as bin/overtake
// builds it.
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
function extract(src, name) {
  const start = src.indexOf("function " + name + "(")
  if (start < 0) throw new Error(name + " not found")
  let d = 0, i = src.indexOf("{", start)
  for (; i < src.length; i++) { if (src[i] === "{") d++; else if (src[i] === "}" && --d === 0) break }
  return src.slice(start, i + 1).replace(/\((\w+): \w+\): \w+/, "($1)").replace(/\(\): \w+/, "()")
}
const svc = fs.readFileSync(path.join(copy, "Service.qml"), "utf8")

// A FileView as Quickshell 0.3 behaves (measured): setText of the same text it
// last tried to write is skipped, a failed write still counts as tried, and a
// failure emits saveFailed; reload() makes the file's own text the reference.
function FileView(disk, onSaveFailed) {
  return {
    cmp: disk.text, fail: false,
    setText(t) {
      if (t === this.cmp) return
      this.cmp = t
      if (this.fail) { onSaveFailed(); return }
      disk.text = t
    },
    reload() { this.cmp = disk.text },
  }
}
function Service(disk) {
  const s = { historyLoaded: false, historyEntries: [], unsaved: {}, timer: false, retry: false }
  s.file = FileView(disk, () => s.overtakeSaveFailed())
  s.saveSoon = f => { s.unsaved[f] = true; s.timer = true }
  s.flushStore = () => { s.timer = false; if (s.unsaved.history && s.historyLoaded) { delete s.unsaved.history; s.file.setText(Store.serialise(s.historyEntries)) } }
  s.loadHistory = text => {
    if (s.historyLoaded) return
    s.historyEntries = Store.retain(s.historyEntries.concat(Store.parseHistory(text)), Date.now() / 1000)
    s.historyLoaded = true
    if (s.unsaved.history || Store.serialise(s.historyEntries) !== String(text)) s.saveSoon("history")
  }
  s.storeRecord = (row, now) => { now = now || Date.now() / 1000; s.historyEntries = Store.addHistory(s.historyEntries, Store.closedEntry(row, "expired", now), now); s.saveSoon("history") }
  // the patched functions themselves
  s.currentHistory = new Function("service", "Store", "historyEntries", extract(svc, "currentHistory")
    .replace(/historyEntries/g, "service.historyEntries").replace("saveSoon(", "service.saveSoon(") + "; return currentHistory")(s, Store)
  // (missing in a copy that doesn't retry: then a failed write just stays failed)
  s.overtakeSaveFailed = svc.includes("function overtakeSaveFailed(")
    ? new Function("historyFile", "overtakeSaveRetry", extract(svc, "overtakeSaveFailed") + "; return overtakeSaveFailed")(
        { reload: () => s.file.reload() }, { restart: () => { s.retry = true } })
    : () => {}
  s.forget = new Function("service", extract(svc, "forget") + "; return forget")(s)
  return s
}
const row = (k, txt) => Store.normalise({ key: k, app: "Signal", summary: "Alice", body: txt, ts: Date.now() / 1000 })
let failed = 0
const check = (what, ok) => { console.log((ok ? "ok - " : "FAIL: ") + what); if (!ok) failed++ }

// 1. Nothing is removed before history has loaded (it would come back).
{
  const s = Service({ text: "" })
  check("forget before history has loaded is refused (\"notready\")", s.forget("nA") === "notready")
}
// 2. Clear all is written at once: a shutdown right after can't lose it.
{
  const disk = { text: "" }, s = Service(disk); s.loadHistory(disk.text); s.flushStore()
  s.storeRecord(row("nA1", "SECRET-1")); s.storeRecord(row("nA2", "SECRET-2")); s.flushStore()
  const r = s.forget("nA1 nA2")      // no flush by the timer afterwards: the shell is gone
  check("Clear all is on disk at once, without waiting for the save timer", r === "ok" && !/SECRET/.test(disk.text))
}
// 3. A failed write during Clear all is retried and sticks; nothing returns.
{
  const disk = { text: "" }, s = Service(disk); s.loadHistory(disk.text); s.flushStore()
  s.storeRecord(row("nB1", "SECRET-3")); s.flushStore()
  s.file.fail = true
  s.forget("nB1"); s.flushStore()   // disk full: the write fails
  check("a failed write schedules a retry", s.retry === true && /SECRET-3/.test(disk.text))
  s.file.fail = false
  s.retry = false; s.saveSoon("history"); s.flushStore()   // the retry fires once the disk has room
  check("the retry writes the cleared history (not skipped as already tried)", !/SECRET-3/.test(disk.text))
  const after = Service(disk); after.loadHistory(disk.text)
  check("after a restart the cleared entries stay gone", after.historyEntries.length === 0)
}
// 4. Nothing past its day stays on disk, even with no new notification.
{
  const disk = { text: "" }, s = Service(disk); s.loadHistory(disk.text); s.flushStore()
  const old = Date.now() / 1000 - 25 * 3600
  s.storeRecord(row("nC1", "SECRET-OLD"), old); s.flushStore()
  check("(setup) a 25-hour-old entry is on disk", /SECRET-OLD/.test(disk.text))
  check("an expiry timer runs every minute once history has loaded",
    /id: overtakeExpiry[\s\S]{0,120}interval: 60000[\s\S]{0,60}running: service\.historyLoaded[\s\S]{0,60}onTriggered: service\.currentHistory\(\)/.test(svc))
  s.currentHistory(); s.flushStore()   // what that timer does
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
