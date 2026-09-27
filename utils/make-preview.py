#!/usr/bin/env python3
"""Draws docs/images/preview.png, the KDE Store thumbnail and README picture:
two pairs of monitors with the plugin's name between them, the top pair
showing one picture spanned across both, the bottom pair a different
picture on each.

Each monitor is drawn flat as SVG, rendered with Inkscape, tilted with an
ImageMagick perspective distortion (SVG has no perspective), and composited
over the background. Needs inkscape and magick (ImageMagick 7). The name is
set in Bricolage Grotesque, the website's heading font; if it isn't
installed, it's downloaded from Google Fonts for the run.
"""
import os
import subprocess
import tempfile
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "docs", "images", "preview.png")

SIZE = 1024       # output size
SS = 3            # supersampling factor
NAME = "Multi-Monitor Slideshow"
FONT = "Bricolage Grotesque"
FONT_URL = ("https://github.com/google/fonts/raw/main/ofl/bricolagegrotesque/"
            "BricolageGrotesque%5Bopsz,wdth,wght%5D.ttf")

# A flat monitor: a 16:9 screen with thin top and side bezels and a thicker
# bottom one.
SIDE, TOP, CHIN = 5, 5, 16
SW, SH = 460, 259
MW, MH = SW + 2 * SIDE, SH + TOP + CHIN

# Tilt: each monitor turns toward the viewer, so its inner edge (at the
# join) looks shorter and the monitor narrower.
INNER = 0.9       # inner edge height, relative to the outer edge
NARROW = 0.95     # width after turning
GAP = 3           # between the two monitors of a pair
ROWS = (100, 616) # top of each pair
TITLE_Y = 537     # title baseline, so the name sits in the middle

# ---------------------------------------------------------------- pictures
# Screen content, in screen coordinates (SW x SH).

# The spanned picture: a sunset over mountains and a lake, drawn across
# both screens of a pair plus the bezels between them (the part behind the
# bezels is hidden, as on real monitors).
PANORAMA_W = 2 * SW + 2 * SIDE + GAP
PANORAMA = """
<defs>
  <linearGradient id="duskSky" x1="0" y1="140" x2="0" y2="312" gradientUnits="userSpaceOnUse">
    <stop offset="0" stop-color="#15204c"/><stop offset="0.5" stop-color="#5a3a8c"/>
    <stop offset="0.85" stop-color="#e0735a"/><stop offset="1" stop-color="#ffb068"/>
  </linearGradient>
  <radialGradient id="sunGlow" cx="512" cy="266" r="180" gradientUnits="userSpaceOnUse">
    <stop offset="0" stop-color="#ffc978" stop-opacity="0.75"/><stop offset="1" stop-color="#ffc978" stop-opacity="0"/>
  </radialGradient>
  <linearGradient id="lake" x1="0" y1="318" x2="0" y2="393" gradientUnits="userSpaceOnUse">
    <stop offset="0" stop-color="#6b3f78"/><stop offset="1" stop-color="#1a1433"/>
  </linearGradient>
</defs>
<g transform="scale(%(sx)f %(sy)f) translate(-46 -140)">
  <rect x="0" y="100" width="1024" height="330" fill="url(#duskSky)"/>
  <circle cx="512" cy="266" r="180" fill="url(#sunGlow)"/>
  <circle cx="512" cy="268" r="56" fill="#ffd98a"/>
  <polygon fill="#7a4d8c" opacity="0.85" points="0,300 46,300 96,268 150,284 222,240 298,274 376,234 446,286 512,304 578,284 652,238 738,258 822,228 902,256 978,240 1024,250 1024,330 0,330"/>
  <polygon fill="#3e2a5e" points="0,326 46,326 118,284 196,312 288,270 378,318 460,306 512,318 566,304 640,286 730,320 818,280 900,306 978,288 1024,296 1024,340 0,340"/>
  <rect x="0" y="318" width="1024" height="90" fill="url(#lake)"/>
  <g fill="#ffd98a">
    <rect x="470" y="328" width="84" height="3" rx="1.5" opacity="0.85"/>
    <rect x="480" y="340" width="64" height="3" rx="1.5" opacity="0.65"/>
    <rect x="490" y="352" width="44" height="3" rx="1.5" opacity="0.45"/>
    <rect x="499" y="364" width="26" height="3" rx="1.5" opacity="0.3"/>
  </g>
  <polygon fill="#120d24" points="0,400 0,346 46,346 132,340 226,366 300,400"/>
  <polygon fill="#120d24" points="1024,400 1024,344 978,344 884,338 796,368 736,400"/>
</g>
""" % {"sx": PANORAMA_W / 932.0, "sy": SH / 253.0}

# Individual picture 1: a ringed planet in space.
SPACE = """
<defs>
  <radialGradient id="space" cx="0.65" cy="0.3" r="0.9">
    <stop offset="0" stop-color="#2f2466"/><stop offset="1" stop-color="#07081a"/>
  </radialGradient>
  <radialGradient id="planet" cx="0.35" cy="0.3" r="0.8">
    <stop offset="0" stop-color="#ffd9a0"/><stop offset="0.6" stop-color="#e08a4f"/><stop offset="1" stop-color="#7a3326"/>
  </radialGradient>
  <filter id="haze"><feGaussianBlur stdDeviation="18"/></filter>
  <clipPath id="ringFront"><rect x="0" y="152" width="460" height="120"/></clipPath>
  <radialGradient id="moon" cx="0.35" cy="0.35" r="0.75">
    <stop offset="0" stop-color="#f1f4fa"/><stop offset="1" stop-color="#8e98b0"/>
  </radialGradient>
</defs>
<rect width="460" height="259" fill="url(#space)"/>
<ellipse cx="330" cy="90" rx="120" ry="50" fill="#d0508f" opacity="0.28" filter="url(#haze)"/>
<ellipse cx="380" cy="170" rx="90" ry="40" fill="#4f8fe0" opacity="0.25" filter="url(#haze)"/>
<g fill="#fff">
  <circle cx="30" cy="30" r="1.4"/><circle cx="90" cy="18" r="1"/><circle cx="210" cy="36" r="1.6"/>
  <circle cx="260" cy="100" r="1.1"/><circle cx="320" cy="24" r="1.3"/><circle cx="410" cy="48" r="1.7"/>
  <circle cx="440" cy="130" r="1.1"/><circle cx="300" cy="200" r="1.4"/><circle cx="420" cy="230" r="1.2"/>
  <circle cx="250" cy="236" r="1"/><circle cx="20" cy="220" r="1.3"/><circle cx="60" cy="110" r="1"/>
  <circle cx="360" cy="140" r="1"/><circle cx="230" cy="160" r="1.2"/><circle cx="140" cy="20" r="1.1"/>
</g>
<g transform="rotate(-16 150 152)">
  <ellipse cx="150" cy="152" rx="112" ry="26" fill="none" stroke="#f3d3a0" stroke-width="7" opacity="0.8"/>
  <circle cx="150" cy="152" r="64" fill="url(#planet)"/>
  <ellipse cx="150" cy="152" rx="112" ry="26" fill="none" stroke="#f3d3a0" stroke-width="7" clip-path="url(#ringFront)"/>
</g>
<circle cx="372" cy="70" r="15" fill="url(#moon)"/>
"""

# Individual picture 2: a beach with a palm tree and a sailboat.
BEACH = """
<defs>
  <linearGradient id="beachSky" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#5cc2f2"/><stop offset="1" stop-color="#e3f6ff"/>
  </linearGradient>
  <linearGradient id="sea" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#1fc1cf"/><stop offset="1" stop-color="#0b6a92"/>
  </linearGradient>
</defs>
<rect width="460" height="140" fill="url(#beachSky)"/>
<circle cx="378" cy="52" r="22" fill="#fff6c8"/>
<g fill="#fff" opacity="0.9">
  <ellipse cx="120" cy="46" rx="40" ry="11"/><ellipse cx="142" cy="38" rx="22" ry="11"/>
</g>
<rect y="128" width="460" height="131" fill="url(#sea)"/>
<g fill="none" stroke="#e6fbff" stroke-width="2.5" stroke-linecap="round" opacity="0.55">
  <path d="M200,160 q15,-6 30,0 t30,0 t30,0"/>
  <path d="M300,190 q15,-6 30,0 t30,0 t30,0 t30,0"/>
  <path d="M170,215 q15,-6 30,0 t30,0"/>
</g>
<path d="M300,122 l0,-34 l22,32 z" fill="#fff"/>
<path d="M294,124 l34,0 l-5,6 l-24,0 z" fill="#374a5e"/>
<path d="M0,259 L0,170 C80,176 160,208 250,259 Z" fill="#f3d8a4"/>
<path d="M0,176 C80,182 150,210 234,259" fill="none" stroke="#ffffff" stroke-width="3" opacity="0.7"/>
<path d="M78,246 C84,200 96,150 116,108" fill="none" stroke="#6b4a2f" stroke-width="9" stroke-linecap="round"/>
<g fill="#2f8f5a">
  <path d="M116,108 C90,90 60,96 40,118 C66,108 92,106 116,108 Z"/>
  <path d="M116,108 C100,80 76,70 52,74 C78,82 98,94 116,108 Z"/>
  <path d="M116,108 C124,80 144,66 170,66 C150,80 132,94 116,108 Z"/>
  <path d="M116,108 C142,96 170,100 186,122 C162,112 138,110 116,108 Z"/>
  <path d="M116,108 C110,86 116,64 132,50 C128,74 122,92 116,108 Z"/>
</g>
"""


def monitor_svg(content, dx=0):
    """A flat monitor with `content` on its screen, shifted left by dx."""
    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="{MW}" height="{MH}" viewBox="0 0 {MW} {MH}">
  <defs><clipPath id="screen"><rect x="{SIDE}" y="{TOP}" width="{SW}" height="{SH}"/></clipPath>
  <linearGradient id="glare" x1="0" y1="0" x2="1" y2="1">
    <stop offset="0" stop-color="#fff" stop-opacity="0.10"/><stop offset="0.45" stop-color="#fff" stop-opacity="0"/>
  </linearGradient></defs>
  <rect width="{MW}" height="{MH}" rx="7" fill="#0d1017"/>
  <rect x="{MW / 2 - 14}" y="{MH - CHIN / 2 - 1.5}" width="28" height="3" rx="1.5" fill="#262c38"/>
  <g clip-path="url(#screen)"><g transform="translate({SIDE - dx} {TOP})">{content}</g>
  <rect x="{SIDE}" y="{TOP}" width="{SW}" height="{SH}" fill="url(#glare)"/></g>
</svg>"""


def corners(left, y0):
    """Where a tilted monitor's corners land: TL, TR, BR, BL."""
    w = MW * NARROW
    inset = MH * (1 - INNER) / 2
    if left:
        x0 = SIZE / 2 - GAP / 2 - w
        return [(x0, y0), (x0 + w, y0 + inset), (x0 + w, y0 + MH - inset), (x0, y0 + MH)]
    x0 = SIZE / 2 + GAP / 2
    return [(x0, y0 + inset), (x0 + w, y0), (x0 + w, y0 + MH), (x0, y0 + MH - inset)]


def background_svg():
    stands = []
    for y0 in ROWS:
        for left in (True, False):
            c = corners(left, y0)
            x = (c[2][0] + c[3][0]) / 2
            y = (c[2][1] + c[3][1]) / 2
            stands.append(f'<rect x="{x - 12}" y="{y - 2}" width="24" height="22" fill="#c3cbd8"/>'
                          f'<ellipse cx="{x}" cy="{y + 22}" rx="64" ry="6" fill="#bcc5d3"/>')
    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="{SIZE}" height="{SIZE}">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#f7f9fc"/><stop offset="1" stop-color="#dfe6f0"/>
    </linearGradient>
  </defs>
  <rect width="{SIZE}" height="{SIZE}" fill="url(#bg)"/>
  <text x="{SIZE / 2}" y="{TITLE_Y}" text-anchor="middle" font-family="{FONT}" font-weight="700"
        font-size="72" letter-spacing="-1" fill="#1a2233">{NAME}</text>
  {"".join(stands)}
</svg>"""


def run(*args, env=None):
    subprocess.run(args, check=True, capture_output=True, env=env)


def font_env(tmp):
    """An environment in which fontconfig (and so Inkscape) finds FONT."""
    found = subprocess.run(["fc-list", FONT], capture_output=True, text=True).stdout
    if found.strip():
        return None
    urllib.request.urlretrieve(FONT_URL, f"{tmp}/font.ttf")
    with open(f"{tmp}/fonts.conf", "w") as f:
        f.write(f"""<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig><include ignore_missing="yes">/etc/fonts/fonts.conf</include><dir>{tmp}</dir></fontconfig>""")
    return dict(os.environ, FONTCONFIG_FILE=f"{tmp}/fonts.conf")


def render(svg, path, w, h, env=None):
    src = path[:-4] + ".svg"
    with open(src, "w") as f:
        f.write(svg)
    run("inkscape", src, "--export-type=png", f"--export-filename={path}", "-w", str(w), "-h", str(h), env=env)


def main():
    with tempfile.TemporaryDirectory() as tmp:
        big = SIZE * SS
        render(background_svg(), f"{tmp}/bg.png", big, big, font_env(tmp))
        screens = [
            (ROWS[0], True, PANORAMA, 0),
            (ROWS[0], False, PANORAMA, SW + 2 * SIDE + GAP),
            (ROWS[1], True, SPACE, 0),
            (ROWS[1], False, BEACH, 0),
        ]
        layers = []
        for i, (y0, left, content, dx) in enumerate(screens):
            flat = f"{tmp}/m{i}.png"
            render(monitor_svg(content, dx), flat, MW * SS, MH * SS)
            src = [(0, 0), (MW, 0), (MW, MH), (0, MH)]
            pairs = " ".join(f"{sx * SS},{sy * SS} {dx_ * SS},{dy_ * SS}"
                             for (sx, sy), (dx_, dy_) in zip(src, corners(left, y0)))
            layer = f"{tmp}/l{i}.png"
            run("magick", flat, "-alpha", "set", "-virtual-pixel", "transparent",
                "-define", f"distort:viewport={big}x{big}+0+0",
                "-distort", "Perspective", pairs, "+repage", layer)
            layers.append(layer)
        cmd = ["magick", f"{tmp}/bg.png"]
        for layer in layers:
            cmd += ["(", layer, "(", "+clone", "-background", "#1a2233", "-shadow", f"30x{8 * SS}+0+{7 * SS}", ")",
                    "+swap", "-background", "none", "-layers", "merge", ")"]
        cmd += ["-background", "none", "-layers", "flatten", "-resize", f"{SIZE}x{SIZE}",
                "-strip", "-define", "png:compression-level=9", OUT]
        run(*cmd)
    print(os.path.relpath(OUT))


if __name__ == "__main__":
    main()
