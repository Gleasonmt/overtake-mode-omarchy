.pragma library
// Edits the text of ~/.config/overtake/desktop-icons.txt ("<id> | <label>" per
// line, # comments), keeping comments and blank lines where they are. Used by
// the desktop's right-click menus and Start's "Add to desktop".

function isIcon(line) { var t = String(line).trim(); return t.length > 0 && t.charAt(0) !== "#" }
function idOf(line) { return String(line).split("|")[0].trim() }
function labelOf(line) { var p = String(line).split("|"); return p.length > 1 ? p.slice(1).join("|").trim() : "" }
function lineFor(id, label) { return label ? id + " | " + label : id }

function lines(text) {
  var out = String(text || "").split("\n")
  if (out.length && out[out.length - 1] === "") out.pop()
  return out
}
function join(list) { return list.join("\n") + "\n" }

function has(text, id) {
  return lines(text).some(function(l) { return isIcon(l) && idOf(l) === id })
}

function add(text, id, label) {
  if (has(text, id)) return String(text || "")
  return join(lines(text).concat([lineFor(id, label)]))
}

function remove(text, id) {
  return join(lines(text).filter(function(l) { return !(isIcon(l) && idOf(l) === id) }))
}

function rename(text, id, label) {
  return join(lines(text).map(function(l) { return isIcon(l) && idOf(l) === id ? lineFor(id, label) : l }))
}

// Swap an icon with the next icon above (delta -1) or below (delta 1).
function move(text, id, delta) {
  var all = lines(text)
  var slots = []
  all.forEach(function(l, i) { if (isIcon(l)) slots.push(i) })
  var at = -1
  for (var i = 0; i < slots.length; i++) if (idOf(all[slots[i]]) === id) at = i
  var to = at + delta
  if (at < 0 || to < 0 || to >= slots.length) return join(all)
  var a = slots[at], b = slots[to], tmp = all[a]
  all[a] = all[b]
  all[b] = tmp
  return join(all)
}

// Put the icons in order of nameOf(id, label), in the slots they already use.
function sortBy(text, nameOf) {
  var all = lines(text)
  var slots = [], icons = []
  all.forEach(function(l, i) { if (isIcon(l)) { slots.push(i); icons.push(l) } })
  icons.sort(function(x, y) {
    return String(nameOf(idOf(x), labelOf(x))).toLowerCase().localeCompare(String(nameOf(idOf(y), labelOf(y))).toLowerCase())
  })
  slots.forEach(function(slot, i) { all[slot] = icons[i] })
  return join(all)
}
