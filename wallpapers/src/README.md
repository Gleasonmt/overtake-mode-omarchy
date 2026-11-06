# Wallpaper sources

Overtake's Classic slideshow is drawn by these scripts, written with an AI
assistant for this project (see [NOTICE.md](../../NOTICE.md)). Each redraws its
pictures at 3440x1440 (`python3 <script>.py` writes into the current folder):

- `hero.py` → `hero.svg` (render with `rsvg-convert -w 3440 -h 1440 hero.svg -o 3-shine.png`)
- `beach.py` → `beach.svg`: it adds the chair and umbrella to `beach-base.svg`, a committed drawing no script here makes (render the same way)
- `chips.py` → `chips-grid.ppm`, a 344x144 pixel grid
  (`magick chips-grid.ppm -filter Point -resize 3440x1440! 4-chips.png`)
- `hills-cave.py <folder>` → `1-hills-day.svg`, `2-hills-night.svg` and `6-cave.svg` there
  (render the same way, e.g. `rsvg-convert -w 3440 -h 1440 6-cave.svg -o 6-cave.png`)
