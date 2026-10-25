# One large Omarchy logo, a glowing glass pane high in the top right, its
# light shining down across the room.
MARK = ["###########","#....#....#","#.####..#.#","#.#.....#.#","#.#.....#.#","###.....#.#",
        "#.#.....#.#","#.#.....#.#","#.#######.#","#....#....#","######.####"]
# Pane corners (perspective quad): top-left, top-right, bottom-right, bottom-left.
TL, TR, BR, BL = (2560, 120), (3120, 60), (3150, 560), (2590, 610)
def at(u, v):  # bilinear point on the quad, u,v in 0..1
    top = (TL[0] + (TR[0]-TL[0])*u, TL[1] + (TR[1]-TL[1])*u)
    bot = (BL[0] + (BR[0]-BL[0])*u, BL[1] + (BR[1]-BL[1])*u)
    return (top[0] + (bot[0]-top[0])*v, top[1] + (bot[1]-top[1])*v)
def quad(u0, v0, u1, v1):
    pts = [at(u0, v0), at(u1, v0), at(u1, v1), at(u0, v1)]
    return " ".join("%.1f,%.1f" % p for p in pts)
pad = 0.07
cell = (1 - 2*pad) / 11
cells = []
for y, row in enumerate(MARK):
    for x, c in enumerate(row):
        if c == "#":
            cells.append('<polygon points="%s" fill="#eaf6ff"/>' % quad(pad + x*cell, pad + y*cell, pad + (x+1)*cell + 0.002, pad + (y+1)*cell + 0.002))
pane = " ".join("%d,%d" % p for p in (TL, TR, BR, BL))
svg = f'''<svg xmlns="http://www.w3.org/2000/svg" width="3440" height="1440" viewBox="0 0 3440 1440">
<defs>
<radialGradient id="room" cx=".82" cy=".25" r=".95"><stop offset="0" stop-color="#0b3b8f"/><stop offset=".45" stop-color="#062561"/><stop offset="1" stop-color="#020a22"/></radialGradient>
<linearGradient id="beam" gradientUnits="userSpaceOnUse" x1="2870" y1="360" x2="1700" y2="1440"><stop offset="0" stop-color="#7cc8ff" stop-opacity=".62"/><stop offset=".6" stop-color="#2f7fe0" stop-opacity=".16"/><stop offset="1" stop-color="#2f7fe0" stop-opacity="0"/></linearGradient>
<linearGradient id="glass" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#9fdcff"/><stop offset="1" stop-color="#3f9bff"/></linearGradient>
<filter id="glow" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="70"/></filter>
<filter id="haze"><feGaussianBlur stdDeviation="18"/></filter>
<filter id="smoke"><feGaussianBlur stdDeviation="90"/></filter>
<filter id="soft"><feGaussianBlur stdDeviation="2.2"/></filter>
</defs>
<rect width="3440" height="1440" fill="url(#room)"/>
<ellipse cx="2300" cy="1250" rx="1300" ry="200" fill="#4aa0ff" opacity="0.12" filter="url(#smoke)"/>
<ellipse cx="1500" cy="900" rx="1000" ry="220" fill="#4aa0ff" opacity="0.07" filter="url(#smoke)"/>
<ellipse cx="2700" cy="700" rx="600" ry="300" fill="#4aa0ff" opacity="0.06" filter="url(#smoke)"/>
<polygon points="{TL[0]},{TL[1]} {BL[0]},{BL[1]} {BR[0]},{BR[1]} 3600,1500 600,1500" fill="url(#beam)" filter="url(#haze)"/>
<polygon points="{BL[0]+120},{BL[1]} {BR[0]-140},{BR[1]} 3000,1500 1500,1500" fill="url(#beam)" opacity=".55" filter="url(#haze)"/>
<polygon points="{pane}" fill="#5fb6ff" opacity=".7" filter="url(#glow)"/>
<polygon points="{pane}" fill="url(#glass)" opacity=".93"/>
<g filter="url(#soft)">{"".join(cells)}</g>
</svg>'''
open("hero.svg", "w").write(svg)
