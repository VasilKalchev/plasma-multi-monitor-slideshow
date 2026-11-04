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

Plasma loads wallpaper plugins from
`~/.local/share/plasma/wallpapers/<id>/`. Keep the clone somewhere else
and install from it with `utils/deploy.sh`, which copies the files the
release archive holds (metadata.json, contents/, LICENSE, README.md) there
and restarts plasmashell. The desktop then only runs what was deployed,
not every half-made edit, and the installed plugin matches a release. The
script refuses to replace a folder that is a git checkout.

- **Apply a `.qml` edit**: `utils/deploy.sh`. QML is cached by file path
  for the life of the shell; switching the wallpaper type off and on only
  re-reads settings, not code. `utils/deploy.sh --no-restart` only copies,
  which is enough for `kcmshell6 kcm_wallpaper` (see below). Don't use
  `kquitapp6 plasmashell` plus a manual relaunch: it takes the shell out of
  systemd's control; the script uses
  `systemctl --user restart plasma-plasmashell.service`.
- **Don't install with `kpackagetool6 -i`/`-u` pointed at the clone.** It
  copies the whole folder, .git and docs included, and once wiped the
  folder it was pointed at instead of updating it. To test a release
  archive, build one with `utils/package.sh` and install it into a scratch
  root with `kpackagetool6 -t Plasma/Wallpaper -p <dir> -i <archive>`.
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
  inside plasmashell, so it needs a deploy with the restart and logs with
  the shell; open it with `qdbus org.kde.plasmashell /PlasmaShell
  org.kde.PlasmaShell.evaluateScript 'desktops()[0].showConfigurationInterface()'`.
  Check layout changes in both. Plasma creates the page twice (a throwaway
  copy to find the `cfg_` properties, then the real one), so
  `Component.onCompleted` runs twice.
- `main.qml` can't run under the `qml` tool (it needs `WallpaperItem` and
  Plasma's imports), so verifying means deploying and restarting the
  shell.
- **Screenshots of the settings** (`docs/images/settings.png`, the
  Desktop Folder Settings dialog, and `monitor-sizes.png`) are
  `grabToImage()` captures made from inside the page, so no other window
  can end up in them. Copy the plugin files (with `utils/`) to a scratch
  folder, add a temporary `Timer` to that copy's `config.qml` that sets
  `root.Window.window` to 1180×840 and `cfg_SinglePaths`/`cfg_SpanPaths`
  to the folders to show, waits for the thumbnails, then grabs the
  dialog's top item (walk `parent` up from `root` to the child of
  `win.contentItem`; the `contentItem` itself can't be grabbed) and, with
  the popup open, `sizesPopup.contentItem.parent`. The folder list shows
  the real paths, so to keep your user name out of it, have the copy's
  `localPath()` in `FolderListSection.qml` show the home folder as
  `/home/user` (`.replace(/^\/home\/[^/]+/, "/home/user")`). Run the
  copy's `utils/deploy.sh`, open the dialog with the `qdbus …
  evaluateScript` line above, and when the files are written, run
  `utils/deploy.sh` from the repo: the restart closes the dialog without
  applying.
- **Release**: bump `Version` in `metadata.json`, commit, tag
  `v<version>`, push the tag, and run `utils/package.sh` for the archive.
  Attach it to a GitHub release (`gh release create v<version>
  <archive>`) and upload it on the KDE Store product's Files tab, with a
  changelog entry. The store product (https://store.kde.org/p/2375225/) is in **Plasma 6 Extensions ›
  Plasma 6 Wallpaper Plugins**, the category Get New Plugins… reads. Its
  thumbnail (also the README's and the site's picture) is
  `docs/images/preview.png`, drawn by `utils/make-preview.py` (needs
  Inkscape and ImageMagick); `settings.png` is its second screenshot, and
  its logo is the preview with a larger name on a transparent background, drawn by `utils/make-logo.py` (needs cairosvg, pillow and numpy; `store/logo.png` in the notes folder). The website is
  GitHub Pages, served from `docs/` on `main`.

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
  folder's rows, and every later `Ready` is off by one. Empty and
  unreadable folders reach `Ready` with 0 rows, but a missing one (or a
  URL that isn't a local file) makes the model switch to the process's
  working directory when it is created: plasmashell's is the home
  folder. So every model keeps the folder it was asked for (`wanted`),
  and rows from a model whose `folder` differs from it are ignored.
- **Scan claims** (`SpanState.claimScan()`): one screen scans per config
  and tick. A claim that hasn't finished within 30 s is taken over,
  because Plasma destroys and rebuilds wallpaper items when displays
  change, and the claiming item can vanish mid-scan. Taking over needs a
  later call, and calls come with ticks; while the lists are empty the
  slideshow Timer is stopped, so `SpanState._emptyRetry` ticks every 30 s
  instead (this also notices a drive with the folders mounted after
  login). A screen still scanning for the same settings doesn't restart
  its scan on a tick, so a slow folder can finish.
- **`property var` arrays** don't reliably notify on in-place mutation
  (`.push()`, `.shift()`, index assignment). Always assign a new array
  (`.slice()` and modify the copy).
- **`Qt.callLater`** merges repeated calls with the same function, so code
  that every screen must run passes a fresh closure
  (`function () { root.x(); }`).
- **A layer's `geom` is not a binding** (`ImageLayer.qml`). It is
  computed on image load, on probe results, at every tick, right away
  when `SpanFit`, `MatchPhysicalSize` or `MonitorSizes` change, and
  (debounced 1.5 s) when `screenLayout` changes. A new input to
  `computeGeomFor()` needs a matching refresh.
- **Layer handover**: only `pending` (the layer a new picture loads into)
  can become `front`, and only once it is Ready and, for a spanned
  picture, measured. A geometry change makes both layers decode again; if
  any Ready could take over, the faded-out layer's old picture came back.
  A layer that has faded out lets go of its picture.
- **Full-width layers use `Image.Stretch`**, not `PreserveAspectCrop`: the
  latter re-crops around the layer's own center, which drifts the seam off
  the bezel on every screen but the largest.
- **Probes** decode at `sourceSize: Qt.size(1024, 0)`, and the natural
  size is read from `implicitWidth`/`implicitHeight` (`sourceSize` reads
  back the requested size). Only the aspect ratio is used.
- **Screen identity** comes from the connector name (`Screen.name`), not
  the position, which changes during every display reconfiguration.
- **The desk math lives in `desk.js`** (`.pragma library`), shared by
  `main.qml` and `config.qml`: the settings page lays out the same desk to
  gray out the spanned-image settings that make no difference. Change the
  placement there, not in a copy, and then the port of it in
  `docs/cropping.html`, which runs the same math in the browser.
- **Monitor size corrections** (`MonitorSizes`) are keyed by
  `manufacturer + " " + model` (on KWin Wayland, e.g. `AOC 2369` or
  `Dell Inc. DELL G2724D`; `serialNumber` is empty), so they follow the
  monitor to another connector. A monitor that reports neither is keyed by
  its connector name (`monitorKey()` in `desk.js`). Qt reports an unknown size as 100 DPI,
  not as 0, so a monitor without an EDID size looks plausible, not missing.
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
