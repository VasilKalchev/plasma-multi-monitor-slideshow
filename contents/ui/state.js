/*
    The saved slideshow state (state.json), for SpanState.qml: what goes
    into the file, how it is checked when read back, and how much of the
    current image's time is left. Pure functions, so they can be tested
    outside Plasma (utils/test-state.py).

    plasmashell writes the file; the lock screen only reads it. See
    "Resuming and the lock screen" in docs/how-it-works.md.
*/
.pragma library

var version = 1;

// The desktop's settings that decide what the slideshow shows and how it
// is drawn, saved with the state so the lock screen can show the
// desktop's slideshow without settings of its own (see FollowDesktop).
// Each with its type: "list" is a list of strings.
var settingTypes = {
    SpanPaths: "list",
    SinglePaths: "list",
    DisabledPaths: "list",
    SlideInterval: "int",
    SlideshowOrder: "int",
    SpanFit: "int",
    MatchPhysicalSize: "bool",
    MonitorSizes: "list",
    SingleFillMode: "int",
    SingleBlur: "bool",
    SingleColor: "string"
};

function toList(v) {
    var out = [];
    if (v !== null && v !== undefined && typeof v !== "string" && v.length !== undefined) {
        for (var i = 0; i < v.length; i++) {
            out.push(String(v[i]));
        }
    }
    return out;
}

// The settings to save, from a screen's settings (a config object or a
// copy of one). A color becomes its "#rrggbb" name.
function settingsOf(config) {
    if (config === null || config === undefined) {
        return null;
    }
    var out = {};
    for (var key in settingTypes) {
        var v = config[key];
        if (v === undefined || v === null) {
            continue;
        }
        var type = settingTypes[key];
        out[key] = type === "list" ? toList(v) : type === "string" ? String(v) : v;
    }
    return out;
}

// The saved settings, keeping only the known ones with the right type, or
// null when there are none (a file from before they were saved).
function parseSettings(v) {
    if (v === null || typeof v !== "object") {
        return null;
    }
    var out = {};
    var any = false;
    for (var key in settingTypes) {
        var x = v[key];
        var type = settingTypes[key];
        var ok = type === "list" ? Array.isArray(x) && x.every(function (e) { return typeof e === "string"; })
               : type === "int" ? isInt(x)
               : type === "bool" ? typeof x === "boolean"
               : typeof x === "string";
        if (ok) {
            out[key] = type === "list" ? x.slice() : x;
            any = true;
        }
    }
    return any ? out : null;
}

// For a command run by the "executable" engine through /bin/sh.
function shellQuote(text) {
    return "'" + String(text).replace(/'/g, "'\\''") + "'";
}

// A short hash of a string: djb2 with a final mix, as 8 hex digits.
function hash(text) {
    var h = 5381;
    for (var i = 0; i < text.length; i++) {
        h = (Math.imul(h, 33) + text.charCodeAt(i)) | 0;
    }
    h = Math.imul(h ^ (h >>> 16), 0x85ebca6b);
    h = Math.imul(h ^ (h >>> 13), 0xc2b2ae35);
    h = (h ^ (h >>> 16)) >>> 0;
    return ("0000000" + h.toString(16)).slice(-8);
}

// A saved position only fits the image lists it was saved with: the order
// and both lists, as SpanState.configure() sorts them. Also the length of
// each list, so two lists that only differ in where one ends and the other
// begins don't give the same text.
function listsCheck(order, spanImages, singleImages) {
    return hash(order + "|" + spanImages.length + "|" + singleImages.length + "|"
                + spanImages.join("\n") + "|" + singleImages.join("\n"));
}

// state: { written, order, interval, seed, tick, shown, check, count, span,
// images, settings }
function serialize(state) {
    return JSON.stringify({
        v: version,
        written: state.written,
        order: state.order,
        interval: state.interval,
        seed: state.seed,
        tick: state.tick,
        shown: state.shown,
        check: state.check,
        count: state.count,
        span: state.span,
        images: state.images,
        settings: state.settings
    });
}

function isInt(n) {
    return typeof n === "number" && isFinite(n) && Math.floor(n) === n;
}

// The file's text as a state object, or null if it isn't a state file this
// version can use (empty, cut off, edited by hand, another version).
function parse(text) {
    var s;
    try {
        s = JSON.parse(text);
    } catch (e) {
        return null;
    }
    if (s === null || typeof s !== "object" || s.v !== version) {
        return null;
    }
    if (!isInt(s.written) || !isInt(s.order) || !isInt(s.interval) || !isInt(s.seed) || !isInt(s.tick)
            || typeof s.shown !== "number" || !isFinite(s.shown) || typeof s.check !== "string") {
        return null;
    }
    if (s.tick < 0 || s.shown < 0) {
        return null;
    }
    var images = {};
    if (s.images !== null && typeof s.images === "object") {
        for (var name in s.images) {
            if (typeof s.images[name] === "string") {
                images[name] = s.images[name];
            }
        }
    }
    return {
        written: s.written,
        order: s.order,
        interval: s.interval,
        seed: s.seed,
        tick: s.tick,
        shown: s.shown,
        check: s.check,
        count: isInt(s.count) && s.count >= 0 ? s.count : -1,
        span: s.span === true,
        images: images,
        settings: parseSettings(s.settings)
    };
}

// The heartbeat of plasmashell that saved the state: it writes the file at
// least this often (in seconds) while it is awake. `interval` is the one
// saved in the file.
function beatOf(interval) {
    return Math.max(1, Math.min(60, interval));
}

// Seconds left of the current image's time. `shown` is the screen time
// saved with the state. The lock screen (follower) adds the time since the
// file was written, since the desktop has been running behind it. But at
// most one beat (`beat`, see beatOf()): the desktop writes at least once a
// beat while awake, so more time than that since the last write was spent
// asleep, and sleep isn't screen time. Without the cap the lock screen
// showed the next image after waking, and went back a minute later.
// plasmashell itself adds nothing: the time since its last write may have
// been spent switched off.
function remaining(interval, shown, written, now, follower, beat) {
    var seen = shown;
    if (follower && now > written) {
        seen += Math.min((now - written) / 1000, beat);
    }
    return interval - seen;
}

// Writes the file safely: a temporary file, renamed into place, so a crash
// in the middle never leaves half a file.
function saveCommand(dir, text) {
    var file = dir + "/state.json";
    return "mkdir -p " + shellQuote(dir) + " && printf '%s\\n' " + shellQuote(text) + " > " + shellQuote(file + ".tmp")
        + " && mv -f " + shellQuote(file + ".tmp") + " " + shellQuote(file);
}
