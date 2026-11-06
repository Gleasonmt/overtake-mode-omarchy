#!/usr/bin/env python3
# Every QML Text item renders as plain text (`textFormat: Text.PlainText` as
# its own property), so text other programs choose (window titles,
# notification fields, device and file names) can never be read as HTML that
# loads a remote image. No rich-text item types are used at all.
#
# That covers Overtake's own plugins and the patched copies of Omarchy's, built
# here from $OMARCHY_SRC as bin/overtake builds them. One exception is allowed,
# and it has to look exactly like this: the notifications copy's toast body,
# Omarchy's own, is Text.StyledText, fed only by Markup.render (see the hostile
# input check in t-notifications.js).
#   python3 -I tests/t-plain-text.py
import os, pathlib, re, shutil, subprocess, sys, tempfile

root = pathlib.Path(__file__).resolve().parent.parent
src = pathlib.Path(os.environ.get("OMARCHY_SRC", "/usr/share/omarchy/shell/plugins"))
# (name, folder in Omarchy, the QML files that copy keeps), as in bin/overtake's COPY_SPECS
COPIES = [("workspaces", "bar/widgets", ["Workspaces.qml"]),
          ("bluetooth", "panels/bluetooth", ["Panel.qml"]),
          ("audio", "panels/audio", ["Panel.qml"]),
          ("notifications", "notifications", ["Service.qml", "Toast.qml", "DeedButton.qml"]),
          ("battery", "services/battery", ["Service.qml"])]
EXCEPTION_FILE = "notifications/Toast.qml"
# The whole expression, so anything else fed to it fails the test.
EXCEPTION_TEXT = re.compile(r'''\btextFormat:\s*Text\.StyledText\s*\n\s*text:\s*card\.redacted\s*\?\s*I18n\.t\("notifications\.redactedBody"\)\s*:\s*String\(card\.row\.bodyRich \|\| ""\)\s*\n''')


def own_properties(src, m):
    """The text of a `Text {` block with nested blocks left out, and where it ends."""
    depth, j = 1, m.end()
    while depth and j < len(src):
        depth += {"{": 1, "}": -1}.get(src[j], 0)
        j += 1
    own, d = [], 0
    for c in src[m.end():j - 1]:
        if c == "{":
            d += 1
        elif c == "}":
            d -= 1
        elif d == 0:
            own.append(c)
    return "".join(own)


def without_comments(src):
    """The source with // and /* */ comments blanked, leaving strings and line numbers alone."""
    out, i, quote = [], 0, ""
    while i < len(src):
        c = src[i]
        if quote:
            out.append(c)
            if c == "\\" and i + 1 < len(src):
                out.append(src[i + 1])
                i += 1
            elif c == quote or (c == "\n" and quote != "`"):
                quote = ""
        elif c in "\"'`":
            quote = c
            out.append(c)
        elif src.startswith("//", i):
            while i < len(src) and src[i] != "\n":
                i += 1
            continue
        elif src.startswith("/*", i):
            end = src.find("*/", i + 2)
            end = len(src) if end < 0 else end + 2
            out.append("\n" * src.count("\n", i, end))
            i = end
            continue
        else:
            out.append(c)
        i += 1
    return "".join(out)


def scan(label, text, problems, allow_exception=False):
    text = without_comments(text)   # (a commented-out textFormat doesn't count)
    count, exceptions = 0, 0
    for kind in ("Text.RichText", "Text.MarkdownText"):
        if kind in text:
            problems.append(f"{label}: uses {kind}")
    for m in re.finditer(r"(?<![A-Za-z.])(Label|ToolTip|TextEdit|TextArea)\s*\{", text):
        problems.append(f"{label}:{text[:m.start()].count(chr(10)) + 1}: uses {m.group(1)}")
    # Every `Text {` (also `component X: Text {`): its own properties, nested
    # blocks left out, must set PlainText.
    for m in re.finditer(r"(?<![A-Za-z.])Text\s*\{", text):
        count += 1
        own = own_properties(text, m)
        if re.search(r"\btextFormat:\s*Text\.PlainText\b", own):
            continue
        if allow_exception and EXCEPTION_TEXT.search(own):
            exceptions += 1
            continue
        problems.append(f"{label}:{text[:m.start()].count(chr(10)) + 1}: Text without textFormat: Text.PlainText")
    styled = text.count("Text.StyledText")
    if styled != exceptions:
        problems.append(f"{label}: uses Text.StyledText outside the allowed toast body")
    return count, exceptions


problems = []
own_files = sorted(root.glob("plugins/*/*.qml")) + [root / "Setup.qml"]
items = 0
for path in own_files:
    items += scan(str(path.relative_to(root)), path.read_text(), problems)[0]

built, exceptions = 0, 0
if src.is_dir():
    with tempfile.TemporaryDirectory() as tmp:
        for name, folder, qml in COPIES:
            work = pathlib.Path(tmp) / name
            work.mkdir()
            for f in (src / folder).iterdir():
                if f.is_file():
                    shutil.copy(f, work / f.name)
            if subprocess.run([sys.executable, "-I", str(root / "patches/apply.py"), name, str(work)]).returncode:
                problems.append(f"the {name} patch doesn't apply")
                continue
            for f in qml:
                c, e = scan(f"{name}/{f}", (work / f).read_text(), problems, allow_exception=f"{name}/{f}" == EXCEPTION_FILE)
                built += c
                exceptions += e
    if exceptions != 1:
        problems.append(f"expected exactly one allowed StyledText (the toast body), found {exceptions}")
else:
    print(f"note: no Omarchy plugins at {src}, so the built copies weren't checked")

if problems:
    print("\n".join(problems))
    print("FAIL: rich text possible")
    sys.exit(1)
print(f"ok - all {items} Text items in Overtake's own plugins are plain text; no rich-text item types")
if built:
    print(f"ok - the built copies' {built} Text items are plain text, but for the one toast body fed by Markup.render")
