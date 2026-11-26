# Changelog

## 1.2.0 (2026-11-26)

### Added

- **Resume where it left off** setting, on by default. After a restart
  the same images come back for the rest of their time, and the slideshow
  goes on with the same sequence. The time counted is real screen time:
  suspend and power-off don't count. The place in the slideshow is saved in
  `~/.local/state/com.github.vasilkalchev.multimonitorslideshow/state.json`.
  Untick the setting for new images at every start, as before.
- The lock screen shows the desktop's slideshow: the same images, changing
  at the same time, and the same image after sleep. It takes the folders
  and settings from the desktop. New setting on the lock screen's page,
  **Show the desktop's slideshow** (on by default); untick it for a
  slideshow of its own. The lock screen's page shows only the settings
  that apply there, and no longer the Context Menu button.

### Changed

- Random order: a new round of the shuffle is worked out the same way
  whatever came before, so a resumed desktop and the lock screen continue
  the same sequence. Running sequences don't change.

## 1.1.0 (2026-11-11)

### Added

- **Individual images** setting: how an individual image fills its
  monitor, like Positioning in the built-in Slideshow. Scaled and Cropped
  (as before, the default), Scaled, Scaled Keep Proportions, Centered or
  Tiled.
- **Background** setting for Scaled Keep Proportions and Centered: a
  blurred copy of the image, or a color, fills the part of the monitor the
  image leaves free.
- The journal now says what the plugin found: the image counts, a folder
  that is missing, an image that can't be loaded and the monitor layout
  (`journalctl --user -u plasma-plasmashell.service`, lines starting with
  "Multi-monitor Slideshow:").

### Changed

- Random order: each monitor goes through all individual images before
  repeating one, two monitors never show the same image at once, and a new
  shuffle doesn't start with the image the last one ended on.
- An image is full-width only when a slice of it has the shape of every
  monitor. Before, some panoramas were cut into slices.
- After Next, Next Individual or Next Spanned, the image stays up for a
  whole interval.
- A folder can be in one list only, individual or spanning.

### Fixed

- A missing folder (an unplugged drive, for example) no longer shows the
  images of the home folder, and the slideshow starts by itself once the
  folder is back.
- Clicking Defaults in the settings no longer brought the old settings
  back at the next image change.
- Next Individual and Next Spanned skipped nothing when the next image of
  that kind was more than one lap away.
- A spanned image whose file was replaced by one of another shape is
  measured again.
- A spanned image could briefly appear at the wrong place, or the previous
  image could flash, when the image changed.
- Monitors that are offset vertically by more than their height
  difference: the spanned image keeps that offset.
- Monitor Sizes showed a monitor that reports no size as 5.0″; it now says
  "unknown".
- Settings that are out of range (edited by hand) fall back to Random and
  15 minutes.
- Mirrored monitors count once in the shape of the spanned thumbnails.
- The settings page no longer logs a "Cannot open" warning for every image
  without a thumbnail, and reuses thumbnails it has just made.
- The thumbnail cache is also cleaned up on file systems that don't keep
  access times.
- Less memory and work when the image changes: a spanned image is decoded
  once, and the outgoing image isn't decoded again.

## 1.0.0 (2026-09-27)

First release.
