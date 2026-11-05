"""The hills (day and night) and cave wallpapers as SVG, 3440x1440.

python3 hills-cave.py <folder> writes the .svg files there.
"""
import math
import os
import random
import sys

OUT = sys.argv[1]
ONLY = set(sys.argv[2:])
W, H = 3440, 1440
os.makedirs(OUT, exist_ok=True)

with open("/usr/share/omarchy/icon.txt", encoding="utf-8") as f:
    ICON_ROWS = [line.rstrip("\n") for line in f if line.strip("\n")]
ICON = {(x // 2, y) for y, row in enumerate(ICON_ROWS) for x in range(0, len(row), 2) if row[x] == "█"}

# The Omarchy window, matching the taskbar's Start logo: four 11-cell Omarchy
# marks laid out 2x2, two cells apart, on a 24-cell grid.
MARK_11 = [
    "###########",
    "#....#....#",
    "#.####..#.#",
    "#.#.....#.#",
    "#.#.....#.#",
    "###.....#.#",
    "#.#.....#.#",
    "#.#.....#.#",
    "#.#######.#",
    "#....#....#",
    "######.####",
]
WINDOW_PANES = [(0, 0), (13, 0), (0, 13), (13, 13)]
OMARCHY_WINDOW = {(ox + x, oy + y) for ox, oy in WINDOW_PANES
                  for y, row in enumerate(MARK_11) for x, ch in enumerate(row) if ch == "#"}


def doc(defs, body):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">'
            f'<defs>{defs}</defs>{"".join(body)}</svg>')


def mark(x0, y0, cell, fill, opacity=1.0):
    return "".join(f'<rect x="{x0 + x * cell}" y="{y0 + y * cell}" width="{cell + 0.5}" height="{cell + 0.5}" '
                   f'fill="{fill}" opacity="{opacity}"/>' for x, y in ICON)


def rle(blocks, block, fill, opacity=1.0, extra=""):
    """Merge a set of (bx, by) pixel blocks into one rect per horizontal run."""
    rows = {}
    for bx, by in blocks:
        rows.setdefault(by, []).append(bx)
    out = []
    for by, xs in rows.items():
        xs.sort()
        start = prev = xs[0]
        for bx in xs[1:] + [None]:
            if bx is not None and bx == prev + 1:
                prev = bx
                continue
            out.append(f'<rect x="{start * block}" y="{by * block}" width="{(prev - start + 1) * block + 0.5}" '
                       f'height="{block + 0.5}" fill="{fill}" opacity="{opacity}"{extra}/>')
            if bx is not None:
                start = prev = bx
    return "".join(out)


def inside(poly, x, y):
    hit = False
    for i in range(len(poly)):
        x1, y1 = poly[i]
        x2, y2 = poly[(i + 1) % len(poly)]
        if (y1 > y) != (y2 > y) and x < (x2 - x1) * (y - y1) / (y2 - y1) + x1:
            hit = not hit
    return hit


def raster_poly(poly, block):
    xs, ys = [p[0] for p in poly], [p[1] for p in poly]
    return {(bx, by)
            for bx in range(int(min(xs) // block), int(max(xs) // block) + 1)
            for by in range(int(min(ys) // block), int(max(ys) // block) + 1)
            if inside(poly, bx * block + block / 2, by * block + block / 2)}


def pixel_cloud(cx, cy, r, block, rng):
    """A cumulus cloud: union of blocky circles with a flat base."""
    puffs = [(cx, cy, r)] + [(cx + rng.uniform(-1.6, 1.6) * r, cy + rng.uniform(-0.5, 0.2) * r,
                              r * rng.uniform(0.55, 0.9)) for _ in range(5)]
    blocks = set()
    for px, py, pr in puffs:
        for bx in range(int((px - pr) // block), int((px + pr) // block) + 1):
            for by in range(int((py - pr) // block), int((py + pr) // block) + 1):
                if (bx * block - px) ** 2 + (by * block - py) ** 2 <= pr * pr and by * block <= cy + r * 0.35:
                    blocks.add((bx, by))
    return blocks


# ---------------------------------------------------------------- Hills
def hill_crest(x):
    """One broad hill: crest left of centre, long gentle slope to the right."""
    t = x / W
    width = 0.26 if t < 0.32 else 0.62
    return H * 0.70 - H * 0.19 * math.exp(-((t - 0.32) / width) ** 2)


def hills(night):
    rng = random.Random(11)
    block = 16
    if night:
        sky = [("0", "#0e0f17"), (".55", "#1a1b26"), ("1", "#343b58")]
        bands = ["#3b4466", "#343c5c", "#2e3552", "#283048", "#232a40"]
        field, path, far = "#1f2539", "#14161f", "#2a3150"
        cloud, cloud_shade = "#3b4261", "#30364f"
    else:
        sky = [("0", "#1556c9"), (".5", "#3a8ef0"), ("1", "#b3dcfc")]
        bands = ["#97d64f", "#86cb45", "#76bf3c", "#68b236", "#5aa430"]
        field, path, far = "#4f9f30", "#5b4a2b", "#7fa2c8"
        cloud, cloud_shade = "#ffffff", "#dde9f6"
    stops = "".join(f'<stop offset="{o}" stop-color="{c}"/>' for o, c in sky)
    defs = f'<linearGradient id="sky" x1="0" y1="0" x2="0" y2="1">{stops}</linearGradient>'
    body = [f'<rect width="{W}" height="{H}" fill="url(#sky)"/>']

    if night:
        for _ in range(320):
            size = rng.choice([4, 4, 8])
            body.append(f'<rect x="{rng.randrange(0, W, 8)}" y="{rng.randrange(0, int(H * 0.62), 8)}" '
                        f'width="{size}" height="{size}" fill="#c0caf5" opacity="{rng.uniform(.2, .9):.2f}"/>')
        body.append('<circle cx="2700" cy="300" r="250" fill="#e0af68" opacity=".07"/>'
                    '<circle cx="2700" cy="300" r="160" fill="#e0af68" opacity=".09"/>')
        body.append(mark(2700 - 27 * 9 / 2, 300 - 26 * 9 / 2, 9, "#e0af68"))
    # Cumulus clouds massed on the right like the original.
    for cx, cy, r in [(600, 300, 70), (1500, 380, 90), (2050, 430, 110), (2500, 520, 120), (3100, 300, 130),
                      (3000, 600, 90), (1900, 650, 60), (2700, 700, 70), (300, 520, 50)]:
        blocks = pixel_cloud(cx, cy, r, block, rng)
        shade = {(bx, by) for bx, by in blocks if by * block > cy + r * 0.05}
        body.append(rle(blocks - shade, block, cloud, .9 if night else 1))
        body.append(rle(shade, block, cloud_shade, .9 if night else 1))
    if not night:
        body.append(mark(1020, 120, 8, "#ffffff", .9))  # one cloud is the Omarchy mark

    # Tiny distant mountains peeking past the hill's shoulder on the far right.
    far_blocks = set()
    for bx in range(int(W * 0.86 // block), W // block + 1):
        peak = H * 0.635 - 40 * math.exp(-((bx * block - W * 0.94) / 120) ** 2)
        for by in range(int(peak // block), int(H * 0.68 // block)):
            far_blocks.add((bx, by))
    body.append(rle(far_blocks, block, far))

    # The hill, shaded in pixel contour bands from its sunlit crest downward.
    for i, colour in enumerate(bands):
        blocks = set()
        for bx in range(0, W // block + 1):
            top = round((hill_crest(bx * block) + i * 26 * (1 + bx * block / W)) / block)
            for by in range(top, H // block + 1):
                blocks.add((bx, by))
        body.append(rle(blocks, block, colour))

    # A dirt line and the flat field in front, sprinkled with flowers (fireflies at night).
    body.append(f'<rect x="0" y="{H * 0.82}" width="{W}" height="12" fill="{path}" opacity=".8"/>')
    body.append(f'<rect x="0" y="{H * 0.82 + 12}" width="{W}" height="{H}" fill="{field}"/>')
    for _ in range(140):
        x, y = rng.randrange(0, W, 8), rng.randrange(int(H * 0.84), H, 8)
        body.append(f'<rect x="{x}" y="{y}" width="8" height="8" fill="{"#e0af68" if night else "#ffe24a"}" '
                    f'opacity="{rng.uniform(.4, .9) if night else 1:.2f}"/>')
    return doc(defs, body)


# ---------------------------------------------------------------- Cave
def rock_shapes(scale=1.0, ox=0.0, base=0.0):
    """Two sea stacks: a small one, and a big one whose arch is an Omarchy notch."""
    def tx(points):
        return [(ox + x * scale, base + y * scale) for x, y in points]
    small = tx([(0, 0), (40, -190), (110, -260), (190, -230), (250, -120), (290, 0)])
    big = tx([(420, 0), (450, -220), (520, -420), (600, -470), (690, -400), (760, -210), (800, 0)])
    arch = tx([(560, 0), (560, -130), (660, -130), (660, 0)])  # a square doorway
    return small, big, arch


def beach_scene(block, horizon, rng, rocks_ox, rocks_scale, runner=True):
    body = []
    # Sea and surf.
    body.append(f'<rect x="0" y="{horizon}" width="{W}" height="{H * 0.08 + block * 7}" fill="#1f6fa8"/>')
    for i in range(4):
        y = horizon + H * 0.08 + i * block * 1.5
        for x in range(0, W, block * 3):
            if rng.random() < 0.6:
                body.append(f'<rect x="{x}" y="{y}" width="{block * rng.randint(2, 6)}" height="{block / 2}" '
                            f'fill="#e8f6ff" opacity="{.8 - i * .15:.2f}"/>')
    # Rocks, lit from the left, with grassy tops.
    small, big, arch = rock_shapes(rocks_scale, rocks_ox, horizon + H * 0.08)
    lit, shade, grass = "#d9a35c", "#8a5a33", "#7c9a3c"
    for poly in (small, big):
        blocks = raster_poly(poly, block)
        if poly is big:
            blocks -= raster_poly(arch, block)
        cx = sum(p[0] for p in poly) / len(poly)
        top = min(by for _, by in blocks)
        body.append(rle({b for b in blocks if b[0] * block < cx}, block, lit))
        body.append(rle({b for b in blocks if b[0] * block >= cx}, block, shade))
        body.append(rle({b for b in blocks if b[1] <= top + 1 and rng.random() < 0.9}, block, grass))
    return body, (small, big, arch)


def runner_blocks(block):
    """Running silhouette (about 190px tall), feet at y=0, as pixel blocks."""
    bones = [  # (start, end, radius)
        ((0, -150), (-6, -92), 12),       # torso
        ((2, -142), (22, -118), 6), ((22, -118), (36, -134), 5),     # front arm
        ((-2, -142), (-22, -120), 6), ((-22, -120), (-30, -96), 5),  # back arm
        ((-6, -92), (18, -54), 9), ((18, -54), (30, -10), 7), ((30, -10), (44, -6), 5),       # front leg
        ((-6, -92), (-24, -50), 9), ((-24, -50), (-54, -64), 7), ((-54, -64), (-62, -56), 5),  # back leg
    ]
    head = ((4, -170), 13)

    def near_bone(x, y):
        for (x1, y1), (x2, y2), r in bones:
            dx, dy = x2 - x1, y2 - y1
            t = max(0, min(1, ((x - x1) * dx + (y - y1) * dy) / (dx * dx + dy * dy)))
            if (x - x1 - t * dx) ** 2 + (y - y1 - t * dy) ** 2 <= r * r:
                return True
        (hx, hy), hr = head
        return (x - hx) ** 2 + (y - hy) ** 2 <= hr * hr

    return {(bx, by) for bx in range(-80 // block, 60 // block) for by in range(-190 // block, 1)
            if near_bone(bx * block + block / 2, by * block + block / 2)}


def cave():
    rng = random.Random(33)
    block = 16
    horizon = H * 0.50
    defs = ('<linearGradient id="sky" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#1767c9"/>'
            '<stop offset="1" stop-color="#8fd0f7"/></linearGradient>'
            '<linearGradient id="floor" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#c99559"/>'
            '<stop offset="1" stop-color="#6e4a2b"/></linearGradient>')
    body = [f'<rect width="{W}" height="{horizon}" fill="url(#sky)"/>']
    for cx, cy, r in [(1400, 330, 80), (1750, 260, 60), (2050, 380, 70)]:
        body.append(rle(pixel_cloud(cx, cy, r, block, rng), block, "#ffffff", .9))
    scene, _ = beach_scene(block, horizon, rng, 1250, 1.0)
    body += scene
    body.append(f'<rect x="0" y="{horizon + H * 0.08 + block * 6}" width="{W}" height="{H}" fill="url(#floor)"/>')
    # Composition, from inside the cave: an arched mouth
    # left of centre, a dark boulder filling the lower left, a sunlit wall on
    # the right, and the sand floor running in toward the viewer.
    def frac(points):
        return [(x * W, y * H) for x, y in points]

    mouth = frac([(0.17, 0.66), (0.18, 0.50), (0.22, 0.38), (0.29, 0.27), (0.38, 0.19), (0.50, 0.14),
                  (0.61, 0.16), (0.69, 0.24), (0.74, 0.36), (0.77, 0.52), (0.75, 0.66)])
    floor = frac([(0.30, 0.66), (0.75, 0.66), (0.82, 0.76), (0.92, 0.86), (1.0, 0.90), (1.0, 1.0),
                  (0.46, 1.0), (0.39, 0.86), (0.31, 0.75)])
    nx, ny = W // block + 1, H // block + 1
    visible = raster_poly(mouth, block) | raster_poly(floor, block)
    # Erode the edge a little so the rim reads as rough rock, not a polygon.
    for b in list(visible):
        if any((b[0] + dx, b[1] + dy) not in visible for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))) and rng.random() < 0.35:
            visible.discard(b)

    # Depth: distance (in blocks) from the opening. Rock near the mouth catches
    # the light; it darkens the deeper it sits toward the viewer.
    dist = {b: 0 for b in visible}
    frontier = list(visible)
    while frontier:
        nxt = []
        for bx, by in frontier:
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                n = (bx + dx, by + dy)
                if 0 <= n[0] < nx and 0 <= n[1] < ny and n not in dist:
                    dist[n] = dist[(bx, by)] + 1
                    nxt.append(n)
        frontier = nxt

    def mix(c1, c2, t):
        a = [int(c1[i:i + 2], 16) for i in (1, 3, 5)]
        b = [int(c2[i:i + 2], 16) for i in (1, 3, 5)]
        return "#" + "".join(f"{round(a[i] + (b[i] - a[i]) * t):02x}" for i in range(3))

    buckets = {}
    for (bx, by), d in dist.items():
        if d == 0:
            continue
        # Sunlight on the right wall fades in gradually across the frame.
        sun = max(0.0, min(1.0, (bx * block - W * 0.58) / (W * 0.18))) * (1.0 if by * block < H * 0.92 else 0.3)
        reach = 12 + 22 * sun
        t = max(0.0, min(1.0, (d + rng.uniform(-1.5, 1.5)) / reach)) ** 0.8
        shadow_side = mix("#5a3c24", "#0a0705", t)
        sun_side = mix("#d19a5a", "#2a1a0f", t)
        colour = mix(shadow_side, sun_side, sun)
        buckets.setdefault(colour, set()).add((bx, by))
    for colour, blocks in buckets.items():
        body.append(rle(blocks, block, colour))

    # Shadow across the near floor, darkest right at the viewer's feet.
    defs += ('<linearGradient id="nearShadow" x1="0" y1="0" x2="0" y2="1">'
             '<stop offset="0" stop-color="#000" stop-opacity="0"/><stop offset="1" stop-color="#000" stop-opacity=".75"/>'
             '</linearGradient>')
    body.append(f'<rect x="0" y="{H * 0.80}" width="{W}" height="{H * 0.2}" fill="url(#nearShadow)"/>')
    return doc(defs, body)


walls = {
    "1-hills-day": lambda: hills(night=False),
    "2-hills-night": lambda: hills(night=True),
    "6-cave": cave,
}
for name, build in walls.items():
    if ONLY and name not in ONLY:
        continue
    with open(os.path.join(OUT, name + ".svg"), "w") as f:
        f.write(build())
    print(name)
