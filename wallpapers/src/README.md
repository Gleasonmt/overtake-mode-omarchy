# Wallpaper sources

Overtake's slideshow wallpapers were made for this project with an AI image
model (see [NOTICE.md](../../NOTICE.md)). These scripts redraw three of them at 3440x1440 (`python3 <script>.py` writes into the current folder):

- `hero.py` → `hero.svg` (render with `rsvg-convert -w 3440 -h 1440 hero.svg -o 3-shine.png`)
- `beach.py` → `beach.svg` from `beach-base.svg` (render the same way)
- `chips.py` → `chips-grid.ppm`, a 344x144 pixel grid
  (`magick chips-grid.ppm -filter Point -resize 3440x1440! 4-chips.png`)

The hills and cave images have no generator kept.
