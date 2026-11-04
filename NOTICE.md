# Notices

Overtake Mode is MIT licensed (see `LICENSE`). Parts of it come from
[Omarchy](https://github.com/omacom/omarchy), which is also MIT licensed:

- `install.sh` builds patched copies of five of Omarchy's own shell plugins
  (workspaces, bluetooth, audio, notifications, battery) from the Omarchy
  installed on your machine, as `~/.config/omarchy/plugins/overtake.*`.
  Those copies are Omarchy's code with Overtake's changes applied; each one
  gets a copy of this notice.
- `patches/apply.py` holds the excerpts of those Omarchy files that its
  replacements look for.
- Some of Overtake's own plugins follow the structure and helpers of
  Omarchy's shell plugins they sit beside (the notification center reads
  Omarchy's notification history; the menu entries extend Omarchy's menu).

Omarchy's license:

```
Copyright (c) David Heinemeier Hansson

Permission is hereby granted, free of charge, to any person obtaining
a copy of this software and associated documentation files (the
"Software"), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
```

## Wallpapers

The pictures in `wallpapers/` were made for this project and are covered by
its MIT license (see `wallpapers/src` for the scripts that draw some of
them). The Studio snow leopard (`wallpapers/studio/7-snow-leopard.jpg`) was
made with an AI image model. Some pictures include the Omarchy logo.
