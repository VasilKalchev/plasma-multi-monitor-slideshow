/*
    The "desk" that spanned images are laid out on, shared by main.qml
    (which places the images) and config.qml (which greys out the settings
    that make no difference for the connected monitors).
*/
.pragma library

// Monitor size corrections (the MonitorSizes setting) are kept per make and
// model, since every monitor of a model has the same size; per connector
// only when the monitor doesn't say what it is.
function monitorKey(s) {
    var model = [s.manufacturer, s.model].filter(function (p) { return p; }).join(" ");
    return model !== "" ? model : s.name;
}

// MonitorSizes entries are "<monitorKey>=<diagonal in inches>".
function parseSizes(entries) {
    var sizes = {};
    for (var i = 0; i < (entries ? entries.length : 0); i++) {
        var e = String(entries[i]);
        var at = e.lastIndexOf("=");
        var inches = parseFloat(e.slice(at + 1));
        if (at > 0 && isFinite(inches) && inches > 0) {
            sizes[e.slice(0, at)] = inches;
        }
    }
    return sizes;
}

// The diagonal in inches the monitor reports (its EDID size, through Qt's
// pixelDensity, which is in the same logical pixels as its width and
// height); 0 if it reports none.
function reportedInches(s) {
    var d = s.pixelDensity;
    return isFinite(d) && d > 0 ? Math.hypot(s.width, s.height) / d / 25.4 : 0;
}

// Pixels per millimetre: from the user's correction if there is one, else
// as reported.
function density(s, sizes) {
    var inches = sizes[monitorKey(s)];
    if (inches !== undefined) {
        return Math.hypot(s.width, s.height) / (inches * 25.4);
    }
    var d = s.pixelDensity;
    return isFinite(d) && d > 0 ? d : 0;
}

// Screens at distinct positions; mirrored screens count once.
function screenCount(screens) {
    var seen = {};
    var n = 0;
    for (var i = 0; i < screens.length; i++) {
        var key = screens[i].virtualX + "," + screens[i].virtualY;
        if (seen[key] === undefined) {
            seen[key] = true;
            n++;
        }
    }
    return n;
}

// The desk is the real, physical arrangement of the screens, measured in
// the largest screen's pixels. Screens differ in pixel size (a 23" 1080p
// pixel is ~14% bigger than a 27" 1440p one), so mapping the image
// pixel-for-pixel across screens makes it visibly larger on the coarser
// one even though a screenshot looks perfect. Each screen's `f` is how many
// reference pixels one of its own pixels spans; 1 when matchPhysicalSize
// is off or a screen's size is unknown.
//
// Placement on the desk follows the display configuration: horizontally,
// screens are chained outward from the reference screen so neighbors stay
// touching (any pixel gap is kept); vertically, a screen keeps its
// relative alignment against the reference - top, centered, bottom, or
// anything in between - measured as a fraction of the height difference.
// This assumes one row of screens, like the pre-split format itself.
function layout(screens, matchPhysicalSize, sizes) {
    var list = [];
    var known = true;
    for (var i = 0; i < screens.length; i++) {
        var s = screens[i];
        var d = { name: s.name, x: s.virtualX, y: s.virtualY, w: s.width, h: s.height, density: density(s, sizes) };
        list.push(d);
        known = known && d.density > 0;
    }
    // The reference is the largest screen: by its real size when every
    // screen's size is known, else by pixel count. A pre-split image's
    // slices are sized to it (see main.qml's computeGeomFor()), so every
    // other screen has to fit inside one slice; by pixel count alone, a big
    // screen with few pixels (a TV) overflowed its slice.
    var usePhys = matchPhysicalSize && known;
    function size(d) {
        return usePhys ? (d.w / d.density) * (d.h / d.density) : d.w * d.h;
    }
    var ref = null;
    for (var r0 = 0; r0 < list.length; r0++) {
        if (ref === null || size(list[r0]) > size(ref)) {
            ref = list[r0];
        }
    }
    // Ordered left-to-right, then top-to-bottom among screens sharing a
    // virtualX; screens sharing both coordinates are mirrored and share
    // an index. Ordering on virtualX alone collapsed a stacked pair to
    // one index.
    list.sort(function (a, b) { return (a.x - b.x) || (a.y - b.y); });
    var refIndex = list.indexOf(ref);
    for (var j = 0; j < list.length; j++) {
        var e = list[j];
        e.f = usePhys ? ref.density / e.density : 1;
        e.dw = e.w * e.f;
        e.dh = e.h * e.f;
        var dh = ref.h - e.h;
        e.dy = Math.abs(dh) < 1 ? e.y
             : ref.y + (e.y - ref.y) / dh * (ref.h - e.dh);
    }
    if (ref !== null) {
        ref.dx = ref.x;
    }
    for (var l = refIndex - 1; l >= 0; l--) {
        var gapL = list[l + 1].x - (list[l].x + list[l].w);
        list[l].dx = list[l + 1].dx - gapL - list[l].dw;
    }
    for (var r = refIndex + 1; r < list.length; r++) {
        var gapR = list[r].x - (list[r - 1].x + list[r - 1].w);
        list[r].dx = list[r - 1].dx + list[r - 1].dw + gapR;
    }
    var minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
    for (var k = 0; k < list.length; k++) {
        minX = Math.min(minX, list[k].dx);
        minY = Math.min(minY, list[k].dy);
        maxX = Math.max(maxX, list[k].dx + list[k].dw);
        maxY = Math.max(maxY, list[k].dy + list[k].dh);
    }
    return { list: list, ref: ref, refIndex: refIndex, usePhys: usePhys,
             box: { x: minX, y: minY, w: maxX - minX, h: maxY - minY } };
}

// Horizontal middle of the screen row on the desk, counted in screens,
// not pixels: with an even count, the bezel between the two middle
// screens; with an odd count, the center of the middle screen.
function middleJoinX(desk) {
    var n = desk.list.length;
    if (n % 2 === 0) {
        return desk.list[n / 2].dx;
    }
    var mid = desk.list[(n - 1) / 2];
    return mid.dx + mid.dw / 2;
}

// The box a panorama covers when it's centered on the join (SpanFit 1):
// the smallest rectangle around every screen whose center is on the middle
// join horizontally and on the largest screen's middle vertically.
function joinBox(desk) {
    var cx = middleJoinX(desk);
    var cy = desk.ref.dy + desk.ref.dh / 2;
    var b = desk.box;
    var halfW = Math.max(cx - b.x, b.x + b.w - cx);
    var halfH = Math.max(cy - b.y, b.y + b.h - cy);
    return { x: cx - halfW, y: cy - halfH, w: 2 * halfW, h: 2 * halfH };
}
