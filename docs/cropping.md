# How cropping works

This plugin shows images two ways:

- **Individual** images: each monitor shows its own image, scaled to cover the
  monitor and cropped evenly from both sides (Qt's `PreserveAspectCrop`).
  Nothing is shared between monitors.
- **Spanned** images: one image across all monitors. The rest of this
  document is about these. The code is `deskLayout()` and
  `computeGeomFor()` in `contents/ui/main.qml`.

The [interactive version](https://vasilkalchev.github.io/plasma-multi-monitor-slideshow/cropping.html)
(`docs/cropping.html`) runs the same math on a monitor layout and pictures of
your choice.

The worked example uses two monitors of different sizes, side by side:

```
        resolution   position in Display Configuration   panel size   pixel size
left    1920x1080    (0, 206)                             509x286 mm   0.265 mm   (23")
right   2560x1440    (1920, 0)                            596x335 mm   0.233 mm   (27")
```

## Step 1: the desk

Display Configuration places monitors in pixels, but the left monitor's
pixels are about 14% bigger than the right one's. If the image were laid
out pixel for pixel, everything would look 14% bigger on the left monitor,
even though a screenshot would look perfect.

So every spanned image is placed on a "desk" instead: the monitors' real
physical arrangement, measured in pixels of the largest monitor. The
largest is the one with the largest physical area (with **Compensate for
pixel size** off, or when a monitor doesn't report its size, the one with
the most pixels). Here it's the right monitor. Each monitor gets a factor
`f`: how many of the largest monitor's pixels one of its own pixels
covers.

```
f(left)  = 0.265 / 0.233 = 1.1385     -> the left monitor is 1920 x 1.1385 = 2186 by 1080 x 1.1385 = 1230 desk pixels
f(right) = 1                          -> 2560 x 1440 desk pixels
```

Where each monitor goes on the desk follows Display Configuration:

- **Horizontally**, monitors stay touching. The left monitor's right edge
  meets the right monitor's left edge at desk x = 1920, so the left
  monitor spans desk x −266 to 1920.
- **Vertically**, each monitor keeps its alignment against the largest
  one, as a fraction of the height difference. In pixels, the left monitor
  can move 1440 − 1080 = 360 px up or down against the right one. At
  y = 206 it sits at 206 / 360 = 57% of that range (50% would be exactly
  centered). On the desk the range is 1440 − 1230 = 210, so the left
  monitor's top goes 57% × 210 = 120 desk pixels below the right one's
  top. Top-aligned stays top-aligned, centered stays centered,
  bottom-aligned stays bottom-aligned.

The pixel sizes come from Qt's `pixelDensity`, which comes from the size
the monitor reports (its EDID). If a monitor reports a wrong size, turn off
**Compensate for pixel size** in the settings, which sets every `f` to 1.

With identical monitors every `f` is 1 and the desk is just the pixel
layout.

## Step 2: place the image on the desk

The **Spanned images** setting picks one of two behaviours.

### Center on the monitor join

1. The image's center goes on the join between the monitors horizontally
   (desk x = 1920), and on the middle of the largest monitor vertically
   (desk y = 720). With an odd number of monitors, the horizontal center is
   the middle of the middle monitor.
2. The image is scaled, keeping its shape, until it covers every monitor
   around that point. The monitor farthest from the center sets the size:
   the right monitor reaches 2560 to the right, and its top and bottom are
   720 away. So the image must cover a 5120 x 1440 box from desk x −640 to
   4480.

A two-part 32:9 image (for example 5120x1440 or 3840x1080) fits that box
exactly, so its middle seam lands on the bezel:

- The right monitor shows the right half, complete.
- The left monitor shows the left half at the same physical size. It
  covers desk x −266 to 1920, so it loses the left 374 px of that half
  (15%), and 120 px at the top and 90 px at the bottom.

Any other shape is scaled until it covers the box, and the excess is cut
evenly. For example, a 21:9 image (3440x1440) becomes 5120 wide and 2143
tall, so about 16% of its height is cut at the top and 16% at the bottom.

### Detect pre-split images (default)

The image is cut into as many equal slices as there are monitors. If a
slice has the monitor's shape (within 3%), the image is treated as
pre-split: each slice is one unit the size of the largest monitor on the
desk, placed so the largest monitor's own slice sits exactly on it. Every
other monitor is physically smaller, so it fits inside its slice and shows
the part of it that it covers. For two monitors that gives the same result
as "Center on the monitor join" above. These layers use `Image.Stretch`,
not `PreserveAspectCrop` (see the comment in `computeGeomFor()` for why).

Otherwise the image is treated as a panorama: scaled to cover the box
around all monitors on the desk (desk x −266 to 4480, y 0 to 1440, so
4746 x 1440), centered on it, with the overhang cut evenly. The 21:9
example loses about 14% at the top and 14% at the bottom here.

Each monitor runs the pre-split test against its own shape. If the
monitors have different shapes (say a 16:9 and a 16:10), a picture can be
pre-split for one and a panorama for the other, and the halves won't line
up at the join.

A pre-split image is only recognized at the monitor count it was made for.
A two-part image on three monitors is cut into three slices that don't
match any monitor, so it becomes a panorama with its seam in the middle of
the middle monitor. "Center on the monitor join" puts the center on the
middle monitor's center with an odd count, so the same happens there.

With a single monitor, a spanned image is placed like an individual one.

## Step 3: back to each monitor's pixels

Each monitor divides the desk box by its own `f` and shifts it by its
own desk position. For the two-part example:

```
right:  image layer 5120 x 1440 at (−2560, 0)            in its pixels
left:   image layer 4497 x 1265 at (−329, −106)          in its pixels
```

A 400 px square in the image therefore measures 400 px on the right
monitor and 400 / 1.1385 = 351 px on the left one: both 93 mm. A test
picture with straight lines and squares on both sides of the seam makes
this easy to check with a ruler.

Every monitor recomputes its placement shortly (1.5 s) after any monitor
is added, removed, moved, or resized, so a burst of changes settles into
one recompute against the final layout.
