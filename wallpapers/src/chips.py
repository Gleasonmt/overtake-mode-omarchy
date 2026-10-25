# Pixel-art Pringles-style chips flying out of a plain can on the left.
# Drawn on a 344x144 grid (one cell = 10px of the 3440x1440 wallpaper).
import math, random
W, H = 344, 144
img = [[None] * W for _ in range(H)]
zbuf = [[-1e9] * W for _ in range(H)]

# Background: dark navy, a soft banded glow (the 8-bit look comes from the bands).
for y in range(H):
    for x in range(W):
        d = math.hypot((x - 190) / 190, (y - 70) / 90)
        band = min(4, int(d * 4))
        img[y][x] = ["#1c1838", "#171430", "#131128", "#100e22", "#0c0b1b"][band]

def mix(c, k):  # darken/lighten a hex colour
    r, g, b = (int(c[i:i + 2], 16) for i in (1, 3, 5))
    f = lambda v: max(0, min(255, int(v * k)))
    return "#%02x%02x%02x" % (f(r), f(g), f(b))

# ---- the can: mostly off-screen left, opening tilted up to the right
t = math.radians(16)
ax, ay = math.cos(t), -math.sin(t)          # axis toward the opening
ox, oy, R, L = 24, 92, 21, 60               # opening centre, radius, length (cells)
RED, REDL, REDD, GOLD, RIM, INSIDE = "#b8232f", "#d9474f", "#7d1621", "#e3bb55", "#d4d8de", "#24120d"
for y in range(H):
    for x in range(W):
        px, py = x - ox, y - oy
        s = px * ax + py * ay               # along the axis (0 at the opening)
        p = -px * ay + py * ax              # across it
        if -L < s <= 0 and abs(p) <= R:
            c = REDL if p < -R * 0.45 else (REDD if p > R * 0.55 else RED)
            if -9 <= s <= -6: c = GOLD
            img[y][x] = c
        # the opening: an ellipse, rim then dark inside
        e = (p / R) ** 2 + (s / (R * 0.38)) ** 2
        if e <= 1.0:
            img[y][x] = INSIDE if e <= 0.62 else RIM

# ---- the chips: hyperbolic-paraboloid saddles, shaded by their normals
def chip(cx, cy, size, yaw, pitch, roll, seed):
    rnd = random.Random(seed)
    a, b, k = 1.0, 0.74, 0.46
    ry, rp, rr = map(math.radians, (yaw, pitch, roll))
    def rot(v):
        x, y, z = v
        x, z = x * math.cos(ry) + z * math.sin(ry), -x * math.sin(ry) + z * math.cos(ry)
        y, z = y * math.cos(rp) - z * math.sin(rp), y * math.sin(rp) + z * math.cos(rp)
        x, y = x * math.cos(rr) - y * math.sin(rr), x * math.sin(rr) + y * math.cos(rr)
        return x, y, z
    light = (-0.45, -0.65, 0.6)
    ln = math.sqrt(sum(c * c for c in light)); light = tuple(c / ln for c in light)
    specks = {(rnd.randrange(0, 60), rnd.randrange(0, 60)) for _ in range(14)}
    steps = max(60, int(size * 5))
    for i in range(steps + 1):
        r = i / steps
        for j in range(steps * 3):
            th = 2 * math.pi * j / (steps * 3)
            X, Y = a * r * math.cos(th), b * r * math.sin(th)
            Z = k * ((X / a) ** 2 - (Y / b) ** 2)
            n = rot((-2 * k * X / a ** 2, 2 * k * Y / b ** 2, 1.0))
            x, y, z = rot((X, Y, Z))
            gx, gy = int(round(cx + x * size)), int(round(cy + y * size))
            if not (0 <= gx < W and 0 <= gy < H) or z <= zbuf[gy][gx]: continue
            zbuf[gy][gx] = z
            nl = math.sqrt(sum(c * c for c in n))
            lam = abs(sum(n[q] / nl * light[q] for q in range(3))) ** 1.6
            c = ["#8f5118", "#c07a26", "#dea040", "#f0c264", "#fbe2a0"][min(4, int(lam * 5.6))]
            if r > 0.9: c = mix(c, 0.8)                          # baked edge
            if r < 0.85 and (gx * 73856093 ^ gy * 19349663 ^ seed * 83492791) % 29 == 0: c = mix(c, 0.74)  # seasoning
            img[gy][gx] = c

# Smallest at the can, growing as they fly right along an arc.
chips = [  # cx, cy, size, yaw, pitch, roll
    (54, 74, 9, 30, 35, -25), (84, 58, 13, -25, 30, 20), (120, 50, 17, 40, 40, -15),
    (162, 56, 21, -35, 28, 30), (210, 68, 26, 25, 42, -20), (264, 62, 31, -20, 32, 12),
]
for n, c in enumerate(chips): chip(*c, seed=n)

# The Omarchy logo, bottom right, drawn on the grid.
MARK = ["###########","#....#....#","#.####..#.#","#.#.....#.#","#.#.....#.#","###.....#.#",
        "#.#.....#.#","#.#.....#.#","#.#######.#","#....#....#","######.####"]
for yy, row in enumerate(MARK):
    for xx, ch in enumerate(row):
        if ch == "#": img[121 + yy][318 + xx] = "#8b90ab"

with open("chips-grid.ppm", "w") as f:
    f.write("P3\n%d %d\n255\n" % (W, H))
    for row in img:
        f.write(" ".join("%d %d %d" % tuple(int(c[i:i + 2], 16) for i in (1, 3, 5)) for c in row) + "\n")
