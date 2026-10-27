# Studio look wallpapers: smooth gradients and layered shapes, drawn as SVG.
#   python3 studio.py            -> writes studio-*.svg into the current folder
#   for f in studio-*.svg; do rsvg-convert -w 3440 -h 1440 "$f" -o "${f#studio-}"; done
# (then rename to .png: 1-mesa-day.png, 2-mesa-night.png, ...)
import math, random

W, H = 3440, 1440


def wave(base, amp, length, phase, step=40, extra=None):
    """A smooth ridge line across the width, closed down to the bottom."""
    pts = []
    for x in range(-step, W + 2 * step, step):
        y = base + amp * math.sin(x / length + phase)
        if extra:
            y += extra(x)
        pts.append((x, y))
    d = "M %d %d " % (pts[0][0], H + 10)
    d += " ".join("L %.1f %.1f" % p for p in pts)
    d += " L %d %d Z" % (pts[-1][0], H + 10)
    return d


def svg(defs, body):
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">'
            '<defs>%s</defs>%s</svg>') % (W, H, W, H, defs, body)


def grad(id_, stops, x2="0", y2="1", x1="0", y1="0"):
    s = "".join('<stop offset="%s" stop-color="%s"/>' % st for st in stops)
    return '<linearGradient id="%s" x1="%s" y1="%s" x2="%s" y2="%s">%s</linearGradient>' % (id_, x1, y1, x2, y2, s)


# Flat-topped buttes with a soft shoulder: a mesa skyline.
def mesa_line(base, tops, slope=90):
    d = "M -10 %d L -10 %d " % (H + 10, base)
    for left, right, top in tops:
        d += "L %d %d L %d %d L %d %d L %d %d " % (left - slope, base, left, top, right, top, right + slope, base)
    d += "L %d %d L %d %d Z" % (W + 10, base, W + 10, H + 10)
    return d


def mesa(night):
    halo = '<radialGradient id="halo"><stop offset="0" stop-color="#fff4d6" stop-opacity=".55"/><stop offset="1" stop-color="#fff4d6" stop-opacity="0"/></radialGradient>'
    sky = grad("sky", [("0", "#0b1434" if night else "#4f9fe8"), (".6", "#2a2f6b" if night else "#a9d4f5"), ("1", "#7a4a7d" if night else "#f6d7b0")])
    far = grad("far", [("0", "#3b2f5c" if night else "#d98e63"), ("1", "#2a2148" if night else "#c4704a")])
    mid = grad("mid", [("0", "#4a2f4f" if night else "#c2603a"), ("1", "#2e1d36" if night else "#9c4428")])
    near = grad("near", [("0", "#2b1a2c" if night else "#8f3a22"), ("1", "#160c18" if night else "#5e2213")])
    body = '<rect width="%d" height="%d" fill="url(#sky)"/>' % (W, H)
    if night:
        random.seed(7)
        for _ in range(420):
            x, y, r = random.uniform(0, W), random.uniform(0, H * 0.62), random.choice([1.2, 1.6, 2.2, 3])
            body += '<circle cx="%.0f" cy="%.0f" r="%.1f" fill="#ffffff" opacity="%.2f"/>' % (x, y, r, random.uniform(0.35, 0.95))
        body += '<circle cx="2620" cy="300" r="74" fill="#f4f1e6"/>'
        body += '<circle cx="2620" cy="300" r="260" fill="url(#halo)" opacity=".35"/>'
    else:
        body += '<circle cx="2700" cy="330" r="460" fill="url(#halo)"/><circle cx="2700" cy="330" r="120" fill="#fff6dc"/>'
    body += '<path d="%s" fill="url(#far)"/>' % mesa_line(980, [(300, 760, 760), (1500, 1800, 820), (2380, 3050, 700)], 140)
    body += '<path d="%s" fill="url(#mid)"/>' % mesa_line(1120, [(-60, 420, 900), (1050, 1420, 940), (2050, 2300, 880), (2900, 3600, 960)], 110)
    body += '<path d="%s" fill="url(#near)"/>' % wave(1260, 26, 380, 1.3)
    return svg(halo + sky + far + mid + near, body)


def ribbons():
    defs = grad("bg", [("0", "#120b2e"), (".5", "#1d1550"), ("1", "#0a1f3d")], x2="1", y2="1")
    colours = [("#7c5cff", "#36d1dc"), ("#ff6ec7", "#7c5cff"), ("#2ee6a6", "#1e90ff"), ("#ffb86b", "#ff5f6d")]
    for i, (a, b) in enumerate(colours):
        defs += grad("r%d" % i, [("0", a), ("1", b)], x2="1", y2="0")
    defs += '<filter id="soft" filterUnits="userSpaceOnUse" x="-600" y="-600" width="4640" height="2640"><feGaussianBlur stdDeviation="6"/></filter><filter id="glow" filterUnits="userSpaceOnUse" x="-600" y="-600" width="4640" height="2640"><feGaussianBlur stdDeviation="60"/></filter>'
    body = '<rect width="%d" height="%d" fill="url(#bg)"/>' % (W, H)
    for i in range(4):
        base = 520 + i * 170
        top = []
        bottom = []
        for x in range(-100, W + 200, 40):
            y = base + 210 * math.sin(x / (560 + i * 70) + i * 1.1) + 60 * math.sin(x / 190 + i)
            thick = 70 + 50 * math.sin(x / 700 + i * 2)
            top.append((x, y))
            bottom.append((x, y + thick))
        d = "M " + " L ".join("%.1f %.1f" % p for p in top) + " L " + " L ".join("%.1f %.1f" % p for p in reversed(bottom)) + " Z"
        body += '<path d="%s" fill="url(#r%d)" opacity=".28" filter="url(#glow)"/>' % (d, i)
        body += '<path d="%s" fill="url(#r%d)" opacity=".85" filter="url(#soft)"/>' % (d, i)
    return svg(defs, body)


def aurora():
    defs = grad("sky", [("0", "#020617"), (".55", "#06233a"), ("1", "#0b3a4a")])
    defs += '<filter id="blur" filterUnits="userSpaceOnUse" x="-600" y="-600" width="4640" height="2640"><feGaussianBlur stdDeviation="40"/></filter><filter id="blur2" filterUnits="userSpaceOnUse" x="-600" y="-600" width="4640" height="2640"><feGaussianBlur stdDeviation="14"/></filter>'
    body = '<rect width="%d" height="%d" fill="url(#sky)"/>' % (W, H)
    random.seed(3)
    for _ in range(300):
        body += '<circle cx="%.0f" cy="%.0f" r="%.1f" fill="#fff" opacity="%.2f"/>' % (random.uniform(0, W), random.uniform(0, H * 0.7), random.choice([1, 1.5, 2]), random.uniform(.3, .9))
    for i, (col, op) in enumerate([("#22ffb0", .55), ("#3fd0ff", .35), ("#b46bff", .3)]):
        pts = []
        for x in range(-100, W + 200, 60):
            pts.append((x, 380 + i * 60 + 140 * math.sin(x / 420 + i * 1.7) + 50 * math.sin(x / 150)))
        d = "M " + " L ".join("%.1f %.1f" % p for p in pts)
        body += '<path d="%s" stroke="%s" stroke-width="%d" fill="none" opacity="%.2f" filter="url(#blur)"/>' % (d, col, 180 - i * 30, op)
        body += '<path d="%s" stroke="%s" stroke-width="10" fill="none" opacity="%.2f" filter="url(#blur2)"/>' % (d, col, op)
    body += '<path d="%s" fill="#06141f"/>' % wave(1060, 120, 300, 0.4, extra=lambda x: 90 * abs(math.sin(x / 520)) * -1)
    body += '<path d="%s" fill="#030b12"/>' % wave(1220, 50, 240, 2.0)
    # still water with the sky's colour in it
    body += '<rect y="1300" width="%d" height="140" fill="#0a2a36" opacity=".9"/>' % W
    return svg(defs, body)


def orbs():
    defs = grad("bg", [("0", "#f3e8ff"), (".5", "#e0f2fe"), ("1", "#fde2e4")], x2="1", y2="1")
    defs += '<filter id="blur" filterUnits="userSpaceOnUse" x="-600" y="-600" width="4640" height="2640"><feGaussianBlur stdDeviation="120"/></filter>'
    body = '<rect width="%d" height="%d" fill="url(#bg)"/>' % (W, H)
    for cx, cy, r, col in [(700, 420, 520, "#a78bfa"), (1700, 980, 600, "#60a5fa"), (2700, 380, 560, "#f472b6"), (3100, 1150, 420, "#fbbf24"), (300, 1200, 380, "#34d399")]:
        body += '<circle cx="%d" cy="%d" r="%d" fill="%s" opacity=".55" filter="url(#blur)"/>' % (cx, cy, r, col)
    return svg(defs, body)


def sunrise():
    """Soft arcs rising from below the bottom edge, warm to cool."""
    defs = grad("bg", [("0", "#1b1640"), (".55", "#5b2a6e"), ("1", "#f08a5d")])
    defs += '<filter id="blur" filterUnits="userSpaceOnUse" x="-600" y="-600" width="4640" height="2640"><feGaussianBlur stdDeviation="10"/></filter>'
    body = '<rect width="%d" height="%d" fill="url(#bg)"/>' % (W, H)
    colours = ["#2d2463", "#4a2c7a", "#6e3385", "#94418a", "#b9528a", "#d96a7f", "#ee8a72", "#f8ad6a", "#fdd08a"]
    for i, c in enumerate(colours):
        r = 2300 - i * 230
        body += '<circle cx="%d" cy="%d" r="%d" fill="%s" opacity=".9" filter="url(#blur)"/>' % (W * 0.62, H + 380, r, c)
    return svg(defs, body)


for name, data in [("1-mesa-day", mesa(False)), ("2-mesa-night", mesa(True)), ("3-ribbons", ribbons()),
                   ("4-aurora", aurora()), ("5-orbs", orbs()), ("6-sunrise", sunrise())]:
    open("studio-%s.svg" % name, "w").write(data)
