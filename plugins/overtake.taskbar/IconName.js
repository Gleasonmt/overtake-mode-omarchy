.pragma library
// An app's Icon= as a theme icon name. A file path never reaches Qt: its lookup
// opens the file on the shell's main thread (a named pipe hangs the shell for
// good) and decodes it in the shell (a small PNG with text chunks takes gigabytes,
// both measured). Such an app shows the generic icon. Omarchy's own installers
// always write names.
function safe(name) { return /^[A-Za-z0-9_][A-Za-z0-9_.+-]{0,127}$/.test(String(name || "")) }
