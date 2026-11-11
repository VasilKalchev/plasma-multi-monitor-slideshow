/*
    Shared state for every screen's Multi-monitor Slideshow wallpaper instance.

    Plasma's wallpaper views for a single corona all run in one QML
    engine, so a QML singleton is visible to every screen at once. That
    means we don't need clock-derived math or polling to keep screens in
    sync: the one Timer here advances tickCount, and every screen
    instance reacts to that change immediately via ordinary property
    bindings, with zero IPC.
*/
pragma Singleton
import QtQuick
import "desk.js" as Desk
import "images.js" as Images

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
    // below), and on Next. Every screen picks its picture from it, so
    // they all change at the same moment.
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

    // Random order only: how many single-image turns there have been
    // before this one, counted from tick 0. Each screen's walk through its
    // own shuffle of the single images goes by this, not by tickCount, so
    // the spanned turns in between don't make it skip images.
    property int singleTurn: 0

    property var _shuffledIndices: []
    property int _shuffledLap: -1
    // _singlesBefore[pos]: the single-image turns in this lap before pos.
    property var _singlesBefore: []

    // Sorted orders only: one lap of turns, each { span: url } or
    // { single: index into singleImages }, built for _turnsScreens screens.
    property var _turns: []
    property int _turnsScreens: -1
    property var _sortKeys: ({})     // url -> { name: lowercase file name, time: ms, url }

    // Screens at distinct positions; mirrored screens show the same image.
    readonly property int screenCount: Math.max(1, Desk.screenCount(Qt.application.screens))

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

    // Sort comparator for the sorted orders (see images.js).
    function compareImages(a, b) {
        return Images.compare(order, _sortKeys[a] || { name: a, time: 0, url: a },
                              _sortKeys[b] || { name: b, time: 0, url: b });
    }

    // When the file was last modified, in ms; 0 if it isn't in the lists.
    function modifiedTime(url) {
        var key = _sortKeys[url];
        return key !== undefined ? key.time : 0;
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
            var before = [];
            var singles = 0;
            for (var s = 0; s < shuffled.length; s++) {
                before.push(singles);
                if (shuffled[s] >= spanImages.length) {
                    singles++;
                }
            }
            _shuffledIndices = shuffled;
            _singlesBefore = before;
            _shuffledLap = lap;
        }
        // Every lap has one turn per single image.
        singleTurn = lap * singleImages.length + _singlesBefore[pos];

        var idx = _shuffledIndices[pos];
        if (idx < spanImages.length) {
            isSpanTurn = true;
            currentSpanImage = spanImages[idx];
        } else {
            isSpanTurn = false;
            currentSpanImage = "";
        }
    }

    // -- the journal --
    // What a black or stuck desktop needs to be explained from
    // `journalctl --user -u plasma-plasmashell.service`. Every screen runs
    // the same code, so the lines that would repeat are kept here and
    // written once, when what they say changes.
    readonly property string logPrefix: "Multi-monitor Slideshow: "
    property string _loggedCounts: ""
    property string _loggedDesk: ""
    property var _missingFolders: ({})

    function logCounts(folders) {
        var text = spanImages.length + " spanned and " + singleImages.length + " individual images in "
                 + folders + (folders === 1 ? " folder" : " folders");
        if (text !== _loggedCounts) {
            _loggedCounts = text;
            console.info(logPrefix + text);
        }
    }

    // A folder that can't be listed (see the Instantiator in main.qml).
    function logFolder(folder, missing) {
        if (missing && _missingFolders[folder] !== true) {
            _missingFolders[folder] = true;
            console.warn(logPrefix + "folder not found, skipped: " + folder);
        } else if (!missing && _missingFolders[folder] === true) {
            _missingFolders[folder] = false;
            console.info(logPrefix + "folder is back: " + folder);
        }
    }

    // The desk the spanned images are laid out on (see desk.js).
    function logDesk(desk) {
        var parts = [];
        for (var i = 0; i < desk.list.length; i++) {
            var d = desk.list[i];
            parts.push(d.names.join("=") + " " + d.w + "x" + d.h + " at " + d.x + "," + d.y
                       + " -> on the desk at " + Math.round(d.dx) + "," + Math.round(d.dy)
                       + ", scale " + d.f.toFixed(4) + (d === desk.ref ? ", reference" : ""));
        }
        var text = parts.join("; ") + (desk.usePhys ? "" : " (in pixels, not physical sizes)");
        if (text !== _loggedDesk) {
            _loggedDesk = text;
            console.info(logPrefix + "monitors: " + text);
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
        if (scanClaim === signature) {
            console.info(logPrefix + "a folder scan didn't finish in " + scanClaimGrace / 1000 + " s, scanning again");
        }
        scanClaim = signature;
        scanClaimTime = Date.now();
        return true;
    }

    // Called by a screen instance that claimed and ran a scan. The lists
    // arrive unsorted; sortKeys maps each URL to its file name and
    // modification time, for the sorted orders.
    //
    // `claim` is the signature the scan was claimed with. If the current
    // claim is for other settings, the scan is dropped: it was started by
    // a screen whose settings were older (at startup, before the screens
    // have shared theirs), and its lists would replace the newer scan's,
    // or be taken for it. A scan of the same settings claimed at an
    // earlier tick is as good as the current one, and is used: a scan
    // slower than the interval would otherwise never be.
    function _claimSettings(claim) {
        return claim.slice(0, claim.lastIndexOf("|"));
    }
    function configure(claim, spanList, singleList, interval, sortOrder, sortKeys) {
        if (_claimSettings(claim) !== _claimSettings(scanClaim)) {
            return;
        }
        // A shuffle is a permutation of the old total, and which of its
        // slots are spanned turns goes by the old split; reshuffle for new ones.
        if (spanList.length + singleList.length !== _shuffledIndices.length
                || spanList.length !== spanImages.length) {
            _shuffledIndices = [];
            _shuffledLap = -1;
        }
        // Values the settings page can't produce (a config file edited by
        // hand): an unknown order is Random, as the page shows it, and an
        // interval that isn't a positive number is the default. Intervals
        // under a minute are kept; the page shows them as 1 minute.
        order = sortOrder >= 1 && sortOrder <= 4 ? Math.floor(sortOrder) : 0;
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
        slideInterval = interval >= 1 ? Math.min(Math.floor(interval), 86400) : 900;
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
    // image out of sequence. Bounded by two laps: in Random order the
    // next lap is reshuffled, so the next span image can be up to
    // 2 * total - 1 steps away (the rest of this lap, then all of the
    // next one).
    function advanceToSpan() {
        if (spanImages.length === 0) {
            return;
        }
        var total = spanImages.length + singleImages.length;
        for (var i = 0; i < 2 * total; i++) {
            advance();
            if (isSpanTurn) {
                return;
            }
        }
    }

    // Mirrors advanceToSpan(), landing on the next non-ultrawide
    // ("single") image instead.
    function advanceToSingle() {
        if (singleImages.length === 0) {
            return;
        }
        var total = spanImages.length + singleImages.length;
        for (var i = 0; i < 2 * total; i++) {
            advance();
            if (!isSpanTurn) {
                return;
            }
        }
    }

    // After a Next from the menu the next automatic change waits a whole
    // interval, as in the built-in Slideshow, instead of following the
    // picture just chosen a moment later.
    function restartTimer() {
        if (_timer.running) {
            _timer.restart();
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

    // The timer above stops while there are no images, and folders are
    // only scanned on a tick, so with empty lists nothing would ever look
    // again: not when a drive with the folders is mounted after login, nor
    // when the claiming screen was destroyed before its first scan
    // finished (see claimScan()). While a scan has been claimed and the
    // lists are empty, tick every scanClaimGrace so the screens rescan.
    property Timer _emptyRetry: Timer {
        interval: root.scanClaimGrace
        running: root.scanClaim !== ""
                 && (root.spanImages.length + root.singleImages.length) === 0
        repeat: true
        onTriggered: root.advance()
    }
}
