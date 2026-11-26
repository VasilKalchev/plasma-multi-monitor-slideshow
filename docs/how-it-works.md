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
| `contents/ui/state.js` | The saved place in the slideshow (`state.json`): writing, reading and checking it, and the time left. Used by `SpanState.qml`. |
| `contents/ui/images.js` | Which files count as images and how the sorted orders compare them, used by the slideshow and by the settings page's thumbnail grid. |
| `contents/ui/config.qml` | The settings page. |
| `contents/ui/FolderListSection.qml` | One folder list on the settings page. |
| `contents/ui/FolderImages.qml` | The thumbnail grid on the settings page. |
| `utils/kwin-layout-keeper.py` | A separate helper for KWin's saved monitor layouts (see the README). |
| `utils/deploy.sh` | Installs the plugin from a clone into Plasma's wallpaper folder and restarts the shell. |
| `utils/span-test-5120x1440.png`, `utils/make-span-test.sh` | A test image for checking spanned images on two 16:9 monitors, and the script that makes it. |
| `utils/package.sh`, `utils/make-preview.py` | Build the release archive and the preview image. |
| `utils/make-logo.py` | Draws the KDE Store logo. |
| `utils/test-state.py` | Tests for `state.js` and the Random lap order, run in Qt's JavaScript engine. |

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
Each screen keeps its own sequence when monitors are added, removed or
moved, and goes one image further on every individual turn, through the
whole list before it is reshuffled. Two shuffles land on the same image
now and then; the screen whose connector name sorts later then takes
another image from its own shuffle, so the screens show different images
(while there are enough of them).

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

Individual images fill their screen the way the **Individual images**
setting says. By default they are scaled to cover it, with the overflow
cut evenly from both sides. A mode that can leave part of the screen free
(**Scaled, Keep Proportions** and **Centered**) gets a backdrop inside the
same layer, under the image: the background color, and for **Blur** a
quarter-size copy of the image, scaled to cover the screen and blurred.
The layer fades in once the backdrop is decoded too.

A spanned image has to line up across screens, so every screen works out
the same layout and then draws only its own part:

1. **The desk.** The screens are laid out as they physically sit next to
   each other, measured in pixels of the largest screen. Mirrored screens
   (at the same position) are one place on the desk. A screen with
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

## Resuming and the lock screen

What every screen shows follows from a few numbers in `SpanState`: the
seed of the shuffle, `tickCount`, and the image lists (and, for
individual images, each screen's connector name). So saving those is
enough to bring the same images back. That's what **Resume where it
left off** does.

**Saving.** plasmashell saves its place to
`~/.local/state/com.github.vasilkalchev.multimonitorslideshow/state.json`:

```json
{"v":1, "written":1795723873928, "order":0, "interval":1800,
 "seed":427408983, "tick":2, "shown":1770, "check":"7bb0d802",
 "span":true, "images":{"HDMI-A-1":"file:///…", "HDMI-A-2":"file:///…"}}
```

`check` is a hash of the order and both image lists, `shown` the seconds
the current image has been on screen, and `images` what each monitor
shows (only for reading and for a check after a restore). The file is
written at every image change and once a minute, through the
plasma5support "executable" engine, to a temporary file that is then
renamed. Saves are merged, so Next Spanned stepping through many turns
writes once.

**Screen time.** `shown` grows by one minute at each beat of a Timer.
Qt timers stop while the machine is suspended, like the slideshow timer
itself, so suspend doesn't count, and neither does time switched off. A
shutdown loses the time since the last beat, so an image can stay up to a
minute longer than its interval, never shorter. Time locked, or with the
monitors off for power saving, counts, as it does for the slideshow
timer.

**Restoring.** At startup the file is read before the first image is
picked (at most 3 s). If the setting is on and the order and the lists
still match, the seed and the tick are taken over and the images come
back. The image then stays up for the rest of its interval, or the
slideshow goes on to the next image at once if its time is up. Anything
else (no file, a damaged one, other images) starts a new slideshow, and
the journal says why.

**The lock screen** is another program, `kscreenlocker_greet`, with its
own settings (in `kscreenlockerrc`) and its own `SpanState`. The plugin
tells the two apart by `Qt.application.name`: `plasmashell` writes the
file, `kscreenlocker_greet` only reads it, and anything else does
neither. With **Show the desktop's slideshow** on (`FollowDesktop`, a
setting only the lock screen's page shows), the lock screen runs with
the desktop's settings, which the desktop saves in the file too: it
scans the desktop's folders, so its lists match, and draws the images
the same way. Its own folders and settings are only used with the
setting off, or when there is no saved state to follow (the desktop
doesn't use the plugin). It takes the desktop's seed and tick and adds the
time since the file was written (the desktop has been running all
along), but at most one minute: the desktop writes at least once a
minute while awake, so any more than that was spent asleep, and sleep
doesn't count here either. It reads the file again every 10 s and
changes images when the desktop does. Its own slideshow timer stays
stopped meanwhile. Locking, sleeping and waking up again keeps the same
image, for the rest of its time.

The Random order's swap at the start of a lap (so a lap doesn't begin
with the image the last one ended on) is worked out from the previous
lap's shuffle, not from what the process remembers, so a restored desktop
and the lock screen get the same sequence as a desktop that has been
running all along.

## The settings page

The same page sets up the desktop and the lock screen. It tells them
apart by what Plasma hands it: in Screen Locking's settings,
`configDialog` is the lock screen's settings module, the only one with a
`wallpaperConfigFile`. There it shows **Show the desktop's slideshow**
and, while that is on, a line about the desktop's slideshow (read from
`state.json`) instead of the slideshow's own settings. **Resume where it
left off** and **Context Menu…** are only shown on the desktop.


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
