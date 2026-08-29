/*
    Multi-Monitor Slideshow wallpaper plugin.

    Handles two kinds of wallpaper:
      - "Span" images (from SpanPaths, e.g. a dual-monitor panorama): shown
        stretched across every monitor together, like Windows' "Span"
        wallpaper mode, perfectly synced so all screens show the same
        picture at the same time.
      - "Single" images (from SinglePaths, ordinary wallpapers): shown one
        per monitor, independently chosen per screen, exactly like the
        built-in Slideshow plugin.

    Cross-screen sync (for span images, and for keeping every screen's
    rotation in lockstep about *when* to change) is handled by the
    SpanState singleton (SpanState.qml): Plasma's wallpaper views for a
    single corona all run in one QML engine, so a QML singleton is a
    true shared object, not a per-screen copy. Whichever screen's timer
    fires first advances the shared state, and every screen reacts
    immediately via ordinary property bindings - no clock math, no
    polling, no IPC.
*/
import QtQuick
import QtQuick.Window
import QtQml.Models
import Qt.labs.folderlistmodel
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid

WallpaperItem {
    id: root

    readonly property var cfg: root.configuration

    readonly property bool isSpanTurn: SpanState.isSpanTurn
    property string currentSource: isSpanTurn ? SpanState.currentSpanImage : computeMySingleSource()

    // Cache of image URL -> natural pixel size, so an image that has
    // already been shown once never needs to be re-probed. Without this,
    // a short rotation interval could keep resetting the probe before it
    // finishes loading, permanently falling back to panorama treatment
    // for images that are actually pre-composed multi-monitor halves.
    property var _probeCache: ({})

    // Two picture layers (ImageLayer.qml), crossfaded, so changing
    // wallpapers doesn't flash to black like a plain source swap would (the
    // default Slideshow plugin crossfades too). `front` is the opaque one. A
    // new picture loads into the other one (`pending`) and only becomes the
    // front once it has actually finished decoding, and a spanned picture
    // once its shape is measured too - otherwise the fade-in would be a
    // fade to blank, or to a picture that then jumps into place. Only the
    // pending layer can take over: a geometry change makes both layers
    // decode again, and the other layer's old picture would otherwise come
    // back to the front.
    property ImageLayer front: layerA
    property ImageLayer pending: null
    readonly property ImageLayer back: front === layerA ? layerB : layerA

    function loadSource(src, isSpan) {
        // First-ever load: straight onto the front layer, no fade -
        // there's nothing on screen yet to fade from.
        var layer = String(front.source) === "" ? front : back;
        layer.span = isSpan;
        layer.probeSize = _probeCache[src] !== undefined ? _probeCache[src] : Qt.size(0, 0);
        layer.geom = computeGeomFor(isSpan, layer.probeSize);
        layer.source = src;
        pending = layer;
    }

    // Called when a layer's status changes, and when its picture is
    // measured.
    function layerChanged(layer) {
        if (layer.status === Image.Ready || layer.status === Image.Error) {
            root.loading = false;
        }
        if (layer !== pending) {
            return;
        }
        if (layer.status === Image.Error) {
            pending = null;
        } else if (layer.status === Image.Ready && layer.placed) {
            pending = null;
            front = layer;
        }
    }

    // A layer that has faded out lets go of its picture.
    function layerFaded(layer) {
        if (layer.opacity === 0 && layer !== front && layer !== pending) {
            layer.source = "";
        }
    }

    function layerMeasured(layer) {
        var cache = _probeCache;
        cache[String(layer.source)] = layer.probeSize;
        _probeCache = cache;
        // A new size makes the layer decode again; the same size doesn't.
        layer.geom = computeGeomFor(layer.span, layer.probeSize);
        layerChanged(layer);
    }

    // The binding re-fires with an unchanged value whenever something it
    // reads changes, e.g. every step of a display reconfiguration. Don't
    // decode and fade the picture already on screen into itself; just drop
    // another picture that may still be loading, which would otherwise
    // replace it when ready.
    onCurrentSourceChanged: {
        if (currentSource !== ""
                && currentSource === String(front.source)
                && isSpanTurn === front.span) {
            if (pending === back) {
                back.source = "";
                pending = null;
            }
            return;
        }
        loadSource(currentSource, isSpanTurn);
    }

    // A fixed, per-screen number, so each screen's independent "single
    // image" pick differs from the others'. Derived from the screen's
    // connector name (DP-1, HDMI-A-1, ...), which stays the same when the
    // display layout changes: it used to come from the screen's position,
    // so every layout change (including the burst of reconfigurations
    // while a TV powers on) switched every screen to a different image,
    // and two screens that briefly shared a position showed the same one.
    // The final mixing step matters: names like DP-1 and DP-2 differ only
    // in the last character, so a plain string hash gives neighbouring
    // numbers. Falls back to the position only if the name is unknown.
    function screenSalt() {
        var name = root.myScreenName || ("pos:" + Math.floor(myVX) + "," + Math.floor(myVY));
        var h = 5381;
        for (var i = 0; i < name.length; i++) {
            h = (Math.imul(h, 33) + name.charCodeAt(i)) | 0;
        }
        h = Math.imul(h ^ (h >>> 16), 0x85ebca6b);
        h = Math.imul(h ^ (h >>> 13), 0xc2b2ae35);
        return (h ^ (h >>> 16)) | 0;
    }

    // Reads the list off SpanState rather than a local copy, so a screen
    // that skipped the scan (see claimScan) still renders, and so this
    // binding re-evaluates when the scanning screen publishes its results.
    // Each screen walks its own shuffle of the list (seeded with its salt),
    // not the same shuffle at an offset: with a shared order, screens
    // whose offsets are close show each other's pictures a few changes
    // apart.
    function computeMySingleSource() {
        var images = SpanState.singleImages;
        if (images.length === 0) {
            return "";
        }
        var tick = SpanState.tickCount;
        var sLap = Math.floor(tick / images.length);
        var sPos = tick % images.length;
        var seed = (SpanState.baseSeed + 500000 + Math.imul(sLap, 0x9e3779b1)) ^ screenSalt();
        var sOrder = SpanState.shuffledOrder(images, seed);
        return sOrder[sPos];
    }

    // -- contextual (right-click) actions, mirroring the built-in Slideshow plugin --
    // A real cascading submenu isn't possible from pure QML here (it'd need
    // an actual QMenu*, which no QML-constructible type in this plugin's
    // available imports subclasses) - confirmed by trying Qt.labs.platform.Menu,
    // which the shell rejected outright. This disabled header is a
    // pseudo-grouping stand-in instead.
    contextualActions: [wallpaperHeaderAction, openWallpaperAction, nextAction, nextIndividualAction, nextSpannedAction]

    PlasmaCore.Action {
        id: wallpaperHeaderAction
        text: i18nd("plasma_wallpaper_com.github.vasilkalchev.multimonitorslideshow", "Wallpaper")
        enabled: false
        // Independently removable via its own config toggle, but also
        // auto-hides once every entry under it is hidden, rather than
        // leaving a dangling disabled label with nothing below it.
        visible: cfg.ShowWallpaperHeader === true
                 && (cfg.ShowOpenImageAction !== false || cfg.ShowNextAction !== false
                     || cfg.ShowNextIndividualAction === true || cfg.ShowNextSpannedAction === true)
    }

    PlasmaCore.Action {
        id: openWallpaperAction
        text: i18nd("plasma_wallpaper_com.github.vasilkalchev.multimonitorslideshow", "Open Image")
        icon.name: "document-open"
        enabled: root.currentSource !== ""
        visible: cfg.ShowOpenImageAction !== false
        onTriggered: Qt.openUrlExternally(root.currentSource)
    }

    PlasmaCore.Action {
        id: nextAction
        text: i18nd("plasma_wallpaper_com.github.vasilkalchev.multimonitorslideshow", "Next")
        icon.name: "media-skip-forward"
        visible: cfg.ShowNextAction !== false
        onTriggered: SpanState.advance()
    }

    PlasmaCore.Action {
        id: nextIndividualAction
        text: i18nd("plasma_wallpaper_com.github.vasilkalchev.multimonitorslideshow", "Next Individual")
        icon.name: "view-restore"
        enabled: SpanState.singleImages.length > 0
        visible: cfg.ShowNextIndividualAction === true
        onTriggered: SpanState.advanceToSingle()
    }

    PlasmaCore.Action {
        id: nextSpannedAction
        text: i18nd("plasma_wallpaper_com.github.vasilkalchev.multimonitorslideshow", "Next Spanned")
        icon.name: "view-fullscreen"
        enabled: SpanState.spanImages.length > 0
        visible: cfg.ShowNextSpannedAction === true
        onTriggered: SpanState.advanceToSpan()
    }

    // -- folder scanning: flat, one level deep --
    // One FolderListModel per folder, created by the Instantiator below with
    // its `folder` bound at construction, and torn down once every folder
    // has reported. FolderListModel is built to be configured declaratively
    // once: a single shared model driven imperatively (reassigning `folder`
    // in a loop) races its own initial scan of the default folder, which
    // delivers a Ready carrying the previous folder's rows and throws every
    // later Ready off by one. With the folder fixed at construction there is
    // no earlier scan to race, each model reports exactly the folder it
    // owns, and results are kept per job rather than by arrival order.
    // Scanning also runs concurrently, one model (and thread) per folder,
    // only while a scan is in flight.
    property var _scanJobs: []        // [{ kind: "span" | "single", folder: url, gen: int }]
    property var _scanResults: []     // per job index: array of image URLs, or undefined
    property int _scanPending: 0
    property int _scanGeneration: 0

    Instantiator {
        model: root._scanJobs
        delegate: FolderListModel {
            required property var modelData
            required property int index
            property bool reported: false

            folder: modelData.folder
            showDirs: false
            showFiles: true
            // caseSensitive: false rather than listing each extension twice -
            // the doubled list still missed mixed-case spellings like ".JpEg"
            // that come out of some cameras and editors.
            caseSensitive: false
            nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.webp", "*.bmp"]

            function report() {
                if (reported || status !== FolderListModel.Ready) {
                    return;
                }
                reported = true;
                var files = [];
                for (var i = 0; i < count; i++) {
                    files.push(get(i, "fileUrl").toString());
                }
                root._scanReport(modelData.gen, index, files);
            }
            onStatusChanged: report()
            Component.onCompleted: report()
        }
    }

    function _scanReport(gen, index, files) {
        if (gen !== _scanGeneration || _scanResults[index] !== undefined) {
            return;
        }
        var results = _scanResults.slice();
        results[index] = files;
        _scanResults = results;
        _scanPending = _scanPending - 1;
        if (_scanPending === 0) {
            _scanFinish();
        }
    }

    function _scanFinish() {
        var span = [], single = [];
        for (var i = 0; i < _scanJobs.length; i++) {
            var target = _scanJobs[i].kind === "span" ? span : single;
            var files = _scanResults[i] || [];
            for (var j = 0; j < files.length; j++) {
                target.push(files[j]);
            }
        }
        SpanState.configure(span, single, cfg.SlideInterval);
        // Tear the models down (and their threads with them). Deferred: this
        // runs inside the last model's own status handler.
        var gen = _scanGeneration;
        Qt.callLater(function () {
            if (root._scanGeneration === gen) {
                root._scanJobs = [];
                root._scanResults = [];
            }
        });
    }

    function _configSignature() {
        return [JSON.stringify(cfg.SpanPaths || []), JSON.stringify(cfg.SinglePaths || []),
                cfg.SlideInterval].join("|");
    }

    // The folders are scanned again on every tick, so images added to or
    // deleted from them are picked up at the next change. Only one screen
    // walks the folders per tick; the rest read the results off SpanState.
    // claimScan() is the sole gate, and it answers the whole question - has
    // this config been scanned at this tick, by anyone, and did that scan
    // live long enough to finish - which is why this is cheap to call from
    // every screen rather than tracking a locally-scanned signature.
    function rescan() {
        if (!SpanState.claimScan(_configSignature() + "|" + SpanState.tickCount)) {
            return;
        }
        _scanGeneration = _scanGeneration + 1;
        var gen = _scanGeneration;
        var jobs = [];
        (cfg.SpanPaths || []).forEach(function (f) {
            jobs.push({ kind: "span", folder: f, gen: gen });
        });
        (cfg.SinglePaths || []).forEach(function (f) {
            jobs.push({ kind: "single", folder: f, gen: gen });
        });
        _scanResults = [];
        _scanPending = jobs.length;
        _scanJobs = jobs;
        if (jobs.length === 0) {
            _scanFinish();
        }
    }

    // Mirrors SpanState.tickCount, which advances both on the normal
    // interval and on an explicit "Next ..." click - so this fires in both
    // cases, and only then.
    //
    // Folder-list changes made through the System Settings dialog don't
    // reliably reach an already-running instance via the config object's
    // change signals (the dialog appears to apply changes to the
    // underlying config file without always notifying the live wallpaper
    // item). So rather than polling on a schedule of our own, re-ask right
    // when the wallpaper is about to change: an edit in Settings takes
    // effect on the next rotation, and any of the "Next ..." context-menu
    // actions doubles as an explicit "apply now".
    property int lastTick: SpanState.tickCount
    onLastTickChanged: {
        rescan();
        refreshGeometry();
    }

    function refreshGeometry() {
        layerA.geom = computeGeomFor(layerA.span, layerA.probeSize);
        layerB.geom = computeGeomFor(layerB.span, layerB.probeSize);
    }

    // -- keeping geometry current --
    // Geometry is computed when an image loads, not bound, so it has to be
    // refreshed by hand whenever something it depends on changes: this
    // screen's own size, or any screen's position or size.
    // Without this, a display that appears for a moment (a TV being turned
    // on) left a screen drawing its image at a stale size - Plasma briefly
    // resizes or rebuilds the wallpaper views, and the size taken during
    // that moment stuck until the next rotation. Debounced, so a burst of
    // changes (a TV powering on can flip the layout back and forth for a
    // while) settles into one recompute against the final layout.
    readonly property string screenLayout: {
        var screens = Qt.application.screens;
        var parts = [];
        for (var i = 0; i < screens.length; i++) {
            var s = screens[i];
            parts.push([s.virtualX, s.virtualY, s.width, s.height].join(","));
        }
        return parts.join(";") + "|" + root.width + "x" + root.height;
    }
    onScreenLayoutChanged: geomRefresh.restart()

    Timer {
        id: geomRefresh
        interval: 1500
        onTriggered: root.refreshGeometry()
    }

    // -- cross-screen spanning geometry --
    readonly property string myScreenName: Screen.name
    readonly property real myVX: Screen.virtualX
    readonly property real myVY: Screen.virtualY

    // All span geometry is worked out on a shared "desk": the arrangement
    // of the screens in the display configuration, in pixels, with the
    // largest screen as the reference. This assumes one row of screens,
    // like the pre-split format itself.
    function deskLayout() {
        var screens = Qt.application.screens;
        var list = [];
        var ref = null;
        for (var i = 0; i < screens.length; i++) {
            var s = screens[i];
            var d = { name: s.name, x: s.virtualX, y: s.virtualY, w: s.width, h: s.height };
            d.dx = d.x;
            d.dy = d.y;
            d.dw = d.w;
            d.dh = d.h;
            list.push(d);
            if (ref === null || d.w * d.h > ref.w * ref.h) {
                ref = d;
            }
        }
        // Ordered left-to-right, then top-to-bottom among screens sharing a
        // virtualX; screens sharing both coordinates are mirrored and share
        // an index. Ordering on virtualX alone collapsed a stacked pair to
        // one index.
        list.sort(function (a, b) { return (a.x - b.x) || (a.y - b.y); });
        var refIndex = list.indexOf(ref);
        // Find this screen by connector name first: while the layout is
        // changing, this item's own position can lag behind the screen list,
        // and a position match would then pick the wrong screen.
        var me = list[0];
        for (var m = 0; m < list.length; m++) {
            if (root.myScreenName !== "" ? list[m].name === root.myScreenName
                                         : (list[m].x === root.myVX && list[m].y === root.myVY)) {
                me = list[m];
                break;
            }
        }
        var minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
        for (var k = 0; k < list.length; k++) {
            minX = Math.min(minX, list[k].dx);
            minY = Math.min(minY, list[k].dy);
            maxX = Math.max(maxX, list[k].dx + list[k].dw);
            maxY = Math.max(maxY, list[k].dy + list[k].dh);
        }
        return { list: list, ref: ref, refIndex: refIndex, me: me,
                 box: { x: minX, y: minY, w: maxX - minX, h: maxY - minY } };
    }

    // Geometry for a display layer: where to position/size it so it shows
    // the right content for this screen. Pure function of (isSpan,
    // probeSize) - each of the two crossfade layers calls this with its
    // own state, since they can be showing images of different kinds/
    // aspect ratios mid-transition. Every span branch picks a box on the
    // desk; toLocal() converts it into this screen's own pixels.
    function computeGeomFor(isSpan, probeSize) {
        if (!isSpan) {
            return { w: root.width, h: root.height, x: 0, y: 0, stretch: false };
        }
        var desk = deskLayout();
        var me = desk.me, ref = desk.ref, n = desk.list.length;
        function toLocal(b, stretch) {
            return {
                w: b.w,
                h: b.h,
                x: b.x - me.dx,
                y: b.y - me.dy,
                stretch: stretch
            };
        }

        if (probeSize.width > 0 && probeSize.height > 0) {
            // Some "span" wallpapers are pre-composed as N equal-width
            // halves/thirds/etc., one per monitor (common for "dual
            // monitor wallpaper" packs), rather than one continuous
            // panorama. When a 1/N-wide slice of the image already has
            // this screen's own aspect ratio, treat it that way.
            var unitW = probeSize.width / n;
            var unitAspect = unitW / probeSize.height;
            var myAspect = me.w / me.h;
            if (Math.abs(unitAspect - myAspect) / myAspect < 0.03) {
                // Each slice is one reference-screen-sized unit on the desk,
                // laid out so the reference screen's own slice sits exactly
                // on it. Every other screen shows whatever part of its slice
                // it covers: a smaller screen next to the reference loses its
                // slice's outer edge, never the edge at the seam, and its
                // vertical crop follows its real alignment.
                //
                // Stretch, not PreserveAspectCrop: the slice's aspect only
                // matches the screen's within 3%, and PreserveAspectCrop
                // would absorb that gap with its own crop centered on this
                // layer's box - not on this screen's window into it - so the
                // seam would drift off the bezel toward the top and bottom
                // of any non-reference screen. Stretch maps source pixels to
                // exactly this box, so all screens agree on every pixel, at
                // the cost of an imperceptible sub-3% non-uniform stretch.
                return toLocal({
                    x: ref.dx - desk.refIndex * ref.dw,
                    y: ref.dy,
                    w: ref.dw * n,
                    h: ref.dh
                }, true);
            }
        }
        // Continuous panorama: cover-fit the whole image onto the box
        // around every screen on the desk, then crop out this screen.
        return toLocal(desk.box, false);
    }

    // Plasma keeps its splash screen up until `loading` clears. It clears
    // when the first picture is decoded, or here when there is nothing to
    // show (no folders, or only empty ones).
    readonly property bool nothingToShow: SpanState.scanCompleted !== ""
        && SpanState.spanImages.length + SpanState.singleImages.length === 0
    onNothingToShowChanged: {
        if (nothingToShow) {
            root.loading = false;
        }
    }

    Component.onCompleted: {
        root.loading = !nothingToShow;
        Qt.callLater(function () { root.rescan(); });
    }

    Item {
        anchors.fill: parent
        clip: true

        ImageLayer {
            id: layerA
            shown: root.front === layerA
            onStatusChanged: root.layerChanged(layerA)
            onOpacityChanged: root.layerFaded(layerA)
            onMeasured: root.layerMeasured(layerA)
        }

        ImageLayer {
            id: layerB
            shown: root.front === layerB
            onStatusChanged: root.layerChanged(layerB)
            onOpacityChanged: root.layerFaded(layerB)
            onMeasured: root.layerMeasured(layerB)
        }
    }
}
