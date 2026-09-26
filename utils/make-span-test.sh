#!/usr/bin/env bash
# Generates span-test-5120x1440.png: a two-half (2x 16:9) test wallpaper for
# checking that spanned images split on the bezel and keep the same physical
# size on monitors with different pixel sizes.
set -euo pipefail
cd "$(dirname "$0")"

W=5120 H=1440 C=2560
colors=('#ff4d4d' '#ffb000' '#33d17a' '#3fa9f5' '#c061cb')
args=()

# Vertical grid every 200 px, measured from the seam.
for d in $(seq 200 200 2400); do
    args+=(-stroke '#3a4250' -strokewidth 2
           -draw "line $((C - d)),0 $((C - d)),$H"
           -draw "line $((C + d)),0 $((C + d)),$H")
done

# Horizontal colored lines across the full width: they must stay straight
# across the bezel.
i=0
for y in 240 480 720 960 1200; do
    args+=(-stroke "${colors[$i]}" -strokewidth 8 -draw "line 0,$y $W,$y")
    i=$((i + 1))
done

# Identical 400 px squares and circles mirrored around the seam: they must
# look the same size on both monitors.
for s in -1 1; do
    sx=$((C + s * 600)) cx=$((C + s * 1300))
    args+=(-stroke white -strokewidth 6 -fill none
           -draw "rectangle $((sx - 200)),520 $((sx + 200)),920"
           -draw "circle $cx,720 $((cx + 200)),720"
           -stroke none -fill white -pointsize 56
           -draw "text $((sx - 110)),500 '400 px'"
           -draw "text $((cx - 110)),500 '400 px'")
done

magick -size "${W}x${H}" xc:'#14181f' "${args[@]}" \
    -stroke white -strokewidth 4 -draw "line $C,0 $C,$H" \
    -stroke none -fill white -pointsize 64 \
    -draw "text 1500,120 'LEFT HALF'" -draw "text 3150,120 'RIGHT HALF'" \
    span-test-5120x1440.png
