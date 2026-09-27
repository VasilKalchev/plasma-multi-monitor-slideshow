# AGENTS.md

Notes for coding agents (and people) working on this repository.

## What this is

A KDE Plasma 6 wallpaper plugin (KPackage, `KPackageStructure:
Plasma/Wallpaper`, ID `com.github.vasilkalchev.multimonitorslideshow`) written in plain
QML. It runs one slideshow across all monitors: spanned images across
every monitor together, individual images one per monitor. Read
[docs/how-it-works.md](docs/how-it-works.md) for the architecture and
[docs/cropping.md](docs/cropping.md) for the span placement math before
changing either.

## Development setup

Plasma discovers wallpaper plugins in
`~/.local/share/plasma/wallpapers/<id>/`, so the usual setup is a clone at
`~/.local/share/plasma/wallpapers/com.github.vasilkalchev.multimonitorslideshow`: the
working copy is then the live plugin, with no build or install step.

- **Apply a `.qml` edit**: `systemctl --user restart plasma-plasmashell.service`.
  QML is cached by file path; switching the wallpaper type off and on only
  re-reads settings, not code. Don't use `kquitapp6 plasmashell` plus a
  manual relaunch: it takes the shell out of systemd's control.
- **Never run `kpackagetool6 -i`/`-u` on the working copy's own path.** It
  can wipe the directory instead of updating it. To test a package, build
  one with `utils/package.sh` and install it into a scratch root with
  `kpackagetool6 -t Plasma/Wallpaper -p <dir> -i <archive>`.
- **Logs**: `console.info()`/`console.warn()` and QML errors from the
  wallpaper reach `journalctl --user -u plasma-plasmashell.service`.
  `console.log()` is debug level and filtered out; to see it, add a
  drop-in `~/.config/systemd/user/plasma-plasmashell.service.d/*.conf`
  with `[Service]` / `Environment=QT_LOGGING_RULES=qml.debug=true`, then
  `systemctl --user daemon-reload` and restart the shell.
- **Settings page**: it appears in two windows. System Settings →
  Wallpaper (`kcmshell6 kcm_wallpaper`) runs in its own process, loads
  `config.qml` fresh with no shell restart, and logs to the system journal
  (`journalctl _COMM=kcmshell6`); it is narrower. The desktop's
  right-click → Desktop and Wallpaper (Desktop Folder Settings) runs
  inside plasmashell, so it needs a shell restart and logs with the shell;
  open it with `qdbus org.kde.plasmashell /PlasmaShell
  org.kde.PlasmaShell.evaluateScript 'desktops()[0].showConfigurationInterface()'`.
  Check layout changes in both. Plasma creates the page twice (a throwaway
  copy to find the `cfg_` properties, then the real one), so
  `Component.onCompleted` runs twice.
- `main.qml` can't run under the `qml` tool (it needs `WallpaperItem` and
  Plasma's imports), so verifying means restarting the shell.
- **Release**: bump `Version` in `metadata.json`, commit, tag
  `v<version>`, and run `utils/package.sh` for the archive to upload. The
  KDE Store thumbnail (also the README's and the site's picture) is
  `docs/images/preview.png`, drawn by `utils/make-preview.py` (needs
  Inkscape and ImageMagick).

## Gotchas

- **Settings**: every setting the page edits must be in `main.xml`, have a
  `cfg_<Name>` and `cfg_<Name>Default` property in `config.qml`, call
  `stamp()` when edited, and be listed in `sharedKeys` in `main.qml`, or it
  won't be shared across screens (see "One set of settings" in
  how-it-works.md).
- **Translations domain**: every `i18nd()` uses
  `"plasma_wallpaper_com.github.vasilkalchev.multimonitorslideshow"`.
- **FolderListModel** must get its `folder` at construction (an
  `Instantiator` with the folder as its model) and never be reassigned. A
  new model starts scanning its default folder at once; reassigning
  `folder` before that finishes delivers a `Ready` carrying the old
  folder's rows, and every later `Ready` is off by one. Empty, missing and
  unreadable folders all reach `Ready` with 0 rows.
- **Scan claims** (`SpanState.claimScan()`): one screen scans per config
  and tick. A claim that hasn't finished within 30 s is taken over,
  because Plasma destroys and rebuilds wallpaper items when displays
  change, and the claiming item can vanish mid-scan.
- **`property var` arrays** don't reliably notify on in-place mutation
  (`.push()`, `.shift()`, index assignment). Always assign a new array
  (`.slice()` and modify the copy).
- **`Qt.callLater`** merges repeated calls with the same function, so code
  that every screen must run passes a fresh closure
  (`function () { root.x(); }`).
- **A layer's `geom` is not a binding** (`ImageLayer.qml`). It is
  computed on image load, on probe results, at every tick, and (debounced
  1.5 s) when `screenLayout` changes. A new input to `computeGeomFor()`
  needs a matching refresh.
- **Layer handover**: only `pending` (the layer a new picture loads into)
  can become `front`, and only once it is Ready and, for a spanned
  picture, measured. A geometry change makes both layers decode again; if
  any Ready could take over, the faded-out layer's old picture came back.
  A layer that has faded out lets go of its picture.
- **Pre-split layers use `Image.Stretch`**, not `PreserveAspectCrop`: the
  latter re-crops around the layer's own center, which drifts the seam off
  the bezel on every screen but the largest.
- **Probes** decode at `sourceSize: Qt.size(1024, 0)`, and the natural
  size is read from `implicitWidth`/`implicitHeight` (`sourceSize` reads
  back the requested size). Only the aspect ratio is used.
- **Screen identity** comes from the connector name (`Screen.name`), not
  the position, which changes during every display reconfiguration.
- **Thumbnails** (`FolderImages.qml`): Qt decodes asynchronous images on
  one thread, newest request first, so the grid starts them itself, two at
  a time, visible cells first. Freedesktop thumbnail files are named by
  the MD5 of the file URI encoded as
  `encodeURI(decodeURIComponent(url))` with `?` → `%3F` and `#` → `%23`.
  QML can't write freedesktop thumbnails (they need PNG metadata) or make
  directories, so the plugin keeps its own cache and runs `mkdir -p` (and
  the 60-day prune) through the plasma5support "executable" engine. An
  `Image` showing a `grabToImage()` result must not get a `sourceSize`.
- **Physical sizes can't be checked in screenshots**, which count pixels.
  Use `utils/span-test-5120x1440.png` (two 16:9 halves with lines and
  400 px shapes on both sides of the seam, made by `make-span-test.sh`)
  and a ruler: a 400 px square should measure 400 / f px on a monitor
  with factor f, and the lines should continue straight across the bezel.
