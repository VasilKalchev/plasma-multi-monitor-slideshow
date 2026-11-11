/*
    A dense thumbnail grid of the images in one folder, for config.qml.
    Lists the same files the wallpaper uses (flat, same name filters), in
    the order the settings pick. Double-click opens an image.

    Thumbnails come from this plugin's own cache, else from the
    freedesktop thumbnail cache when Dolphin or a file dialog has made
    one. An image in neither is decoded once at thumbnail size, drawn,
    grabbed with grabToImage() and saved to the plugin's cache as a small
    JPEG. QML can't write freedesktop thumbnails (they need PNG metadata)
    or create directories, so the cache directory is made with `mkdir -p`
    through the "executable" data engine.
*/
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import QtQml.Models
import QtCore
import Qt.labs.folderlistmodel
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as P5Support
import "desk.js" as Desk
import "images.js" as Images

ColumnLayout {
    id: root

    property string folder: ""
    property bool isSpan: false
    // SlideshowOrder. Random shows the images shuffled: a new shuffle for
    // each folder and each change to it, not the slideshow's own sequence.
    property int order: 0
    // Unticked folders are dimmed.
    property bool folderEnabled: true

    // Null for a folder that doesn't exist: FolderListModel then lists the
    // process's working directory (the home folder) instead.
    readonly property var files: folderModels.object && String(folderModels.object.folder) === String(folderModels.object.wanted)
                                 ? folderModels.object : null

    // The rows of `files` in the order the grid shows them: shuffled for
    // Random, else sorted like the slideshow (compare() in images.js).
    // FolderListModel's own sorting puts upper-case names first, so it
    // isn't used. The grid can't reorder a FolderListModel, so it shows
    // this list instead and reads each cell's file from `files`; any
    // change to `files` rebuilds it.
    property int filesRevision: 0
    Connections {
        target: root.files
        function onRowsInserted() { root.filesRevision++; }
        function onRowsRemoved() { root.filesRevision++; }
        function onModelReset() { root.filesRevision++; }
    }
    readonly property var rows: {
        root.filesRevision;
        const files = root.files;
        const count = files ? files.count : 0;
        const list = [];
        for (let i = 0; i < count; i++) {
            list.push(i);
        }
        if (root.order === 0) {
            for (let i = count - 1; i > 0; i--) {
                const j = Math.floor(Math.random() * (i + 1));
                const swap = list[i];
                list[i] = list[j];
                list[j] = swap;
            }
        } else {
            const keys = list.map(i => {
                const modified = files.get(i, "fileModified");
                return {
                    name: String(files.get(i, "fileName")).toLowerCase(),
                    time: modified instanceof Date ? modified.getTime() : 0,
                    url: String(files.get(i, "fileUrl"))
                };
            });
            list.sort((a, b) => Images.compare(root.order, keys[a], keys[b]));
        }
        return list;
    }

    // Thumbnail shape: spanned folders take the shape of the whole row of
    // screens, individual folders the shape of this screen.
    readonly property real thumbAspect: {
        if (!root.isSpan) {
            return Screen.height > 0 ? Screen.width / Screen.height : 16 / 9;
        }
        // Mirrored screens are one place in the row (see desk.js).
        var row = Desk.layout(Qt.application.screens, false, {}).list;
        var w = 0, h = 0;
        for (var i = 0; i < row.length; i++) {
            w += row[i].w;
            h = Math.max(h, row[i].h);
        }
        return h > 0 ? w / h : 32 / 9;
    }

    readonly property string cacheDir: StandardPaths.writableLocation(StandardPaths.GenericCacheLocation)
    readonly property string sharedThumbnails: cacheDir + "/thumbnails"
    readonly property string ownThumbnails: cacheDir + "/com.github.vasilkalchev.multimonitorslideshow/thumbnails"
    readonly property var ownSizes: [256, 512, 1024]

    // Pixels a thumbnail covers, and the cache sizes that fit it. A cached
    // thumbnail slightly smaller than the cell (down to 80%) is still used.
    readonly property real thumbPx: Math.max(grid.cellWidth, grid.cellHeight) * Screen.devicePixelRatio
    readonly property int ownSize: {
        for (var i = 0; i < ownSizes.length; i++) {
            if (ownSizes[i] >= thumbPx * 0.8) {
                return ownSizes[i];
            }
        }
        return ownSizes[ownSizes.length - 1];
    }
    readonly property string sharedSize: {
        var sizes = [["normal", 128], ["large", 256], ["x-large", 512], ["xx-large", 1024]];
        for (var i = 0; i < sizes.length; i++) {
            if (sizes[i][1] >= thumbPx * 0.8) {
                return sizes[i][0];
            }
        }
        return "";
    }

    // The own cache's directories exist (ownCacheReady), or can't be made
    // (ownCacheFailed: thumbnails are then shown but not saved).
    property bool ownCacheReady: false
    property bool ownCacheFailed: false
    // File names in the own cache's current size directory, so a hit
    // there skips the freedesktop lookup, whose every miss logs a warning.
    property var ownIndex: ({})
    property string ownIndexDir: ""
    readonly property bool thumbsReady: ownCacheFailed
        || (ownCacheReady && ownIndexDir === ownThumbnails + "/" + ownSize)

    function localPath(fileUrl) {
        var path = String(fileUrl).replace(/^file:\/\//, "");
        try {
            return decodeURIComponent(path);
        } catch (e) {
            return path;
        }
    }

    function shellQuote(text) {
        return "'" + text.replace(/'/g, "'\\''") + "'";
    }

    P5Support.DataSource {
        id: shell
        engine: "executable"
        onNewData: (source, data) => {
            disconnectSource(source);
            if (data["exit code"] === 0) {
                root.ownCacheReady = true;
            } else {
                root.ownCacheFailed = true;
            }
        }
    }

    // Makes the cache directories and prunes the cache: a thumbnail not
    // read for 60 days (its image deleted, edited, or just not looked at)
    // is removed. Reading a file updates its access time at most daily
    // (relatime), which is plenty for this. On a file system mounted
    // noatime it never does, and thumbnails still in use would be deleted
    // 60 days after they were made, so there they go a year after they
    // were made instead.
    Component.onCompleted: {
        var dirs = root.ownSizes.map(function (size) {
            return root.shellQuote(root.localPath(root.ownThumbnails + "/" + size));
        });
        var cache = root.shellQuote(root.localPath(root.ownThumbnails));
        shell.connectSource("mkdir -p " + dirs.join(" ")
            + " && { if findmnt -no OPTIONS -T " + cache + " 2>/dev/null | grep -qw noatime;"
            + " then age='-mtime +365'; else age='-atime +60'; fi;"
            + " find " + cache + " -type f -name '*.jpg' $age -delete; true; }");
    }

    // Without the executable engine nothing would ever answer.
    Timer {
        interval: 5000
        running: !root.ownCacheReady && !root.ownCacheFailed
        onTriggered: root.ownCacheFailed = true
    }

    Instantiator {
        model: root.ownCacheReady ? [root.ownThumbnails + "/" + root.ownSize] : []
        delegate: FolderListModel {
            required property string modelData
            folder: modelData
            showDirs: false
            nameFilters: ["*.jpg"]

            function report() {
                if (status !== FolderListModel.Ready) {
                    return;
                }
                var names = {};
                for (var i = 0; i < count; i++) {
                    names[get(i, "fileName")] = true;
                }
                root.ownIndex = names;
                root.ownIndexDir = modelData;
            }
            onStatusChanged: report()
            Component.onCompleted: report()
        }
    }

    // Where an image's thumbnail comes from: this plugin's cache (keyed by
    // the URI and modification time, so an edited image gets a new
    // thumbnail) if it's there, else the freedesktop cache that Dolphin
    // and the file dialogs fill (keyed by the MD5 of the file's encoded
    // URI). `save` is where a thumbnail made from the image itself goes.
    function thumbnailPlan(fileUrl, modified) {
        var uri = String(fileUrl);
        try {
            uri = encodeURI(decodeURIComponent(uri)).replace(/\?/g, "%3F").replace(/#/g, "%23");
        } catch (e) {
        }
        var mtime = modified instanceof Date ? modified.getTime() : 0;
        var name = Qt.md5(uri + "|" + mtime) + ".jpg";
        var own = root.ownThumbnails + "/" + root.ownSize + "/" + name;
        var sources = [];
        if (root.ownIndex[name] === true && root.ownIndexDir === root.ownThumbnails + "/" + root.ownSize) {
            sources.push(own);
        } else if (root.sharedSize !== "") {
            sources.push(root.sharedThumbnails + "/" + root.sharedSize + "/" + Qt.md5(uri) + ".png");
        }
        return { sources: sources, save: root.localPath(own), name: name, size: root.ownSize };
    }

    // A thumbnail saved just now is in the cache too: the listing above was
    // made when the page opened, and a cell built again (after scrolling
    // away, or a change of order) would decode the image once more. Nothing
    // is bound to ownIndex, so it is added to in place.
    function ownThumbnailSaved(size, name) {
        if (root.ownIndexDir === root.ownThumbnails + "/" + size) {
            root.ownIndex[name] = true;
        }
    }

    spacing: 0

    // A fresh model per folder, with `folder` fixed at construction:
    // reassigning `folder` on a live FolderListModel can deliver the old
    // folder's rows (see "FolderListModel" in AGENTS.md).
    Instantiator {
        id: folderModels
        model: root.folder !== "" ? [root.folder] : []
        delegate: FolderListModel {
            required property string modelData
            readonly property url wanted: modelData
            folder: modelData
            showDirs: false
            showFiles: true
            caseSensitive: false
            nameFilters: Images.nameFilters
        }
    }

    Kirigami.InlineViewHeader {
        Layout.fillWidth: true
        text: {
            if (root.folder === "") {
                return i18nd("plasma_wallpaper_com.github.vasilkalchev.multimonitorslideshow", "Images");
            }
            const name = root.folder.replace(/\/+$/, "").split("/").pop();
            const count = root.files ? root.files.count : 0;
            return i18ndp("plasma_wallpaper_com.github.vasilkalchev.multimonitorslideshow", "%2: %1 image", "%2: %1 images", count, decodeURIComponent(name));
        }
    }

    Rectangle {
        Layout.fillWidth: true
        Layout.fillHeight: true

        Kirigami.Theme.inherit: false
        Kirigami.Theme.colorSet: Kirigami.Theme.View
        color: Kirigami.Theme.backgroundColor

        QQC2.ScrollView {
            anchors.fill: parent

            GridView {
                id: grid

                readonly property real targetHeight: Kirigami.Units.gridUnit * 4
                readonly property int columns: Math.max(1, Math.round(width / (targetHeight * root.thumbAspect)))

                // Thumbnails are started here, a couple at a time: visible
                // cells first, each group in reading order. Qt decodes
                // asynchronous images on one thread and takes the newest
                // request first, so letting every cell request at once
                // filled the grid from the bottom (and from below the view).
                property int loading: 0
                readonly property int maxLoading: 2

                function pump() {
                    if (loading >= maxLoading || !root.thumbsReady) {
                        return;
                    }
                    var waiting = [];
                    var kids = contentItem.children;
                    for (var i = 0; i < kids.length; i++) {
                        if (kids[i].thumbState === 0) {
                            waiting.push(kids[i]);
                        }
                    }
                    var top = contentY, bottom = contentY + height;
                    function outside(c) {
                        return (c.y + c.height > top && c.y < bottom) ? 0 : 1;
                    }
                    waiting.sort(function (a, b) {
                        return (outside(a) - outside(b)) || (a.index - b.index);
                    });
                    for (var k = 0; k < waiting.length && loading < maxLoading; k++) {
                        loading++;
                        waiting[k].start();
                    }
                }
                function schedule() {
                    Qt.callLater(pump);
                }
                onContentYChanged: schedule()
                Connections {
                    target: root
                    function onThumbsReadyChanged() {
                        grid.schedule();
                    }
                }

                clip: true
                opacity: root.folderEnabled ? 1 : 0.5
                model: root.rows
                cellWidth: Math.floor(width / columns)
                cellHeight: Math.round(cellWidth / root.thumbAspect)

                delegate: Item {
                    id: cell

                    required property int index
                    // The file's row in root.files.
                    required property int modelData
                    readonly property url fileUrl: root.files ? root.files.get(modelData, "fileUrl") : ""
                    readonly property string fileName: root.files ? root.files.get(modelData, "fileName") : ""
                    readonly property var fileModified: root.files ? root.files.get(modelData, "fileModified") : undefined

                    // 0 = waiting for grid.pump(), 1 = loading, 2 = done
                    property int thumbState: 0
                    property var sources: []
                    property string savePath: ""
                    property string saveName: ""
                    property int makeSize: 0
                    property bool made: false
                    // Showing a grabToImage() result, which takes no sourceSize.
                    property bool grabbed: false

                    function start() {
                        thumbState = 1;
                        var plan = root.thumbnailPlan(fileUrl, fileModified);
                        sources = plan.sources;
                        savePath = plan.save;
                        saveName = plan.name;
                        makeSize = plan.size;
                        next();
                    }
                    // Tries the next cached thumbnail; when none is left,
                    // makes one from the image itself.
                    function next() {
                        if (sources.length === 0) {
                            if (made) {
                                finish();
                            } else {
                                made = true;
                                maker.source = fileUrl;
                            }
                            return;
                        }
                        var rest = sources.slice();
                        thumb.source = rest.shift();
                        sources = rest;
                    }
                    // Shows and caches the thumbnail `maker` just decoded.
                    // If the grab can't run, shows the image directly.
                    function grabMade() {
                        var ok = maker.grabToImage(function (result) {
                            if (root.ownCacheReady && result.saveToFile(cell.savePath)) {
                                root.ownThumbnailSaved(cell.makeSize, cell.saveName);
                            }
                            maker.source = "";
                            cell.grabbed = true;
                            thumb.source = result.url;
                        }, Qt.size(maker.implicitWidth, maker.implicitHeight));
                        if (!ok) {
                            maker.source = "";
                            thumb.source = fileUrl;
                        }
                    }
                    function finish() {
                        thumbState = 2;
                        grid.loading--;
                        grid.schedule();
                    }

                    width: grid.cellWidth
                    height: grid.cellHeight

                    Component.onCompleted: grid.schedule()
                    Component.onDestruction: {
                        if (thumbState === 1) {
                            grid.loading--;
                            grid.schedule();
                        }
                    }

                    // Decodes the image to thumbnail size for grabMade(). It has
                    // to be drawn for grabToImage() to work, so it sits in a
                    // 1x1 clip under the visible thumbnail.
                    Item {
                        width: 1
                        height: 1
                        clip: true

                        Image {
                            id: maker
                            width: implicitWidth
                            height: implicitHeight
                            asynchronous: true
                            cache: false
                            // Both dimensions set: scaled to fit inside, keeping
                            // its shape.
                            sourceSize: Qt.size(cell.makeSize, cell.makeSize)
                            onStatusChanged: {
                                if (status === Image.Ready) {
                                    cell.grabMade();
                                } else if (status === Image.Error) {
                                    source = "";
                                    cell.finish();
                                }
                            }
                        }
                    }

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 1
                        color: Kirigami.Theme.alternateBackgroundColor
                        border.width: hover.hovered ? 2 : 0
                        border.color: Kirigami.Theme.highlightColor

                        Image {
                            id: thumb
                            anchors.fill: parent
                            clip: true
                            anchors.margins: parent.border.width
                            asynchronous: true
                            fillMode: Image.PreserveAspectCrop
                            // With PreserveAspectCrop the decode covers this
                            // size, so a JPEG original is scaled while decoding.
                            sourceSize: cell.grabbed ? undefined
                                : Qt.size(Math.ceil(cell.width * Screen.devicePixelRatio),
                                          Math.ceil(cell.height * Screen.devicePixelRatio))
                            onStatusChanged: {
                                if (cell.thumbState !== 1) {
                                    return;
                                }
                                if (status === Image.Ready) {
                                    cell.finish();
                                } else if (status === Image.Error) {
                                    cell.next();
                                }
                            }
                        }
                    }

                    HoverHandler {
                        id: hover
                    }
                    TapHandler {
                        onDoubleTapped: Qt.openUrlExternally(cell.fileUrl)
                    }
                    QQC2.ToolTip.visible: hover.hovered
                    QQC2.ToolTip.text: cell.fileName
                    QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                }

                Kirigami.PlaceholderMessage {
                    anchors.centerIn: parent
                    width: parent.width - Kirigami.Units.largeSpacing * 4
                    visible: grid.count === 0
                    text: root.folder === ""
                        ? i18nd("plasma_wallpaper_com.github.vasilkalchev.multimonitorslideshow", "Select a folder to see its images")
                        : i18nd("plasma_wallpaper_com.github.vasilkalchev.multimonitorslideshow", "There are no images in this folder")
                }
            }
        }
    }
}
