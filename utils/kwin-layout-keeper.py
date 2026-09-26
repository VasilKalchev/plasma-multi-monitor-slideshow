#!/usr/bin/env python3
"""Keep the display layout you have now, whatever monitors come and go.

KWin saves a separate layout (positions, primary screen, which outputs are
on) for every set of connected monitors. A TV behind an AV receiver can
show up as several different sets: TV on, TV in standby, and "no TV at
all" for a few seconds while it switches. Each set has its own saved
layout, and if they disagree, the monitors jump and Plasma swaps desktops
between screens whenever the TV changes state. KWin only lets you edit
the layout of the set that is currently active, and it overwrites
~/.config/kwinoutputconfig.json from memory, so editing that file by hand
doesn't stick.

Usage: arrange your displays, then run

    kwin-layout-keeper.py

It records the current layout, then re-applies it whenever the layout
changes, until you stop it with Ctrl+C. KWin stores each re-applied
layout for whatever set of monitors is active at that moment, so one pass
through the TV's states (off, on) fixes every set it shows up as.

Monitors are matched by connector name (DP-1, HDMI-A-1, ...), so a TV
that reports a different identity in standby still matches. Only
positions, primary order and enabled/disabled are managed; resolution,
refresh rate and scale are left alone. A monitor that wasn't connected at
startup is left alone too. While it runs it also reverts deliberate
layout changes, so stop it before rearranging.

Needs python3 and kscreen-doctor (KDE Plasma, Wayland or X11).
"""

import argparse
import json
import shutil
import subprocess
import sys
import time


def current_outputs():
    out = subprocess.run(["kscreen-doctor", "-j"], capture_output=True,
                         text=True, check=True).stdout
    return {o["name"]: o for o in json.loads(out)["outputs"] if o.get("connected", True)}


def rank(o):
    """Primary order: KWin's priority (1 = primary) where available, else
    the older single primary flag (kscreen-doctor before Plasma 5.27)."""
    if "priority" in o:
        return o["priority"]
    return 0 if o.get("primary") else 1


def record(outputs):
    layout = {}
    for name, o in outputs.items():
        layout[name] = {"enabled": o["enabled"], "rank": rank(o),
                        "x": o["pos"]["x"], "y": o["pos"]["y"]}
    return layout


def describe(layout):
    for name in sorted(layout, key=lambda n: (not layout[n]["enabled"], layout[n]["rank"], n)):
        v = layout[name]
        print(f"  {name}: " + (f"at {v['x']},{v['y']}" if v["enabled"] else "disabled"))


def differences(layout, outputs):
    """kscreen-doctor arguments that turn `outputs` back into `layout`."""
    args = []
    present = [n for n in layout if n in outputs]
    # Priorities must be 1..n over the enabled outputs that are present, so
    # re-rank the recorded order instead of copying the numbers.
    ranked = sorted((n for n in present if layout[n]["enabled"]),
                    key=lambda n: (layout[n]["rank"], n))
    uses_priority = any("priority" in o for o in outputs.values())
    for name in present:
        want, have = layout[name], outputs[name]
        if not want["enabled"]:
            if have["enabled"]:
                args.append(f"output.{name}.disable")
            continue
        turning_on = not have["enabled"]
        if turning_on:
            args.append(f"output.{name}.enable")
        position = ranked.index(name) + 1
        if uses_priority:
            if turning_on or have.get("priority") != position:
                args.append(f"output.{name}.priority.{position}")
        elif position == 1 and (turning_on or not have.get("primary")):
            args.append(f"output.{name}.primary")
        if turning_on or (have["pos"]["x"], have["pos"]["y"]) != (want["x"], want["y"]):
            args.append(f"output.{name}.position.{want['x']},{want['y']}")
    return args


def main():
    p = argparse.ArgumentParser(
        description="Record the current display layout and re-apply it whenever "
                    "it changes, until stopped with Ctrl+C.")
    p.add_argument("--dry-run", action="store_true",
                   help="print what would be re-applied, change nothing")
    a = p.parse_args()

    if shutil.which("kscreen-doctor") is None:
        sys.exit("kscreen-doctor not found (it ships with KDE Plasma's kscreen)")

    layout = record(current_outputs())
    print("Keeping this layout:")
    describe(layout)
    print("Switch your monitors/TV through their states now. Ctrl+C to stop.")
    try:
        while True:
            args = differences(layout, current_outputs())
            if args:
                print(time.strftime("%H:%M:%S"),
                      ("would apply: " if a.dry_run else "applying: ") + " ".join(args))
                if not a.dry_run:
                    subprocess.run(["kscreen-doctor", *args], capture_output=True)
            # After a change, give KWin a moment to settle before comparing again.
            time.sleep(1.0 if args else 0.2)
    except KeyboardInterrupt:
        print("\nstopped")


if __name__ == "__main__":
    main()
