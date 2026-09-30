#!/usr/bin/env python3
"""Draws the KDE Store logo: the preview's four tilted monitors and the
plugin's name on a transparent background, with the name larger.

Reuses the drawings of make-preview.py, but renders with cairosvg and Pillow
(pip install cairosvg pillow numpy) instead of Inkscape and ImageMagick.
Usage: make-logo.py [output.png] (default: docs/images/logo-store.png).
The name is set in Bricolage Grotesque; if it isn't at $BRICOLAGE_TTF it is
downloaded from Google Fonts for the run.
"""
import importlib.util
import io
import os
import sys
import tempfile
import urllib.request

import cairosvg
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("mp", os.path.join(HERE, "make-preview.py"))
mp = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mp)

OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "..", "docs", "images", "logo-store.png")
SIZE, SS = mp.SIZE, mp.SS
ROWS = (60, 684)          # the pairs sit further apart than in the preview...
TITLE_LINES = ("Multi-monitor", "Slideshow")
TITLE_PX = 118            # ...to make room for a two-line, larger name
TITLE_COLOR = "#1a2233"

# cairosvg has no blur filter: the two nebula clouds become radial gradients.
SPACE = (mp.SPACE
         .replace('<filter id="haze"><feGaussianBlur stdDeviation="18"/></filter>',
                  '<radialGradient id="pink"><stop offset="0" stop-color="#d0508f" stop-opacity="0.4"/><stop offset="1" stop-color="#d0508f" stop-opacity="0"/></radialGradient>'
                  '<radialGradient id="blue"><stop offset="0" stop-color="#4f8fe0" stop-opacity="0.35"/><stop offset="1" stop-color="#4f8fe0" stop-opacity="0"/></radialGradient>')
         .replace('<ellipse cx="330" cy="90" rx="120" ry="50" fill="#d0508f" opacity="0.28" filter="url(#haze)"/>',
                  '<ellipse cx="330" cy="90" rx="150" ry="70" fill="url(#pink)"/>')
         .replace('<ellipse cx="380" cy="170" rx="90" ry="40" fill="#4f8fe0" opacity="0.25" filter="url(#haze)"/>',
                  '<ellipse cx="380" cy="170" rx="120" ry="60" fill="url(#blue)"/>'))


def png(svg, w, h):
    return Image.open(io.BytesIO(cairosvg.svg2png(bytestring=svg.encode(), output_width=w, output_height=h))).convert("RGBA")


def coeffs(dst, src):
    """Perspective coefficients for Image.transform: output point -> source point."""
    a = []
    for (x, y), (u, v) in zip(dst, src):
        a += [[x, y, 1, 0, 0, 0, -u * x, -u * y], [0, 0, 0, x, y, 1, -v * x, -v * y]]
    b = [c for p in src for c in p]
    return np.linalg.solve(np.array(a, float), np.array(b, float))


def font():
    path = os.environ.get("BRICOLAGE_TTF")
    if not path:
        path = os.path.join(tempfile.gettempdir(), "BricolageGrotesque.ttf")
        if not os.path.exists(path):
            urllib.request.urlretrieve(mp.FONT_URL, path)
    f = ImageFont.truetype(path, TITLE_PX * SS)
    try:
        f.set_variation_by_axes([min(TITLE_PX, 96), 700, 100])   # opsz, wght, wdth
    except Exception:
        pass
    return f


def main():
    big = SIZE * SS
    canvas = Image.new("RGBA", (big, big), (0, 0, 0, 0))

    # stands
    d = ImageDraw.Draw(canvas)
    for y0 in ROWS:
        for left in (True, False):
            c = mp.corners(left, y0)
            x, y = [s * SS for s in ((c[2][0] + c[3][0]) / 2, (c[2][1] + c[3][1]) / 2)]
            d.rectangle([x - 12 * SS, y - 2 * SS, x + 12 * SS, y + 20 * SS], fill="#c3cbd8")
            d.ellipse([x - 64 * SS, y + 16 * SS, x + 64 * SS, y + 28 * SS], fill="#bcc5d3")

    screens = [(ROWS[0], True, mp.PANORAMA, 0),
               (ROWS[0], False, mp.PANORAMA, mp.SW + 2 * mp.SIDE + mp.GAP),
               (ROWS[1], True, SPACE, 0),
               (ROWS[1], False, mp.BEACH, 0)]
    for y0, left, content, dx in screens:
        flat = png(mp.monitor_svg(content, dx), mp.MW * SS, mp.MH * SS)
        dst = mp.corners(left, y0)
        dst = [(x * SS, y * SS) for x, y in dst]
        src = [(0, 0), (mp.MW * SS, 0), (mp.MW * SS, mp.MH * SS), (0, mp.MH * SS)]
        layer = flat.transform((big, big), Image.PERSPECTIVE, coeffs(dst, src), Image.BICUBIC)
        # soft drop shadow from the layer's own alpha
        alpha = layer.getchannel("A")
        shadow = Image.new("RGBA", (big, big), (0x1a, 0x22, 0x33, 0))
        shadow.putalpha(alpha.point(lambda v: int(v * 0.30)))
        shadow = shadow.filter(ImageFilter.GaussianBlur(8 * SS / 2))
        canvas.alpha_composite(shadow, (0, 7 * SS))
        canvas.alpha_composite(layer)

    # the name, two lines, centered between the pairs
    f = font()
    d = ImageDraw.Draw(canvas)
    mid = (ROWS[0] + mp.MH + 40 + ROWS[1]) / 2 * SS
    line = TITLE_PX * 1.08 * SS
    for i, text in enumerate(TITLE_LINES):
        y = mid + (i - (len(TITLE_LINES) - 1) / 2) * line
        d.text((big / 2, y), text, font=f, fill=TITLE_COLOR, anchor="mm")

    canvas.resize((SIZE, SIZE), Image.LANCZOS).save(OUT, optimize=True)
    print(os.path.relpath(OUT))


if __name__ == "__main__":
    main()
