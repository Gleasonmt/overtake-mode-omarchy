import QtQuick
import Quickshell
// An icon by name only, through Qt's theme lookup: the same one Omarchy's own
// launcher, dock and notifications use in this shell. A path is never passed:
// Qt's lookup opens a path on the main thread, and a named pipe hangs the shell
// for good, while a small PNG with compressed text takes gigabytes (both measured).
QtObject {
  function safe(name) { return /^[A-Za-z0-9_][A-Za-z0-9_.+-]{0,127}$/.test(String(name || "")) }
  function source(name) { return safe(name) ? Quickshell.iconPath(name, true) : "" }
}
