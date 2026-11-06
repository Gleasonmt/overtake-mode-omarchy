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

// QML's JSON.stringify leaves an unpaired UTF-16 half raw (measured: length
// 3 for "\ud83d"), where Node escapes it; the libraries serialise as in QML.
const qmlJson = `(function () {
  const raw = JSON.stringify
  JSON.stringify = function () { const s = raw.apply(JSON, arguments); return typeof s !== "string" ? s
    : s.replace(/((?:^|[^\\\\])(?:\\\\\\\\)*)\\\\u(d[89a-f][0-9a-f]{2})/gi, (m, pre, hex) => pre + String.fromCharCode(parseInt(hex, 16))) }
})()`
const libs = {}
function load(name) {   // a QML .pragma library, with its .imports
  if (libs[name]) return libs[name]
  const ctx = { console }
  let src = fs.readFileSync(path.join(copy, name + ".js"), "utf8")
  src = src.replace(/^\.pragma library$/m, "")
           .replace(/^\.import "(\w+)\.js" as (\w+)$/mg, (m, f, as) => { ctx[as] = load(f); return "" })
  vm.createContext(ctx); vm.runInContext(qmlJson, ctx); vm.runInContext(src, ctx)
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
  let d = 0, i = head.endsWith("{") ? start + head.length - 1 : src.lastIndexOf("{", start)
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
// a Timer's onTriggered body, on one line or as a { … } block
function trigger(b) {
  const m = b.match(/onTriggered: (.*)/)
  if (!m) return ""
  if (m[1].trim() === "{") return block(b.slice(m.index), "onTriggered: {").slice(1, -1)
  return m[1].replace(/\s+\/\/ .*$/, "").replace(/^\{(.*)\}\s*$/, "$1")
}
// the Timers the service declares: id → { interval, onTriggered, repeat }
function timers() {
  const out = {}
  for (let at = svc.indexOf("Timer {"); at >= 0; at = svc.indexOf("Timer {", at + 1)) {
    const b = block(svc.slice(at), "Timer {"), id = (b.match(/^\s*id: (\w+)/m) || [])[1]
    if (!id) continue
    out[id] = { interval: +(b.match(/interval: (\d+)/) || [])[1],
                repeat: /repeat: true/.test(b),
                onTriggered: trigger(b) }
  }
  return out
}

// A clock, and Timers running on it.
function Clock() {
  const c = { now: 0, list: [], soon: [] }
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
      while (c.soon.length) c.soon.shift()()
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
// anywhere else reads the file, makes it the reference and emits loaded (or
// loadFailed when there is no file, after which any text is written). A UTF-16 half without its pair is
// dropped on the way to disk.
const onDisk = t => {
  let out = ""
  for (let i = 0; i < t.length; i++) {
    const c = t.charCodeAt(i)
    if (c >= 0xd800 && c <= 0xdbff && i + 1 < t.length && (t.charCodeAt(i + 1) & 0xfc00) === 0xdc00) { out += t.substr(i, 2); i++ }
    else if ((c & 0xf800) !== 0xd800) out += t[i]
  }
  return out
}
function FileView(disk, S) {
  // text: what text() gives and setText compares with; data: the bytes it
  // holds (its last attempt, or the file as last read)
  const f = { cmp: disk.text, data: disk.text, fail: "", inSignal: false }
  const emit = (name, arg) => { f.inSignal = true; try { S.handlers[name](arg) } finally { f.inSignal = false } }
  f.setText = t => {
    if (t === f.cmp) return
    disk.attempts = (disk.attempts || 0) + 1
    // the same bytes as it holds: its text stays as it was
    if (onDisk(t) !== f.data) { f.cmp = t; f.data = onDisk(t) }
    if (f.fail === "open") return emit("onSaveFailed")
    if (f.fail !== "commit") disk.text = onDisk(t)
    emit("onSaved")
  }
  f.reload = () => {
    if (f.inSignal) return
    if (disk.text === null) { f.cmp = f.data = null; return emit("onLoadFailed") }
    // bytes it already holds: its text stays (with any unpaired half)
    if (disk.text !== f.data) { f.cmp = f.data = disk.text }
    emit("onLoaded", f.cmp)
  }
  return f
}

function Service(disk) {
  const clock = Clock()
  const S = { Store, service: null, handlers: {},
              historyLoaded: false, historyEntries: [], liveEntries: [], unsaved: {}, liveLoaded: false, quietLoaded: false,
              storeReady: true, overtakePrepareNext: [], overtakePrepareNow: [], overtakePrepareFailed: false }
  S.service = S
  const fn = src => src ? new Function("S", "with (S) { return (" + src + ") }")(S) : undefined
  for (const name of ["saveSoon", "flushStore", "overtakeWriteStore", "overtakeWhenPrepared", "overtakeStartPrepare", "overtakePrepareExited", "overtakeNotLoadedReply", "overtakeReadHistoryBack", "loadHistory", "currentHistory", "forget", "forgetAll", "storeDrop", "overtakeCheckFile", "overtakeComparable", "overtakeRemoveInPlace", "overtakeSaveFailed"])
    S[name] = fn(extract(svc, name))
  // The folder preparation: a process, so its exit comes later (on the clock's
  // next tick), and `prepareCode` is what it exits with.
  S.prepareCode = 0
  S.storePrepare = { busy: false, runs: 0, get running() { return this.busy },
    set running(v) { if (!v) return; this.busy = true; this.runs++
      clock.soon.push(() => { this.busy = false; S.overtakePrepareExited(S.prepareCode) }) } }
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
  // the in-place removal: read by a second FileView, written by a helper (its
  // real failures are covered in real Quickshell). On a full disk a shrink
  // succeeds (measured); refused at open it fails. reload() is asynchronous
  // (measured): the file is read a moment later.
  const inPlace = { path: null,
    reload() { S.clock.soon.push(() => { if (S.historyLoaded && disk.text !== null) S.overtakeRemoveInPlace(disk.text) }) } }
  S.overtakeInPlace = S.overtakeInPlaceFile = inPlace
  S.overtakeHistoryWrite = { send(t) { if (S.historyFile.fail !== "open") disk.text = onDisk(t) } }
  S.overtakeLiveInPlace = { reload() {} }   // (live.json: covered in real Quickshell)
  S.liveFile = { setText() {} }
  S.clock = clock
  S.start = () => { S.liveLoaded = true; S.historyFile.reload() }        // the first loads
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
  s.clock.advance(0)                 // (only the folder check returns)
  check("Clear all is on disk as soon as the folder check returns, without waiting for the save timer", r === "ok" && !/SECRET/.test(disk.text))
}
// 2a. Nothing is written until the folder check has finished, and while it
//     fails the write is held, not lost.
{
  const disk = { text: "" }, s = Service(disk); s.start(); settle(s)
  s.storeRecord = (k, t) => { s.historyEntries = Store.addHistory(s.historyEntries, Store.closedEntry(row(k, t), "expired", Date.now() / 1000), Date.now() / 1000); s.saveSoon("history") }
  s.storeRecord("nH1", "HELD-1"); s.flushStore()
  check("a write waits for the folder check", s.storePrepare.busy && !/HELD-1/.test(disk.text))
  s.prepareCode = 1; s.clock.advance(0)
  check("a failed folder check holds the write", !/HELD-1/.test(disk.text) && s.overtakePrepareRetry.running)
  s.prepareCode = 0; s.clock.advance(5000)
  check("and it goes as soon as the check passes", /HELD-1/.test(disk.text))
}
// 2b. Clear all waits for live.json too: a card restored after it would come back.
{
  const s = Service({ text: "" }); s.historyFile.reload(); settle(s)
  check("forgetAll before live.json has loaded is refused", s.historyLoaded && !s.liveLoaded && s.forgetAll() === "notready")
}
// 2c. A folder that can't be prepared isn't "still loading".
{
  const s = Service({ text: "" }); s.overtakePrepareFailed = true
  check("forget on a folder that can't be prepared says so", s.forget("nA") === "unwritable")
  check("forgetAll on a folder that can't be prepared says so", s.forgetAll() === "unwritable")
  check("and each asks for another try", s.storePrepare.runs >= 1)
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
  const before = disk.attempts || 0
  s.clock.advance(12000)
  check(how === "open" ? "(open) a refused write leaves the entry on disk, and is retried" : "(commit) on a full disk the removal is already off the file, written in place",
    how === "open" ? /SECRET-3/.test(disk.text) : !/SECRET-3/.test(disk.text))
  check(`(${how}) while it fails, a write about every 6 s, not more`, (disk.attempts || 0) - before <= 3)
  s.historyFile.fail = ""                        // room again
  s.clock.advance(12000)
  check(`(${how}) the cleared history is written once the disk has room`, !/SECRET-3/.test(disk.text))
  const pending = s.clock.list.filter(t => t.running && !t.spec.repeat).length
  check(`(${how}) and then nothing is left retrying`, pending === 0)
  const after = Service(disk); after.start()
  check(`(${how}) after a restart the cleared entries stay gone`, after.historyEntries.length === 0)
}
// 3a. Full disk: a removal is already off the file before there is any room,
//     so a restart before then doesn't bring it back; other rows stay.
{
  const disk = { text: "" }, s = Service(disk); s.start(); settle(s)
  const add = (k, txt) => { s.historyEntries = Store.addHistory(s.historyEntries, Store.closedEntry(row(k, txt), "expired", Date.now() / 1000), Date.now() / 1000); s.saveSoon("history") }
  add("nF1", "SECRET-KEEP"); add("nF2", "SECRET-GONE"); settle(s); s.clock.advance(7000)
  s.historyFile.fail = "commit"
  s.forget("nF2")
  s.clock.advance(1)   // the file read, a moment later
  const after = Service(disk); after.start()
  check("full disk: a removal survives a restart before there is room", !/SECRET-GONE/.test(disk.text) && after.historyEntries.length === 1 && /SECRET-KEEP/.test(disk.text))
}
// 3a'. forgetAll: everything in memory, and live cards file nothing as they close.
{
  const disk = { text: "" }, s = Service(disk); s.start(); settle(s)
  s.liveEntries = [{ key: "nG1" }]
  s.historyEntries = Store.addHistory(s.historyEntries, Store.closedEntry(row("nG2", "SECRET-A"), "expired", Date.now() / 1000), Date.now() / 1000); s.saveSoon("history"); settle(s)
  const r = s.forgetAll()
  s.clock.advance(0)
  check("forgetAll clears history and the live cards", r === "ok" && s.historyEntries.length === 0 && s.liveEntries.length === 0 && !/SECRET-A/.test(disk.text))
}
// 3b. A history file deleted while a write fails is written again from memory.
{
  const disk = { text: "" }, s = Service(disk); s.start(); settle(s)
  const add = (k, txt) => { s.historyEntries = Store.addHistory(s.historyEntries, Store.closedEntry(row(k, txt), "expired", Date.now() / 1000), Date.now() / 1000); s.saveSoon("history") }
  add("nD1", "KEEP-1"); settle(s); s.clock.advance(7000)
  s.historyFile.fail = "commit"; disk.text = null   // gone, and the disk is full
  add("nD2", "KEEP-2"); s.clock.advance(3000)
  s.historyFile.fail = ""; s.clock.advance(12000)
  check("a deleted history file is written again from memory", disk.text !== null && /KEEP-1/.test(disk.text) && /KEEP-2/.test(disk.text))
}
// 3c. A body cut mid-emoji (one UTF-16 half left; the write drops it) never
//     sets off endless rewrites, even after a failed write and a removal.
{
  const disk = { text: "" }, s = Service(disk); s.start(); settle(s)
  const add = (k, txt) => { s.historyEntries = Store.addHistory(s.historyEntries, Store.closedEntry(row(k, txt), "expired", Date.now() / 1000), Date.now() / 1000); s.saveSoon("history") }
  add("nE1", "x" + "\ud83d\ude00".repeat(3001)); settle(s); s.clock.advance(7000)   // Omarchy cuts it to 3/4, mid-emoji
  check("(setup) the stored body ends in half an emoji", /[\ud800-\udbff]"/.test(Store.serialise(s.historyEntries)))
  s.historyFile.fail = "open"; add("nE2", "new one"); s.clock.advance(3000)
  s.forget("nE2"); s.clock.advance(3000)
  s.historyFile.fail = ""; s.clock.advance(12000)
  const before = disk.attempts
  s.clock.advance(60000)
  check("a history with an unpaired UTF-16 half isn't rewritten over and over", disk.attempts === before && !/new one/.test(disk.text))
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
// 4b. The center's Clear all is the service's forgetAll, and a click opens a
//     web notification's site before looking for a window. (Their own code.)
{
  const panel = fs.readFileSync(path.join(repo, "plugins/overtake.notification-center/Panel.qml"), "utf8")
  const P = { entries: [{ key: "a" }], hiddenKeys: ["b"], pendingKeys: [], pendingAll: false, removedKeys: [],
              historyProc: { running: false, command: null, sent: [] } }
  const pf = src => new Function("P", "with (P) { return (" + src + ") }")(P)
  P.removeAll = () => {}   // (what an older Clear all called)
  P.sendPending = pf(extract(panel, "sendPending")); P.clearAll = pf(extract(panel, "clearAll"))
  P.clearAll()
  check("the center's Clear all asks the service for forgetAll", P.historyProc.running && P.historyProc.command.join(" ") === "omarchy-shell notifications forgetAll" && P.entries.length === 0)
  const calls = []
  const Q = { execDetached: () => calls.push("exec"), openProc: { running: false, set command(v) { calls.push("window") } },
              remove: () => calls.push("remove"), close: () => {}, Qt: { openUrlExternally: u => calls.push("site " + u) },
              Quickshell: { execDetached: () => calls.push("exec") } }
  Q.webHost = new Function("return (" + extract(panel, "webHost") + ")")()
  new Function("Q", "with (Q) { return (" + extract(panel, "activate") + ") }")(Q)({ app: "Chromium", groupKey: "web:slack.com", execArgv: "" })
  check("a web notification opens its site, not the browser's window", calls[0] === "site https://slack.com/" && !calls.includes("window"))
}
// 4c. The minute-later check reads at most a code's length of the clipboard.
check("the clipboard check is capped at a code's length", /wl-paste --no-newline 2>\/dev\/null \| head -c 65/.test(svc) && !/command: \["wl-paste"/.test(svc))
// 5. The center never lists an entry past its day, whatever the file holds.
{
  const panel = fs.readFileSync(path.join(repo, "plugins/overtake.notification-center/Panel.qml"), "utf8")
  const root = {}
  const limits = { historyMaxChars: 100 * 4096 * 2, historyMaxRows: 100 }
  const parseHistory = new Function("root", "historyMaxChars", "historyMaxRows", extract(panel, "parseHistory").replace(/lastHiddenKeys = /, "root.lastHiddenKeys = ") + "; return parseHistory")(root, limits.historyMaxChars, limits.historyMaxRows)
  const now = Date.now() / 1000
  const shown = parseHistory(JSON.stringify([
    { key: "n1", app: "Signal", ts: now - 60, closed_ts: now - 30 },
    { key: "n2", app: "Signal", ts: now - 90000, closed_ts: now - 89000 },
  ]))
  check("the center leaves out an entry closed more than a day ago", shown.length === 1 && shown[0].key === "n1")
  const capped = parseHistory
  const many = n => Array.from({ length: n }, (_, i) => ({ key: "n" + i, app: "A", ts: now - 60, closed_ts: now - 30 }))
  check("the center doesn't parse a history file past Omarchy's size limit", capped(" ".repeat(limits.historyMaxChars) + JSON.stringify(many(1))).length === 0)
  check("the center reads at most Omarchy's 100 rows", capped(JSON.stringify(many(150))).length === 100)
  check("the center's limits are Omarchy's", /historyMaxRows: 100\b/.test(panel) && /historyMaxChars: 100 \* 4096 \* 2\b/.test(panel)
        && Store.HISTORY_LIMIT === 100 && Store.HISTORY_ROW_CHARS === 4096)
}
// 6. Clear all is offered while only rows the panel hides remain.
{
  const panel = fs.readFileSync(path.join(repo, "plugins/overtake.notification-center/Panel.qml"), "utf8")
  check("Clear all counts the rows the panel hides", /canClear: entries\.length > 0 \|\| hiddenKeys\.length > 0/.test(panel)
        && /visible: root\.view === "list" && root\.canClear/.test(panel))
}
// 7. What the center says about Do Not Disturb is what the service does
//    (the behaviour itself is checked in real Quickshell).
{
  const panel = fs.readFileSync(path.join(repo, "plugins/overtake.notification-center/Panel.qml"), "utf8")
  for (const words of ["verification codes", "critical battery alerts", "critical alerts from scripts", "plain notify-send messages", "temporary"])
    check(`the Do Not Disturb text mentions ${words}`, panel.includes(words))
  check("the old claim (only battery alerts get through) is gone", !panel.includes("pop-ups are hidden (except critical battery alerts)"))
}
// 8. Omapager's notice: the engine in the copied Service.qml began as Omapager.
{
  const notice = fs.readFileSync(path.join(repo, "NOTICE.md"), "utf8")
  check("(setup) the copy still carries Omapager's credit", /Omapager, Copyright \(c\) 2026 Neil Jagdish Patel/.test(svc))
  check("NOTICE.md has Omapager's copyright line", notice.includes("Copyright (c) 2026 Neil Jagdish Patel"))
  check("NOTICE.md has two copies of the permission text (Omarchy's, Omapager's)", notice.split("Permission is hereby granted").length === 3)
}
// 9. Markup.render, the one thing that feeds the StyledText body, on hostile
//    input: only the listed tags come out, and only links Security allows.
{
  const Markup = load("Markup"), Security = load("Security")
  const hostile = [
    '<img src="https://evil.test/x.png">', '<IMG SRC=https://evil.test/x.png>', '<img/src=x>',
    '&lt;img src="https://evil.test/x.png"&gt;', '&amp;lt;img src="https://evil.test/x.png"&amp;gt;',
    '&amp;amp;lt;img src=x&amp;amp;gt;', '&amp;amp;amp;lt;img src=x&amp;amp;amp;gt;', '&#60;img src=x&#62;', '&#x3c;img src=x&#x3e;',
    '<a href="https://ok.test/" onclick="x"><img src="https://evil.test/x.png"></a>',
    '<a href="javascript:alert(1)">x</a>', '<a href="file:///etc/passwd">x</a>', '<a href="https://u:p@evil.test/">x</a>',
    '<a href="https://evil.test/%0d%0ax">x</a>', '<a href="https://ok.test/\'onmouseover=\'x">x</a>',
    '<a href=https://ok.test/><img src=x></a>', '<b onclick="x">y</b>', '<font color=red size=9>x</font>', '<span style="x">y</span>',
    '<style>*{}</style>', '<script>x</script>', '<table><tr><td>x</td></tr></table>', '<h1>x</h1>', '<p>x</p>', '<hr>', '<ul><li>x</li></ul>',
    '<div>x</div>', '<pre>x</pre>', '<u><b><i><s><em><strong>x', '<br/><br /><br>', '<a href="mailto:a@ok.test?body=x">y</a>',
    'https://ok.test/?a=1&b="<img src=x>', 'see https://ok.test/a&lt;img src=x&gt;', '<img\nsrc=x>', '<\x00img src=x>', '<a\thref="https://ok.test/">y</a>',
    '&#x26;lt;img src=x&#x26;gt;', '&#38;#60;img src=x&#38;#62;',
  ]
  const allowed = /^<\/?(?:b|i|u|s|strong)>$|^<br\/>$|^<\/a>$/
  const badTags = []
  for (const text of hostile) {
    const out = Markup.render(text)
    for (const tag of out.match(/<[^>]*>?/g) || []) {
      const a = tag.match(/^<a href="([^"]*)">$/)
      const href = a && a[1].replace(/&amp;/g, "&")
      if (!allowed.test(tag) && !(a && Security.safeExternalUrl(href) === href)) badTags.push(JSON.stringify(text) + " gives " + tag)
    }
  }
  if (badTags.length) console.log(badTags.join("\n"))
  check(`Markup.render on ${hostile.length} hostile inputs gives only the allowed tags and links`, badTags.length === 0)
  check("(control) that check sees a bare tag", !allowed.test("<img src=x>"))
  check("(control) a good link still comes through", /<a href="https:\/\/ok\.test\/a">/.test(Markup.render('<a href="https://ok.test/a">y</a>')))
  check("(control) a bold still comes through", Markup.render("<b>y</b>") === "<b>y</b>")
}
process.exit(failed ? 1 : 0)
