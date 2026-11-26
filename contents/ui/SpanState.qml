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
import QtCore
import org.kde.plasma.plasma5support as P5Support
import "desk.js" as Desk
import "images.js" as Images
import "state.js" as State

QtObject {
    id: root

    // Randomized once per plasmashell startup, not a fixed constant: all
    // screens still share this single value (it's a QML singleton), so
    // cross-screen sync doesn't need it to be stable across restarts, and
    // leaving it fixed made every reboot replay the exact same shuffle
    // order starting from the same first image. Resuming (see "-- saved
    // state --" below) sets it to the saved seed instead, which continues
    // the old sequence rather than replaying it from the start.
    property int baseSeed: Date.now() % 2147483647

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

    // Random order: lap `lap`'s order of all the turns (indices into
    // spanImages, then singleImages). A new lap doesn't start with the
    // turn the previous lap ended on: then its first two slots are
    // swapped. That previous lap is worked out again rather than taken
    // from the cache, so every process gets the same order whatever laps
    // it has been through: a restored desktop, or the lock screen, starts
    // in the middle of a lap. With more than two turns the swap never
    // moves a lap's last slot; with two, it can, so the laps before are
    // gone through in turn (each a shuffle of two).
    function lapOrder(lap, total) {
        var range = rangeArray(total);
        function swapped(order, prevLast) {
            if (order.length > 1 && order[0] === prevLast) {
                var t = order[0];
                order[0] = order[1];
                order[1] = t;
            }
            return order;
        }
        if (lap === 0 || total < 2) {
            return shuffledOrder(range, baseSeed + lap);
        }
        var prev;
        if (_shuffledLap === lap - 1 && _shuffledIndices.length === total) {
            prev = _shuffledIndices;
        } else if (total > 2) {
            prev = shuffledOrder(range, baseSeed + lap - 1);
        } else {
            prev = shuffledOrder(range, baseSeed);
            for (var l = 1; l < lap; l++) {
                prev = swapped(shuffledOrder(range, baseSeed + l), prev[total - 1]);
            }
        }
        return swapped(shuffledOrder(range, baseSeed + lap), prev[total - 1]);
    }

    // The image is set before isSpanTurn: a screen's picture follows both,
    // and the other way round it would first load an empty spanned one.
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
                currentSpanImage = turn.span;
                isSpanTurn = true;
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
            var shuffled = lapOrder(lap, total);
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
            currentSpanImage = spanImages[idx];
            isSpanTurn = true;
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

    // While configure() is held back (see "-- saved state --"), the lists
    // aren't in yet: logged once the held call has run.
    property int _heldFolders: -1
    function logCounts(folders) {
        if (!stateRead) {
            _heldFolders = folders;
            return;
        }
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
            // The lock screen takes the desktop's settings from the file.
            _requestSave();
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
    //
    // `resume` is the Resume setting. Until the saved state has been read
    // (see "-- saved state --"), the call is held back and made again once
    // it has: otherwise the screens would first show a new image and then
    // the restored one.
    function configure(claim, spanList, singleList, interval, sortOrder, sortKeys, resume) {
        if (_claimSettings(claim) !== _claimSettings(scanClaim)) {
            return;
        }
        if (!stateRead) {
            _heldConfigure = [claim, spanList, singleList, interval, sortOrder, sortKeys, resume];
            return;
        }
        var oldInterval = slideInterval;
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
        slideInterval = interval >= 1 ? Math.min(Math.floor(interval), 86400) : 900;
        _resume = resume !== false;
        var oldCheck = _check;
        _check = State.listsCheck(order, spanList, singleList);
        if (_restoreDecided && slideInterval !== oldInterval) {
            _intervalChanged();
        }
        // The first lists with images decide whether the slideshow resumes.
        // Before the lists are published: the restore sets the seed and the
        // tick, and the timers' running bindings follow the lists.
        if (!_restoreDecided && spanList.length + singleList.length > 0) {
            _restoreDecided = true;
            if (_restore()) {
                // The tick just moved: mark it as scanned, so the screens
                // handling it don't scan the folders a second time.
                scanClaim = _claimSettings(scanClaim) + "|" + tickCount;
            }
        }
        spanImages = spanList;
        singleImages = singleList;
        _turnsScreens = -1;
        scanCompleted = scanClaim;
        pickCurrent();
        // The rescan at every tick usually finds the same images; the tick
        // itself has already been saved.
        if (_check !== oldCheck || slideInterval !== oldInterval) {
            _requestSave();
        }
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
    // picture just chosen a moment later. A restored image's own timer
    // ends too (once it stops, _timer starts with a full interval), or it
    // would skip the picture just chosen.
    function restartTimer() {
        if (_resumeTimer.running && !following) {
            _resumeTimer.stop();
        } else if (_timer.running) {
            _timer.restart();
        }
    }

    // QtObject has no default property to hold a bare child element, so
    // the Timer must be assigned to an explicit property instead.
    // Stopped while a restored image waits out the rest of its time
    // (_resumeTimer), and on the lock screen while it follows the desktop.
    property Timer _timer: Timer {
        interval: Math.max(1, root.slideInterval) * 1000
        running: (root.spanImages.length + root.singleImages.length) > 0
                 && !root._resumeTimer.running && !root.following
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

    // -- saved state: resuming, and the lock screen following the desktop --
    // plasmashell (the writer) saves its place in the slideshow to
    // state.json: the seed and the tick, which give every screen's image,
    // and how long the current image has been on screen. At the next start
    // it picks up from there. The lock screen (kscreenlocker_greet, another
    // process with its own settings and its own SpanState) only reads the
    // file, and shows and changes the images with the desktop (it
    // "follows"). Anything else, System Settings for example, does neither.
    // See "Resuming and the lock screen" in docs/how-it-works.md.
    readonly property string role: Qt.application.name === "plasmashell" ? "writer"
                                 : Qt.application.name === "kscreenlocker_greet" ? "follower" : ""
    readonly property string stateDir: decodeURIComponent(String(StandardPaths.writableLocation(StandardPaths.GenericStateLocation))
                                                          .replace(/^file:\/\//, "")) + "/com.github.vasilkalchev.multimonitorslideshow"
    readonly property string _readCommand: "cat -- " + State.shellQuote(stateDir + "/state.json")

    property bool _resume: true          // the Resume setting, from configure()
    property string _check: ""           // State.listsCheck() of the current lists
    property bool stateRead: role === ""  // the file has been read, or isn't needed
    property var _heldConfigure: null    // a configure() call waiting for the file
    property var _savedState: null       // the file as read at startup, or null
    property string _stateProblem: ""    // why it can't be used, for the journal
    property bool _restoreDecided: false // resumed, or decided not to
    property var _expectedImages: null   // the saved images, checked after a restore
    property int _expectedTick: -1
    property bool _saveQueued: false
    property bool _saveFailed: false

    // The lock screen is following the desktop's file.
    property bool following: false

    // Lock screen only. The FollowDesktop setting, from main.qml, and the
    // desktop's settings from the file while it is on: main.qml then uses
    // these instead of the lock screen's own (folders, order, interval,
    // how images are drawn), so the lock screen shows exactly the
    // desktop's slideshow. null: use the lock screen's own settings (it
    // doesn't follow, or the desktop has saved no settings).
    property bool followWanted: false
    property var followSettings: null
    function setFollowWanted(wanted) {
        followWanted = wanted;
        _updateFollowSettings(_savedState);
    }
    function _updateFollowSettings(state) {
        var settings = role === "follower" && followWanted && state !== null ? state.settings : null;
        if (JSON.stringify(settings) !== JSON.stringify(followSettings)) {
            followSettings = settings;
        }
    }

    // Seconds the current image has been on screen, across sessions. Counted
    // by _heartbeat, a Timer: Qt timers stop while the machine is suspended,
    // like the slideshow's own, so suspend doesn't count.
    property real shown: 0
    readonly property int _beatSeconds: Math.max(1, Math.min(60, slideInterval))

    // Every screen's image, as the screens report it (reportImage()), keyed
    // by a number each screen gets from newReporter(), not by its name: a
    // screen's name can be another screen's for a moment while the item is
    // being made, and a screen must not remove an entry that is another's.
    property var _reports: ({})
    property int _nextReporter: 0
    property string _imagesText: "{}"

    function newReporter() {
        _nextReporter = _nextReporter + 1;
        return _nextReporter;
    }

    // name or url "" removes the screen's entry.
    function reportImage(id, name, url) {
        var reports = {};
        for (var k in _reports) {
            if (k !== String(id)) {
                reports[k] = _reports[k];
            }
        }
        if (name !== "" && url !== "") {
            reports[id] = { name: name, url: url };
        }
        _reports = reports;
        var text = JSON.stringify(_imagesMap());
        if (text !== _imagesText) {
            _imagesText = text;
            _requestSave();
        }
    }

    // Connector name -> image, sorted by name so the same images give the
    // same text.
    function _imagesMap() {
        var byName = {};
        for (var k in _reports) {
            byName[_reports[k].name] = _reports[k].url;
        }
        var map = {};
        var names = Object.keys(byName).sort();
        for (var i = 0; i < names.length; i++) {
            map[names[i]] = byName[names[i]];
        }
        return map;
    }

    property P5Support.DataSource _shell: P5Support.DataSource {
        engine: "executable"
        // A source that is still connected isn't run again: let go of
        // every one, or the lock screen's file would be read only once.
        onNewData: (source, data) => {
            disconnectSource(source);
            if (source === root._readCommand) {
                root._stateText(data["exit code"] === 0 ? data["stdout"] : null);
            } else if (data["exit code"] !== 0 && !root._saveFailed) {
                root._saveFailed = true;
                console.warn(root.logPrefix + "can't save the slideshow's place in " + root.stateDir + ": "
                             + String(data["stderr"]).trim());
            }
        }
    }

    function _readState() {
        _shell.connectSource(_readCommand);
    }

    function _stateText(text) {
        var state = text === null ? null : State.parse(text);
        if (!stateRead) {
            _savedState = state;
            _stateProblem = text === null ? "nothing saved yet" : (state === null ? "the saved state can't be used" : "");
            _updateFollowSettings(state);
            _finishRead();
        } else if (role === "follower" && followWanted) {
            _follow(state);
        }
    }

    function _finishRead() {
        stateRead = true;
        var held = _heldConfigure;
        _heldConfigure = null;
        if (held !== null) {
            configure(held[0], held[1], held[2], held[3], held[4], held[5], held[6]);
        }
        if (_heldFolders >= 0) {
            logCounts(_heldFolders);
            _heldFolders = -1;
        }
    }

    // A file that can't be read in time mustn't keep the screens empty.
    property Timer _readTimeout: Timer {
        interval: 3000
        running: !root.stateRead
        onTriggered: {
            root._stateProblem = "the saved state took too long to read";
            root._finishRead();
        }
    }

    // Called once, by the first configure() with images, after the lists
    // are sorted and before they are published. Returns whether it resumed.
    function _restore() {
        if (role === "") {
            return false;
        }
        var s = _savedState;
        var why = !_resume ? (role === "follower" ? "Show the desktop's slideshow is off" : "Resume where it left off is off")
                : _stateProblem !== "" ? _stateProblem
                : s.order !== order ? "the order has changed"
                : s.check !== _check ? "the images have changed" : "";
        if (why !== "") {
            console.info(logPrefix + (role === "follower" ? "lock screen: not following the desktop, "
                                                          : "starting a new slideshow, ") + why);
            return false;
        }
        var left = _adopt(s);
        if (role === "follower") {
            following = true;
            console.info(logPrefix + "lock screen: following the desktop");
        } else if (left > 0) {
            console.info(logPrefix + "resumed where it left off: " + Math.round(s.shown) + " of " + slideInterval
                         + " s shown, " + Math.round(left) + " s left");
        } else {
            console.info(logPrefix + "resumed where it left off: the image had been shown for its whole time, "
                         + "going on to the next one");
        }
        if (left > 0) {
            _expectedImages = s.images;
            _expectedTick = tickCount;
            _verifyTimer.restart();
        }
        return true;
    }

    // Takes over a saved position: the seed, the tick, and the time left.
    // An image whose time is up goes one further (not one for every
    // interval that went by), straight to that tick: restoring the tick
    // and then advancing would load the restored image first. Returns the
    // seconds that were left.
    function _adopt(s) {
        var follower = role === "follower";
        var left = State.remaining(slideInterval, s.shown, s.written, Date.now(), follower, State.beatOf(s.interval));
        var tick = left > 0 ? s.tick : s.tick + 1;
        if (s.seed !== baseSeed) {
            baseSeed = s.seed;
            _shuffledIndices = [];
            _shuffledLap = -1;
        }
        if (tick !== tickCount) {
            tickCount = tick; // resets `shown` (onTickCountChanged)
        }
        shown = left > 0 ? s.shown : 0;
        if (follower || left > 0) {
            _resumeTimer.interval = Math.max(1000, Math.round((left > 0 ? left : slideInterval) * 1000));
            _resumeTimer.restart();
        }
        return left;
    }

    // The lock screen, at every read: the desktop may have gone on (its
    // timer, or a Next), and the time left is worked out again. A file
    // that doesn't fit (the desktop has just found another image, say)
    // keeps the images as they are until a later read fits again.
    //
    // The desktop's settings are taken over at every read as well. A lock
    // screen that couldn't follow at first (the desktop's lists had just
    // changed, say) starts following once a read fits.
    function _follow(s) {
        _updateFollowSettings(s);
        if (s === null || s.order !== order || s.check !== _check) {
            return;
        }
        if (!following) {
            following = true;
            console.info(logPrefix + "lock screen: following the desktop");
        }
        var tick = tickCount, seed = baseSeed;
        _adopt(s);
        if (tickCount !== tick || baseSeed !== seed) {
            pickCurrent();
        }
    }

    // A restored image waits out the rest of its time; then _timer takes
    // over. On the lock screen it times every change, and every read sets
    // it again from the desktop's file.
    property Timer _resumeTimer: Timer {
        repeat: false
        onTriggered: {
            root.advance();
            if (root.following) {
                interval = Math.max(1, root.slideInterval) * 1000;
                restart();
            }
        }
    }

    property Timer _followTimer: Timer {
        interval: 10000
        repeat: true
        running: root.following || root.followSettings !== null
        onTriggered: root._readState()
    }

    // The images the screens show after a restore should be the saved
    // ones. If they aren't, the sequence isn't worked out the same way as
    // before (a bug): say so. Checked a moment later, once every screen
    // has its name and its image.
    property Timer _verifyTimer: Timer {
        interval: 5000
        onTriggered: root._verify()
    }
    function _verify() {
        var expected = _expectedImages;
        _expectedImages = null;
        if (expected === null || tickCount !== _expectedTick) {
            return;
        }
        var now = _imagesMap();
        var diffs = [];
        for (var name in expected) {
            if (now[name] !== undefined && now[name] !== expected[name]) {
                diffs.push(name + " shows " + now[name] + " instead of " + expected[name]);
            }
        }
        if (diffs.length > 0) {
            console.warn(logPrefix + "the restored images differ from the saved ones: " + diffs.join("; "));
        }
    }

    // plasmashell only. Merged: Next Spanned can step through hundreds of
    // ticks in one click, and a burst of image reports comes with every
    // display change; each gives one write. Nothing is written before the
    // restore is decided, or the state saved last time would be lost
    // (_emptyRetry ticks while a drive with the folders isn't mounted yet),
    // nor while there are no images.
    function _requestSave() {
        if (role !== "writer" || _saveQueued) {
            return;
        }
        _saveQueued = true;
        Qt.callLater(function () {
            root._saveQueued = false;
            root._save();
        });
    }
    function _save() {
        if (role !== "writer" || !_restoreDecided || spanImages.length + singleImages.length === 0) {
            return;
        }
        var text = State.serialize({
            written: Date.now(),
            order: order,
            interval: slideInterval,
            seed: baseSeed,
            tick: tickCount,
            shown: Math.floor(shown),
            check: _check,
            count: spanImages.length + singleImages.length,
            span: isSpanTurn,
            images: _imagesMap(),
            settings: State.settingsOf(sharedConfig)
        });
        _shell.connectSource(State.saveCommand(stateDir, text));
    }

    property Timer _heartbeat: Timer {
        interval: root._beatSeconds * 1000
        repeat: true
        running: root.role === "writer" && root._restoreDecided
                 && (root.spanImages.length + root.singleImages.length) > 0
        onTriggered: {
            root.shown = root.shown + root._beatSeconds;
            root._requestSave();
        }
    }

    // A new image starts with no screen time.
    onTickCountChanged: {
        if (role === "writer" && _restoreDecided) {
            shown = 0;
            if (_heartbeat.running) {
                _heartbeat.restart();
            }
            _requestSave();
        }
    }

    // _timer starts over with the new interval, and so does the image's
    // time; a restored image's own timer ends.
    function _intervalChanged() {
        if (following) {
            return;
        }
        shown = 0;
        if (_resumeTimer.running) {
            _resumeTimer.stop();
        }
        if (_heartbeat.running) {
            _heartbeat.restart();
        }
        _requestSave();
    }

    Component.onCompleted: {
        if (role === "writer") {
            console.info(logPrefix + "saves its place in the slideshow in " + stateDir);
        } else if (role === "follower") {
            console.info(logPrefix + "lock screen: reads the desktop's place in the slideshow from " + stateDir);
        }
        if (role !== "") {
            _readState();
        }
    }
}
