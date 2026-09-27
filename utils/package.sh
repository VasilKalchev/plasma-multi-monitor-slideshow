#!/bin/sh
# Builds multi-monitor-slideshow-<version>.tar.gz from the committed HEAD, for the
# KDE Store and GitHub releases. The archive holds the plugin package
# itself (metadata.json at its root); .gitattributes leaves out the docs
# and utils. Install it with:
#
#     kpackagetool6 -t Plasma/Wallpaper -i multi-monitor-slideshow-<version>.tar.gz
set -eu
cd "$(dirname "$0")/.."

version=$(sed -n 's/^ *"Version": "\(.*\)",\{0,1\}$/\1/p' metadata.json)
[ -n "$version" ] || { echo "no Version in metadata.json" >&2; exit 1; }
if [ -n "$(git status --porcelain)" ]; then
    echo "warning: uncommitted changes are not included" >&2
fi

out="multi-monitor-slideshow-$version.tar.gz"
git archive --format=tar.gz --output="$out" HEAD
echo "$out"
