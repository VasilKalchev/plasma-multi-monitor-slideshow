/*
    Shared state for every screen's Multi-Monitor Slideshow wallpaper instance.

    Plasma's wallpaper views for a single corona all run in one QML
    engine, so a QML singleton is visible to every screen at once. That
    means we don't need clock-derived math or polling to keep screens in
    sync: whichever screen's Timer fires first advances tickCount here,
    and every screen instance reacts to that change immediately via
    ordinary property bindings, with zero IPC.
*/
pragma Singleton
import QtQuick

QtObject {
    id: root

    // Randomized once per plasmashell startup, not a fixed constant: all
    // screens still share this single value (it's a QML singleton), so
    // cross-screen sync doesn't need it to be stable across restarts, and
    // leaving it fixed made every reboot replay the exact same shuffle
    // order starting from the same first image.
    readonly property int baseSeed: Date.now() % 2147483647

    property var spanImages: []
    property var singleImages: []
    property int slideInterval: 900

    // Advances by one every "slideInterval" seconds (see the Timer
    // below). Screens showing an independent "single" image use this
    // plus their own per-screen salt to pick their own image, so they
    // all change at the same moment even though they show different
    // pictures.
    property int tickCount: 0

    property bool isSpanTurn: false
    property string currentSpanImage: ""

    // SlideshowOrder: 0 = random, 1 = A to Z, 2 = Z to A, 3 = date
    // modified (newest first), 4 = date modified (oldest first).
    property int order: 0
    // Sorted orders only: on a single-image turn, screen k (counted left to
    // right) shows singleImages[singleStart + k], so every screen shows the
    // next image in line and one turn uses up one image per screen.
    property int singleStart: 0

    property var _shuffledIndices: []
    property int _shuffledLap: -1

    // Sorted orders only: one lap of turns, each { span: url } or
    // { single: index into singleImages }, built for _turnsScreens screens.
    property var _turns: []
    property int _turnsScreens: -1
    property var _sortKeys: ({})     // url -> { name: lowercase file name, time: ms }

    // Screens at distinct positions; mirrored screens show the same image.
    readonly property int screenCount: {
        var screens = Qt.application.screens;
        var seen = {};
        var n = 0;
        for (var i = 0; i < screens.length; i++) {
            var key = screens[i].virtualX + "," + screens[i].virtualY;
            if (seen[key] === undefined) {
                seen[key] = true;
                n++;
            }
        }
        return Math.max(1, n);
    }

    // -- deterministic seeded PRNG (mulberry32) --
    function mulberry32(seed) {
        return function () {
            seed |= 0;
            seed = (seed + 0x6D2B79F5) | 0;
            var t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
            t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
            return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
        };
    }

    function shuffledOrder(list, seed) {
        var arr = list.slice();
        var rand = mulberry32(seed);
        for (var i = arr.length - 1; i > 0; i--) {
            var j = Math.floor(rand() * (i + 1));
            var tmp = arr[i];
            arr[i] = arr[j];
            arr[j] = tmp;
        }
        return arr;
    }

    function rangeArray(n) {
        var a = [];
        for (var i = 0; i < n; i++) {
            a.push(i);
        }
        return a;
    }

    // Sort comparator for the sorted orders; ties fall back to the URL so
    // the order is total and the same on every screen.
    function compareImages(a, b) {
        var ka = _sortKeys[a] || { name: a, time: 0 };
        var kb = _sortKeys[b] || { name: b, time: 0 };
        var c = 0;
        if (order === 1 || order === 2) {
            c = ka.name.localeCompare(kb.name);
            if (order === 2) {
                c = -c;
            }
        } else if (order === 3) {
            c = kb.time - ka.time;
        } else if (order === 4) {
            c = ka.time - kb.time;
        }
        return c !== 0 ? c : (a < b ? -1 : (a > b ? 1 : 0));
    }

    // Merges both sorted lists into one lap. A span image is one turn; a
    // single-image turn takes the next screenCount single images, one per
    // screen, so no screen repeats the picture its neighbour just had.
    function buildTurns() {
        var n = screenCount;
        var turns = [];
        var i = 0, j = 0;
        while (i < spanImages.length || j < singleImages.length) {
            if (j >= singleImages.length
                    || (i < spanImages.length && compareImages(spanImages[i], singleImages[j]) <= 0)) {
                turns.push({ span: spanImages[i] });
                i++;
            } else {
                turns.push({ single: j });
                j += n;
            }
        }
        return turns;
    }

    function pickCurrent() {
        var total = spanImages.length + singleImages.length;
        if (total === 0) {
            isSpanTurn = false;
            currentSpanImage = "";
            return;
        }
        if (order !== 0) {
            if (_turnsScreens !== screenCount) {
                _turns = buildTurns();
                _turnsScreens = screenCount;
            }
            var turn = _turns[tickCount % _turns.length];
            if (turn.span !== undefined) {
                isSpanTurn = true;
                currentSpanImage = turn.span;
            } else {
                singleStart = turn.single;
                isSpanTurn = false;
                currentSpanImage = "";
            }
            return;
        }
        var lap = Math.floor(tickCount / total);
        var pos = tickCount % total;

        if (lap !== _shuffledLap) {
            var shuffled = shuffledOrder(rangeArray(total), baseSeed + lap);
            // Avoid the first slot of a new lap repeating the last slot
            // of the previous lap.
            if (lap > 0 && _shuffledIndices.length > 0) {
                var prevLast = _shuffledIndices[_shuffledIndices.length - 1];
                if (shuffled[0] === prevLast && shuffled.length > 1) {
                    var t = shuffled[0];
                    shuffled[0] = shuffled[1];
                    shuffled[1] = t;
                }
            }
            _shuffledIndices = shuffled;
            _shuffledLap = lap;
        }

        var idx = _shuffledIndices[pos];
        if (idx < spanImages.length) {
            isSpanTurn = true;
            currentSpanImage = spanImages[idx];
        } else {
            isSpanTurn = false;
            currentSpanImage = "";
        }
    }

    // The newest settings seen from any screen, so every screen can run with
    // the same settings. Plasma stores wallpaper settings per screen, and
    // the settings dialog only edits the screen it was opened on. The
    // dialog stamps every edit with ConfigStamp (ms since the epoch); each
    // screen offers its settings here, and any screen holding older ones
    // copies these into its own config (see main.qml's syncConfig()).
    property real configStamp: 0
    property var sharedConfig: null

    function offerConfig(stamp, values) {
        if (sharedConfig === null || stamp > configStamp) {
            sharedConfig = values;
            configStamp = stamp;
        }
    }

    // Config signature of the scan that has been claimed (see claimScan),
    // when it was claimed, and the signature whose scan actually finished.
    property string scanClaim: ""
    property real scanClaimTime: 0
    property string scanCompleted: ""

    // How long a claim is honoured without having produced results.
    // Sibling instances all start within the same event-loop turn, so this
    // only has to outlast one actual folder walk.
    readonly property int scanClaimGrace: 30000

    // Every screen's wallpaper instance would otherwise run the same folder
    // scan over the same configured folders and write the result here,
    // where the last write wins - N screens paying N times the directory
    // I/O to produce one shared list. Instead the first instance to reach a
    // given signature (the config plus the tick, see main.qml's rescan())
    // claims the scan and is the only one that walks the folders; the
    // others skip it and pick the results up through ordinary bindings on
    // this singleton. A new tick or an edited config re-arms the claim, so
    // each triggers exactly one rescan.
    //
    // A claim is only useful while its owner is alive to finish it, and
    // Plasma destroys and rebuilds wallpaper items when displays are added
    // or removed - so the claiming instance can vanish mid-walk, taking its
    // FolderListModel with it. The claim outlives the item that took it, so
    // without a liveness rule nothing would ever rescan and every screen
    // would render nothing until a config edit or a shell restart. Hence
    // the grace window: a claim that hasn't reached configure() within it
    // is presumed dead and the next caller takes it over. Stealing from a
    // scan that was merely slow costs one redundant scan and nothing else -
    // each instance walks into its own FolderListModel and its own result
    // array, and both publish the same list - which is exactly the
    // behaviour this claim replaced.
    function claimScan(signature) {
        if (scanClaim === signature
                && (scanCompleted === signature
                    || Date.now() - scanClaimTime < scanClaimGrace)) {
            return false;
        }
        scanClaim = signature;
        scanClaimTime = Date.now();
        return true;
    }

    // Called by whichever screen instance claimed and ran the scan. Only
    // the claim holder gets here, so the claim this retires is the current
    // one. The lists arrive unsorted; sortKeys maps each URL to its file
    // name and modification time, for the sorted orders.
    function configure(spanList, singleList, interval, sortOrder, sortKeys) {
        // A shuffle is a permutation of the old total; reshuffle for the new one.
        if (spanList.length + singleList.length !== _shuffledIndices.length) {
            _shuffledIndices = [];
            _shuffledLap = -1;
        }
        order = sortOrder;
        _sortKeys = sortKeys;
        if (order === 0) {
            spanList.sort();
            singleList.sort();
        } else {
            spanList.sort(compareImages);
            singleList.sort(compareImages);
        }
        spanImages = spanList;
        singleImages = singleList;
        _turnsScreens = -1;
        slideInterval = interval;
        scanCompleted = scanClaim;
        pickCurrent();
    }

    function advance() {
        tickCount = tickCount + 1;
        pickCurrent();
    }

    // Like advance(), but keeps stepping through the existing shuffle
    // order until it lands on a span (ultrawide) image instead of
    // whatever's next - rather than picking an unrelated random span
    // image out of sequence. Bounded by "total" so an empty spanImages
    // list (nothing to land on) can't spin forever.
    function advanceToSpan() {
        var total = spanImages.length + singleImages.length;
        for (var i = 0; i < total; i++) {
            advance();
            if (isSpanTurn) {
                return;
            }
        }
    }

    // Mirrors advanceToSpan(), landing on the next non-ultrawide
    // ("single") image instead.
    function advanceToSingle() {
        var total = spanImages.length + singleImages.length;
        for (var i = 0; i < total; i++) {
            advance();
            if (!isSpanTurn) {
                return;
            }
        }
    }

    // QtObject has no default property to hold a bare child element, so
    // the Timer must be assigned to an explicit property instead.
    property Timer _timer: Timer {
        interval: Math.max(1, root.slideInterval) * 1000
        running: (root.spanImages.length + root.singleImages.length) > 0
        repeat: true
        onTriggered: root.advance()
    }
}
