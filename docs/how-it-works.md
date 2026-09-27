# How it works

Multi-monitor Slideshow is a Plasma wallpaper plugin: a folder of QML files that
Plasma loads, with no compiled code. This page explains how the pieces fit
together. [cropping.md](cropping.md) covers the placement math in detail.

## The files

| File | Role |
|---|---|
| `metadata.json` | The plugin's name, ID and version. |
| `contents/config/main.xml` | The settings and their defaults. |
| `contents/ui/main.qml` | The wallpaper on one screen: scanning folders, placing and showing images, the right-click menu. |
| `contents/ui/SpanState.qml` | State shared by every screen: the image lists, the timer and the current turn. |
| `contents/ui/qmldir` | Registers `SpanState` as a singleton, which is what makes it one object for every screen. |
| `contents/ui/ImageLayer.qml` | One of the two crossfading image layers on a screen. |
| `contents/ui/desk.js` | The desk that spanned images are laid out on (see below), used by `main.qml` and `config.qml`. |
| `contents/ui/config.qml` | The settings page. |
| `contents/ui/FolderListSection.qml` | One folder list on the settings page. |
| `contents/ui/FolderImages.qml` | The thumbnail grid on the settings page. |
| `utils/kwin-layout-keeper.py` | A separate helper for KWin's saved monitor layouts (see the README). |
| `utils/deploy.sh` | Installs the plugin from a clone into Plasma's wallpaper folder and restarts the shell. |
| `utils/span-test-5120x1440.png`, `utils/make-span-test.sh` | A test image for checking spanned images on two 16:9 monitors, and the script that makes it. |
| `utils/package.sh`, `utils/make-preview.py` | Build the release archive and the preview image. |

## One wallpaper per screen, one shared state

Plasma creates a separate wallpaper for every screen, and gives each one
its own settings. All of them run in the same QML engine, though, so a QML
singleton is one object that every screen sees. `SpanState` is that
singleton. It holds:

- the list of spanned images and the list of individual images;
- a timer, and `tickCount`, which goes up by one at every image change;
- whose turn it is: a spanned image (and which one), or individual images.

When the timer fires, or someone clicks **Next**, `SpanState`
advances `tickCount` and picks the next turn. Every screen reacts at once
through ordinary property bindings. There is no clock math and no
messaging between screens, so they can't drift apart.

## The slideshow order

Spanned and individual images take turns in one sequence.

**Random:** both lists together form one lap, shuffled with a seeded random
generator. The seed changes at every Plasma start, and each lap is
reshuffled. When the lap lands on an individual image, every screen shows an
individual image, but each screen picks it from its own shuffle of the
individual list, seeded from the screen's connector name (`DP-1`, `HDMI-A-1`, ...).
So the screens show different images, and each screen keeps its own
sequence when monitors are added, removed or moved.

**Sorted** (A to Z, Z to A, newest first, oldest first): both lists are
sorted and merged into one lap of turns. A spanned image is one turn. An
individual turn takes the next images in line, one per screen, left to
right, so no screen repeats what its neighbour just showed.

## Finding the images

The folders are scanned when Plasma starts and again at every image
change, so added and deleted images are picked up at the next change.
Only one screen scans; the others read the result from `SpanState`. Each
folder gets its own `FolderListModel` (Qt's folder listing), created for
that one folder; they are all removed once every folder has reported.
Folders are read one level deep, and unticked folders are skipped.

## Showing an image

Each screen has two image layers. A new image loads into the hidden
layer, and only when it has finished loading (and, for a spanned image,
its shape has been measured) does that layer fade in over the other one.
So a slow image never fades in a blank frame, a spanned image never
jumps into place after it appears, and changing images never flashes
black. The layer that faded out then lets go of its image.

Individual images simply fill their screen: scaled to cover it, with the
overflow cut evenly from both sides.

A spanned image has to line up across screens, so every screen works out
the same layout and then draws only its own part:

1. **The desk.** The screens are laid out as they physically sit next to
   each other, measured in pixels of the largest screen. A screen with
   bigger pixels takes more room on the desk than its pixel count suggests.
   The pixel sizes come from the sizes the monitors report, or from the
   user's corrections in **Monitor Sizes…** (kept per make and model, or
   per connector for a monitor that reports neither, in `MonitorSizes`).
   Vertical alignment follows Display Configuration: a screen aligned to
   the top of the largest one stays aligned to its top.
2. **The image's box.** The image gets a box on the desk. The plugin
   first checks the image's shape (read from a small, fast decode of the
   image). If cutting it into one slice per screen gives screen-shaped
   slices, each slice becomes one unit the size of the largest screen, laid
   side by side so the largest screen's slice sits exactly on it.
   Otherwise the image is a panorama, scaled to cover a box: the
   rectangle around all screens, or with **Always center on the bezel
   between the monitors**, a box centered on the middle join and on the
   middle of the largest screen, just large enough to reach every screen.
3. **Back to the screen.** Each screen converts the box from desk units to
   its own pixels and draws the image layer there. The parts outside the
   screen are clipped.

Each screen recomputes its layout shortly after any monitor is added,
removed, moved or resized.

## One set of settings

Plasma stores wallpaper settings per screen, and the settings dialog only
edits the screen it was opened on. To keep one set of settings, the
settings page stamps every edit with the time. Each screen offers its
settings to `SpanState` at startup and at every image change;
`SpanState` keeps the newest, and screens with older settings copy them
into their own.

A running wallpaper doesn't always get notified when the dialog saves, so
settings are read again at every image change. **Next** applies
them right away.

## The settings page

The page lists the individual and spanning folders on the left, and a
thumbnail grid of the selected folder on the right, in the chosen order.
For Random the grid is shuffled whenever the folder or its contents
change; it's not the slideshow's own sequence. Thumbnails come from
the plugin's own cache, or from the thumbnails your file manager already
made (the freedesktop cache in `~/.cache/thumbnails`). An image with
neither is decoded once at thumbnail size and saved as a small JPEG in
`~/.cache/com.github.vasilkalchev.multimonitorslideshow/thumbnails`. Thumbnails load two at
a time, visible ones first, top to bottom. Each time the page opens,
thumbnails that haven't been read for 60 days are deleted.

The page also lays out the desk (with `desk.js`, like the wallpaper) to
find the spanned-image settings that make no difference for the
connected monitors: **Same physical size on every monitor** when all
monitors have the same pixel size, **Always center on the bezel between
the monitors** when the middle join is already the middle of the monitors.
Those are grayed out, with the reason below them. **Monitor Sizes…** shows
each monitor's reported size and saves a correction as
`<make> <model>=<inches>` in `MonitorSizes` (`<connector>=<inches>` for a
monitor that doesn't report its make and model).

## The right-click menu

The wallpaper adds its entries to the desktop's right-click menu: Open
Image, Next, Next Individual and Next Spanned, plus an optional
grayed-out "Wallpaper" label. A real submenu isn't available to QML
wallpaper plugins, so the label stands in as a heading. Each entry can be
hidden in the settings.
