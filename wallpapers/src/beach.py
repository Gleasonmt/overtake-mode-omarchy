# Swap the beach runner for someone in a beach chair under an umbrella,
# seen from behind looking out to sea, on the same 4px grid and spot.
import os, re, math
SRC = os.path.join(os.path.dirname(os.path.abspath(__file__)), "beach-base.svg")
U = 4
cells = {}  # (cx, cy) in grid units, origin at the feet line, y up = negative

def put(x, y, color):
    cells[(int(math.floor(x / U)), int(math.floor(y / U)))] = color

def fill(test, x0, x1, y0, y1, color):
    for gx in range(int(x0 // U), int(x1 // U) + 1):
        for gy in range(int(y0 // U), int(y1 // U) + 1):
            x, y = gx * U + U / 2, gy * U + U / 2
            c = test(x, y)
            if c: cells[(gx, gy)] = c if isinstance(c, str) else color

SIL = "#141824"; RED = "#e2574c"; WHITE = "#f4efe6"; POLE = "#5b4a3a"
FABRIC = "#2c8fb0"; FABRIC2 = "#e9e2d0"; WOOD = "#8a5a34"; STRAW = "#d9b26b"; BAND = "#c0392b"

# Umbrella pole (planted in the sand, leaning a touch), then the canopy.
fill(lambda x, y: abs(x - (-62 - y * 0.1)) < 3.5, -70, -30, -250, 0, POLE)
cx, cy, rx, ry = -34, -244, 128, 54
def canopy(x, y):
    if y > cy or ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 > 1: return None
    if y > cy - 6: return WHITE if int((x - cx + rx) // 6) % 2 == 0 else None  # scalloped edge
    seg = int((math.atan2(y - cy - 40, x - cx) + math.pi) / (math.pi / 7))
    return RED if seg % 2 == 0 else WHITE
fill(canopy, cx - rx, cx + rx, cy - ry, cy, None)
fill(lambda x, y: abs(x - cx) < 5 and cy - ry - 10 < y < cy - ry + 2, cx - 8, cx + 8, cy - ry - 12, cy - ry, POLE)

# Beach chair, seen from the back: striped fabric in a wooden frame.
fill(lambda x, y: -44 <= x <= -38 or 38 <= x <= 44, -44, 44, -36, 0, WOOD)            # legs
fill(lambda x, y: (-44 <= x <= 44) and (-118 <= y <= -112), -44, 44, -118, -112, WOOD) # top rail
fill(lambda x, y: (-44 <= x <= 44) and (-40 <= y <= -34), -44, 44, -40, -34, WOOD)     # bottom rail
fill(lambda x, y: (FABRIC if int((x + 40) // 12) % 2 == 0 else FABRIC2) if (-38 <= x <= 38 and -112 < y < -40) else None, -38, 38, -112, -40, None)
fill(lambda x, y: (-60 <= x <= -44 or 44 <= x <= 60) and (-76 <= y <= -70), -60, 60, -76, -70, WOOD)   # armrests
fill(lambda x, y: (-60 <= x <= -55 or 55 <= x <= 60) and (-70 <= y <= 0), -60, 60, -70, 0, WOOD)       # front legs

# The sitter: shoulders above the chair back, arms on the armrests, a straw sun hat.
fill(lambda x, y: ((x / 34) ** 2 + ((y + 120) / 18) ** 2 <= 1) and y >= -128, -34, 34, -138, -104, SIL)  # shoulders
fill(lambda x, y: 40 <= abs(x) <= 47 and -110 <= y <= -76, -50, 50, -110, -76, SIL)        # arms
fill(lambda x, y: (x / 15) ** 2 + ((y + 146) / 17) ** 2 <= 1, -16, 16, -164, -128, SIL)                  # head
fill(lambda x, y: (x / 34) ** 2 + ((y + 158) / 6) ** 2 <= 1, -34, 34, -166, -150, STRAW)                 # brim
fill(lambda x, y: (x / 16) ** 2 + ((y + 168) / 12) ** 2 <= 1 and y <= -160, -16, 16, -182, -158, STRAW) # crown
fill(lambda x, y: abs(x) <= 15 and -163 <= y <= -159, -16, 16, -164, -158, BAND)                        # hat band

# Merge horizontal runs into rects, like the rest of the file.
rows = {}
for (gx, gy), c in cells.items(): rows.setdefault(gy, {})[gx] = c
rects = []
for gy in sorted(rows):
    xs = sorted(rows[gy]); i = 0
    while i < len(xs):
        j = i; c = rows[gy][xs[i]]
        while j + 1 < len(xs) and xs[j + 1] == xs[j] + 1 and rows[gy][xs[j + 1]] == c: j += 1
        rects.append('<rect x="%d" y="%d" width="%.1f" height="%.1f" fill="%s" opacity="1.0"/>' % (xs[i] * U, gy * U, (xs[j] - xs[i] + 1) * U + 0.5, U + 0.5, c))
        i = j + 1
sprite = "".join(rects)

s = open(SRC).read()
for opener in ['<g transform="translate(1060 1152.0)">', '<g transform="translate(1060 1152.0) scale(1 -1)" opacity=".3" filter="url(#blur)">']:
    a = s.index(opener) + len(opener); b = s.index("</g>", a)
    s = s[:a] + sprite + s[b:]
open("beach.svg", "w").write(s)
print(len(rects), "rects")
