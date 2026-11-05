#!/usr/bin/env python3
# Every QML Text item renders as plain text (`textFormat: Text.PlainText` as
# its own property), so text other programs choose (window titles,
# notification fields, device and file names) can never be read as HTML that
# loads a remote image. No rich-text item types are used at all.
#   python3 -I tests/t-plain-text.py
import pathlib, re, sys

root = pathlib.Path(__file__).resolve().parent.parent
files = sorted(root.glob("plugins/*/*.qml")) + [root / "Setup.qml"]
items = 0
problems = []
for path in files:
    src = path.read_text()
    rel = path.relative_to(root)
    for kind in ("Text.RichText", "Text.StyledText", "Text.MarkdownText"):
        if kind in src:
            problems.append(f"{rel}: uses {kind}")
    for m in re.finditer(r"(?<![A-Za-z.])(Label|ToolTip|TextEdit|TextArea)\s*\{", src):
        problems.append(f"{rel}:{src[:m.start()].count(chr(10)) + 1}: uses {m.group(1)}")
    # Every `Text {` (also `component X: Text {`): its own properties, nested
    # blocks left out, must set PlainText.
    for m in re.finditer(r"(?<![A-Za-z.])Text\s*\{", src):
        items += 1
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
        if not re.search(r"\btextFormat:\s*Text\.PlainText\b", "".join(own)):
            problems.append(f"{rel}:{src[:m.start()].count(chr(10)) + 1}: Text without textFormat: Text.PlainText")

if problems:
    print("\n".join(problems))
    print("FAIL: rich text possible")
    sys.exit(1)
print(f"ok - all {items} Text items are plain text; no rich-text item types")
