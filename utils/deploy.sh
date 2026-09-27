#!/bin/sh
# Installs the plugin from this working tree (committed or not) where
# Plasma loads it, ~/.local/share/plasma/wallpapers/<id>/, replacing what
# is there, then restarts plasmashell so the new QML is used. It copies
# the same files as the release archive (see .gitattributes).
#
#     utils/deploy.sh               copy and restart plasmashell
#     utils/deploy.sh --no-restart  copy only; enough for the settings page
#                                   in kcmshell6 kcm_wallpaper, which loads
#                                   config.qml fresh every time
set -eu
cd "$(dirname "$0")/.."

restart=1
case "${1-}" in
    "") ;;
    --no-restart) restart=0 ;;
    *) echo "usage: $0 [--no-restart]" >&2; exit 2 ;;
esac

id=$(sed -n 's/^ *"Id": "\(.*\)",\{0,1\}$/\1/p' metadata.json)
case "$id" in
    "" | */* | .*) echo "no usable Id in metadata.json" >&2; exit 1 ;;
esac
dest=${XDG_DATA_HOME:-$HOME/.local/share}/plasma/wallpapers/$id

# A git checkout there is a working copy (cloned straight into Plasma's
# folder), not a deployed copy: don't delete it.
if [ -e "$dest/.git" ]; then
    echo "$dest is a git checkout; move it somewhere else first" >&2
    exit 1
fi

rm -rf "$dest"
mkdir -p "$dest"
cp -R metadata.json LICENSE README.md contents "$dest/"
echo "installed to $dest"

if [ "$restart" = 1 ]; then
    if systemctl --user is-active --quiet plasma-plasmashell.service; then
        systemctl --user restart plasma-plasmashell.service
        echo "restarted plasmashell"
    else
        echo "plasmashell isn't running as a systemd service; restart Plasma to load the new version"
    fi
fi
