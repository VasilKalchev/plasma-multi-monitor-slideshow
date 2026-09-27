# How cropping works

This plugin shows images two ways:

- **Individual** images: each monitor shows its own image, scaled to cover the
  monitor and cropped evenly from both sides (Qt's `PreserveAspectCrop`).
  Nothing is shared between monitors.
- **Spanned** images: one image across all monitors. The rest of this
  document is about these. The code is `layout()` and `joinBox()` in
  `contents/ui/desk.js`, and `computeGeomFor()` in `contents/ui/main.qml`.

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
largest is the one with the largest physical area (with **Same physical
size on every monitor** off, or when a monitor's size is unknown, the one
with the most pixels). Here it's the right monitor. Each monitor gets a factor
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
the monitor reports (its EDID). If a monitor reports a wrong size, enter
the right diagonal under **Monitor Sizes…** in the settings; the plugin
then works out its pixel size from that and its resolution. With **Same
physical size on every monitor** off, every `f` is 1.

With identical monitors every `f` is 1 and the desk is just the pixel
layout.

## Step 2: place the image on the desk

### Pre-split images

The image is cut into as many equal slices as there are monitors. If a
slice has the monitor's shape (within 3%), the image is pre-split: each
slice is one unit the size of the largest monitor on the desk, placed so
the largest monitor's own slice sits exactly on it. Every other monitor is
physically smaller, so it fits inside its slice and shows the part of it
that it covers. These layers use `Image.Stretch`, not `PreserveAspectCrop`
(see the comment in `computeGeomFor()` for why).

A two-part 32:9 image (for example 5120x1440 or 3840x1080) is pre-split on
the example monitors. Each slice is 2560 x 1440 desk pixels, and the right
monitor's slice sits on it, so the image covers desk x −640 to 4480 and
its middle seam lands on the bezel:

- The right monitor shows the right half, complete.
- The left monitor shows the left half at the same physical size. It
  covers desk x −266 to 1920, so it loses the left 374 px of that half
  (15%), and 120 px at the top and 90 px at the bottom.

Each monitor runs the pre-split test against its own shape. If the
monitors have different shapes (say a 16:9 and a 16:10), a picture can be
pre-split for one and a panorama for the other, and the halves won't line
up at the join.

A pre-split image is only recognized at the monitor count it was made for.
A two-part image on three monitors is cut into three slices that don't
match any monitor, so it becomes a panorama.

### Panoramas

Any other image is a panorama: it's scaled, keeping its shape, until it
covers a box on the desk, and the overhang is cut evenly. Which box
depends on **Center on the bezel between the monitors**.

**Off (the default):** the box around all monitors, desk x −266 to 4480
and y 0 to 1440, so 4746 x 1440, with the image centered on it. This cuts
off the least. A 21:9 image (3440x1440) becomes 4746 wide and 1987 tall,
so it loses about 14% at the top and 14% at the bottom.

**On:** the image's center goes on the join between the monitors
horizontally (desk x = 1920), and on the middle of the largest monitor
vertically (desk y = 720). With an odd number of monitors, the horizontal
center is the middle of the middle monitor. The box is the smallest one
around that point that covers every monitor: the right monitor reaches
2560 to the right, and its top and bottom are 720 away, so the box is
5120 x 1440, from desk x −640 to 4480.

- The 21:9 image becomes 5120 wide and 2143 tall, so it loses about 16% at
  the top and 16% at the bottom.
- A two-part image made for other monitors, like two 16:10 halves
  (3840x1200), isn't pre-split on 16:9 monitors, but its seam still lands
  on the bezel. It becomes 5120 x 1600, losing 5% at the top and 5% at the
  bottom. With the setting off, its seam would land 187 desk pixels into
  the right monitor.
- A two-part image on three monitors has its seam in the middle of the
  middle monitor.

When the join is already the middle of the monitors (identical monitors,
lined up), both boxes are the same, and the settings page grays the
setting out.

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
