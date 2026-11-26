#!/usr/bin/env python3
"""Tests for the saved slideshow state: contents/ui/state.js, and the lap order in SpanState.qml.

Runs the plugin's JavaScript in Qt's own engine (QJSEngine), the one Plasma uses:

    uv run --no-project --with pyside6-essentials utils/test-state.py

The state.js functions are loaded with the ".pragma library" line removed. From SpanState.qml, the functions
the lap order needs are cut out by name (from "    function name(" to the next "\\n    }\\n") and run with the
properties they read held in a plain object.
"""

import json
import os
import subprocess
import sys
import tempfile

from PySide6.QtCore import QCoreApplication
from PySide6.QtQml import QJSEngine

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
UI = os.path.join(ROOT, "contents", "ui")

failures = 0  # failed checks
checks = 0    # all checks


def check(name, ok, detail=""):
    global failures, checks
    checks += 1
    if not ok:
        failures += 1
        print(f"FAIL {name} {detail}")


def load_engine():
    engine = QJSEngine()
    with open(os.path.join(UI, "state.js"), encoding="utf-8") as f:
        source = f.read().replace(".pragma library", "")
    result = engine.evaluate(source, "state.js")
    if result.isError():
        sys.exit(f"state.js: {result.toString()}")
    with open(os.path.join(UI, "SpanState.qml"), encoding="utf-8") as f:
        qml = f.read()
    names = ["mulberry32", "shuffledOrder", "rangeArray", "lapOrder"]
    parts = []
    for name in names:
        start = qml.index(f"    function {name}(")
        end = qml.index("\n    }\n", start) + len("\n    }\n")
        body = qml[start:end].strip()
        parts.append(f"st.{name} = {body};")
    script = "var st = { baseSeed: 0, _shuffledLap: -1, _shuffledIndices: [] };\nwith (st) {\n" + "\n".join(parts) + "\n}"
    result = engine.evaluate(script, "SpanState.qml")
    if result.isError():
        sys.exit(f"SpanState.qml functions: {result.toString()}")
    return engine


def js(engine, expression):
    result = engine.evaluate(expression)
    if result.isError():
        raise RuntimeError(f"{expression}: {result.toString()}")
    return json.loads(engine.evaluate(f"JSON.stringify({expression})").toString())


def test_parse(engine):
    state = {"written": 1795721697123, "order": 0, "interval": 1800, "seed": 425368678, "tick": 42, "shown": 540,
             "check": "a1b2c3d4", "count": 2, "span": True,
             "images": {"HDMI-A-1": "file:///a.jpg", "HDMI-A-2": "file:///a.jpg"}, "settings": None}
    text = js(engine, f"serialize({json.dumps(state)})")
    back = js(engine, f"parse({json.dumps(text)})")
    check("round trip", back == state, f"{back}")
    check("round trip has the version", json.loads(text)["v"] == 1)

    bad = ["", "{", "null", "[]", "42", '"x"']
    for text in bad:
        check(f"parse rejects {text!r}", js(engine, f"parse({json.dumps(text)})") is None)
    good = json.loads(js(engine, f"serialize({json.dumps(state)})"))
    changes = [("v", 2), ("tick", -1), ("tick", 1.5), ("shown", -3), ("seed", "x"), ("check", 5), ("written", None),
               ("order", "0")]
    for key, value in changes:
        edited = dict(good)
        edited[key] = value
        result = js(engine, f"parse({json.dumps(json.dumps(edited))})")
        check(f"parse rejects {key}={value!r}", result is None, f"{result}")
    missing = dict(good)
    del missing["interval"]
    check("parse rejects a missing field", js(engine, f"parse({json.dumps(json.dumps(missing))})") is None)
    odd = dict(good)
    odd["images"] = {"DP-1": "file:///b.jpg", "DP-2": 7}
    odd["span"] = "yes"
    result = js(engine, f"parse({json.dumps(json.dumps(odd))})")
    check("parse keeps only string images", result is not None and result["images"] == {"DP-1": "file:///b.jpg"})
    check("parse takes only true as span", result is not None and result["span"] is False)


def test_settings(engine):
    config = {"SpanPaths": ["file:///a"], "SinglePaths": [], "DisabledPaths": ["file:///b"], "SlideInterval": 1800,
              "SlideshowOrder": 0, "SpanFit": 1, "MatchPhysicalSize": True, "MonitorSizes": ["AOC 2369=23"],
              "SingleFillMode": 2, "SingleBlur": False, "SingleColor": "#102030", "ConfigStamp": "123",
              "ShowNextAction": True}
    saved = js(engine, f"settingsOf({json.dumps(config)})")
    expected = {k: v for k, v in config.items() if k not in ("ConfigStamp", "ShowNextAction")}
    check("settingsOf keeps the slideshow's settings only", saved == expected, f"{saved}")
    check("settingsOf of nothing", js(engine, "settingsOf(null)") is None)
    check("settingsOf turns a color into its name", js(engine, "settingsOf({ SingleColor: { toString: function () { "
                                                               "return '#abcdef'; } } }).SingleColor") == "#abcdef")
    state = {"written": 1, "order": 0, "interval": 1800, "seed": 2, "tick": 3, "shown": 4, "check": "c", "count": 476,
             "span": True, "images": {}, "settings": expected}
    back = js(engine, f"parse(serialize({json.dumps(state)}))")
    check("round trip with settings", back == state, f"{back}")
    odd = dict(state, v=1)
    odd["settings"] = {"SpanPaths": "file:///a", "SlideInterval": 1.5, "SpanFit": 1, "SingleBlur": "no",
                       "MonitorSizes": ["x", 3]}
    result = js(engine, f"parse({json.dumps(json.dumps(odd))})")
    check("parse keeps only settings of the right type", result["settings"] == {"SpanFit": 1}, f"{result['settings']}")
    old = dict(state, v=1)
    del old["settings"]
    del old["count"]
    result = js(engine, f"parse({json.dumps(json.dumps(old))})")
    check("a file without settings still parses", result is not None and result["settings"] is None)
    check("a file without a count gives -1", result is not None and result["count"] == -1)


def test_remaining(engine):
    check("remaining, desktop", js(engine, "remaining(1800, 540, 1000, 999999, false, 60)") == 1260)
    check("remaining, lock screen adds the time since the write",
          js(engine, "remaining(1800, 540, 1000, 41000, true, 60)") == 1220)
    check("remaining, lock screen adds at most one beat",
          js(engine, "remaining(1800, 540, 1000, 61000, true, 60)") == 1200)
    check("remaining, clock behind the write", js(engine, "remaining(1800, 540, 61000, 1000, true, 60)") == 1260)
    check("remaining, time up", js(engine, "remaining(120, 150, 0, 0, false, 60)") == -30)
    # Locked at 10 of 30 minutes, the last write 20 s before sleeping, 8 hours asleep, woken 5 s ago: the desktop's
    # image has been on screen for 10 min + 25 s, and the 8 hours must not count.
    written = 1_000_000
    now = written + (20 + 8 * 3600 + 5) * 1000
    left = js(engine, f"remaining(1800, 600, {written}, {now}, true, beatOf(1800))")
    check("remaining, sleep doesn't count on the lock screen", left == 1800 - 600 - 60 and left > 0, f"{left}")
    check("beatOf, long interval", js(engine, "beatOf(1800)") == 60)
    check("beatOf, short interval", js(engine, "beatOf(20)") == 20)
    check("beatOf, broken interval", js(engine, "beatOf(0)") == 1)


def test_check(engine):
    base = js(engine, 'listsCheck(0, ["a", "b"], ["c"])')
    check("check is 8 hex digits", len(base) == 8 and all(c in "0123456789abcdef" for c in base), base)
    check("check is stable", js(engine, 'listsCheck(0, ["a", "b"], ["c"])') == base)
    others = ['listsCheck(1, ["a", "b"], ["c"])', 'listsCheck(0, ["a"], ["b", "c"])', 'listsCheck(0, ["a", "b"], [])',
              'listsCheck(0, ["a", "b", "d"], ["c"])', 'listsCheck(0, ["b", "a"], ["c"])',
              'listsCheck(0, ["a", "b"], ["c2"])']
    for expression in others:
        check(f"check changes: {expression}", js(engine, expression) != base)


def test_save_command(engine):
    with tempfile.TemporaryDirectory() as scratch:
        folder = os.path.join(scratch, "it's a \"dir\" $HOME")
        text = json.dumps({"url": "file:///home/user/it's $(echo x) `y` \\ \"z\".jpg"})
        command = js(engine, f"saveCommand({json.dumps(folder)}, {json.dumps(text)})")
        subprocess.run(["/bin/sh", "-c", command], check=True)
        with open(os.path.join(folder, "state.json"), encoding="utf-8") as f:
            written = f.read()
        check("save writes the text unchanged", written == text + "\n", repr(written))
        check("save leaves no temporary file", os.listdir(folder) == ["state.json"], f"{os.listdir(folder)}")
        quoted = js(engine, 'shellQuote("a\'b")')
        check("shellQuote", quoted == "'a'\\''b'", quoted)


# The lap order as SpanState.pickCurrent() worked it out before: the swap took the previous lap from the cache,
# which a process only has if it went through that lap.
OLD_ORDER = """
function oldLaps(seed, total, laps) {
    var cache = [];
    var out = [];
    for (var lap = 0; lap < laps; lap++) {
        var shuffled = st.shuffledOrder(st.rangeArray(total), seed + lap);
        if (lap > 0 && cache.length > 0) {
            var prevLast = cache[cache.length - 1];
            if (shuffled[0] === prevLast && shuffled.length > 1) {
                var t = shuffled[0];
                shuffled[0] = shuffled[1];
                shuffled[1] = t;
            }
        }
        cache = shuffled;
        out.push(shuffled);
    }
    return out;
}
"""


def test_lap_order(engine):
    engine.evaluate(OLD_ORDER)
    for total in [1, 2, 3, 476]:
        for seed in [1, 12345, 425368678, 2147483646]:
            laps = 12 if total < 4 else 6
            old = js(engine, f"oldLaps({seed}, {total}, {laps})")
            for lap in range(laps):
                cold = js(engine, f"(st.baseSeed = {seed}, st._shuffledLap = -1, st._shuffledIndices = [], "
                                  f"st.lapOrder({lap}, {total}))")
                check(f"lap {lap} of {total} (seed {seed}), cold", cold == old[lap])
                if lap > 0:
                    warm = js(engine, f"(st.baseSeed = {seed}, st._shuffledLap = {lap - 1}, "
                                      f"st._shuffledIndices = {json.dumps(old[lap - 1])}, st.lapOrder({lap}, {total}))")
                    check(f"lap {lap} of {total} (seed {seed}), warm", warm == old[lap])
            swaps = sum(1 for lap in range(1, laps) if old[lap][0] != js(engine, f"st.shuffledOrder(st.rangeArray("
                                                                                 f"{total}), {seed} + {lap})")[0])
            if total == 2 and seed == 1:
                print(f"  2 images, seed 1: {swaps} of {laps - 1} laps swapped")


def main():
    QCoreApplication(sys.argv)
    engine = load_engine()
    test_parse(engine)
    test_settings(engine)
    test_remaining(engine)
    test_check(engine)
    test_save_command(engine)
    test_lap_order(engine)
    print(f"{checks - failures} of {checks} checks passed")
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
