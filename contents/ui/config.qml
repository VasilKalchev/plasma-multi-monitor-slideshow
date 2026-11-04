/*
    Settings UI for the Multi-monitor Slideshow wallpaper plugin.
*/
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "desk.js" as Desk

ColumnLayout {
    id: root

    // Set by Plasma when it loads the page; unused here.
    property var configDialog
    property var wallpaperConfiguration

    property list<string> cfg_SpanPaths: []
    property list<string> cfg_SpanPathsDefault: []
    property list<string> cfg_SinglePaths: []
    property list<string> cfg_SinglePathsDefault: []
    property list<string> cfg_DisabledPaths: []
    property list<string> cfg_DisabledPathsDefault: []
    property int cfg_SlideInterval: 900
    property int cfg_SlideIntervalDefault: 900

    property int cfg_SlideshowOrder: 0
    property int cfg_SlideshowOrderDefault: 0

    property int cfg_SpanFit: 0
    property int cfg_SpanFitDefault: 0

    property bool cfg_MatchPhysicalSize: true
    property bool cfg_MatchPhysicalSizeDefault: true
    property list<string> cfg_MonitorSizes: []
    property list<string> cfg_MonitorSizesDefault: []

    property bool cfg_ShowWallpaperHeader: false
    property bool cfg_ShowWallpaperHeaderDefault: false
    property bool cfg_ShowOpenImageAction: true
    property bool cfg_ShowOpenImageActionDefault: true
    property bool cfg_ShowNextAction: true
    property bool cfg_ShowNextActionDefault: true
    property bool cfg_ShowNextIndividualAction: false
    property bool cfg_ShowNextIndividualActionDefault: false
    property bool cfg_ShowNextSpannedAction: false
    property bool cfg_ShowNextSpannedActionDefault: false

    // Every edit is stamped, so the running wallpaper can tell these are the
    // newest settings and share them with every other screen (see
    // SpanState.offerConfig()). A new stamp is always newer than the one
    // loaded, even if the clock was ahead when that one was made (and has
    // since been corrected); otherwise the older settings would win.
    property string cfg_ConfigStamp: ""
    property string cfg_ConfigStampDefault: ""
    function stamp() {
        cfg_ConfigStamp = String(Math.max(Date.now(), (Number(cfg_ConfigStamp) || 0) + 1));
    }
    // The Defaults button sets every cfg_ to its default, the stamp to ""
    // as well. An empty stamp is older than any other screen's, so the
    // wallpaper would copy the old settings back over the defaults; stamp
    // the reset like any other edit. (Loading never empties the stamp: it
    // starts empty and only ever gets the saved value.)
    onCfg_ConfigStampChanged: {
        if (cfg_ConfigStamp === "") {
            stamp();
        }
    }

    // Unticked folders stay listed but are left out of the slideshow.
    function setFolderEnabled(folder, enabled) {
        const list = cfg_DisabledPaths.filter(p => p !== folder);
        if (!enabled) {
            list.push(folder);
        }
        cfg_DisabledPaths = list;
        stamp();
    }

    // Saves an edited folder list, forgetting removed folders' ticks.
    function setPaths(isSpan, newPaths) {
        if (isSpan) {
            cfg_SpanPaths = newPaths;
        } else {
            cfg_SinglePaths = newPaths;
        }
        cfg_DisabledPaths = cfg_DisabledPaths.filter(p => cfg_SpanPaths.indexOf(p) !== -1 || cfg_SinglePaths.indexOf(p) !== -1);
        stamp();
    }

    // The folder whose images are shown on the right.
    property string selectedFolder: ""
    readonly property bool selectedIsSpan: cfg_SpanPaths.indexOf(selectedFolder) !== -1

    // Keeps a folder selected while there is one to select.
    function ensureSelection() {
        if (selectedFolder !== ""
                && (cfg_SpanPaths.indexOf(selectedFolder) !== -1 || cfg_SinglePaths.indexOf(selectedFolder) !== -1)) {
            return;
        }
        selectedFolder = cfg_SinglePaths.length > 0 ? cfg_SinglePaths[0]
                       : cfg_SpanPaths.length > 0 ? cfg_SpanPaths[0] : "";
    }
    // Deferred, so both lists are loaded before the first pick.
    onCfg_SpanPathsChanged: Qt.callLater(ensureSelection)
    onCfg_SinglePathsChanged: Qt.callLater(ensureSelection)
    Component.onCompleted: Qt.callLater(ensureSelection)

    // -- monitor sizes --
    // The connected monitors, left to right, with the size each reports and
    // the size in use (the user's correction, if any), in inches.
    readonly property var sizeCorrections: Desk.parseSizes(cfg_MonitorSizes)
    readonly property var monitors: {
        const screens = Qt.application.screens;
        const list = [];
        for (let i = 0; i < screens.length; i++) {
            const s = screens[i];
            const key = Desk.monitorKey(s);
            const corrected = sizeCorrections[key];
            const reported = Desk.reportedInches(s);
            list.push({
                key: key,
                name: monitorName(s),
                x: s.virtualX,
                y: s.virtualY,
                reported: reported,
                corrected: corrected !== undefined,
                inches: corrected !== undefined ? corrected : reported
            });
        }
        list.sort((a, b) => (a.x - b.x) || (a.y - b.y));
        return list;
    }

    // "AOC 2369 (DP-1)", "DELL G2724D (DP-2)": the model, with the make
    // unless the model already starts with it.
    function monitorName(s) {
        const make = (s.manufacturer || "").split(" ")[0];
        const model = make && !s.model.toLowerCase().startsWith(make.toLowerCase())
            ? make + " " + s.model : s.model;
        return model ? i18nd("plasma_wallpaper_com.github.vasilkalchev.multimonitorslideshow", "%1 (%2)", model, s.name) : s.name;
    }

    function inchesText(inches) {
        return inches > 0 ? i18nd("plasma_wallpaper_com.github.vasilkalchev.multimonitorslideshow", "%1″", inches.toFixed(1))
                          : i18nd("plasma_wallpaper_com.github.vasilkalchev.multimonitorslideshow", "unknown");
    }

    // A size within 0.05″ of the reported one isn't a correction.
    function setMonitorSize(monitor, inches) {
        const list = cfg_MonitorSizes.filter(e => e.slice(0, e.lastIndexOf("=")) !== monitor.key);
        if (inches > 0 && Math.abs(inches - monitor.reported) >= 0.05) {
            list.push(monitor.key + "=" + inches.toFixed(1));
        }
        cfg_MonitorSizes = list;
        stamp();
    }

    // -- which spanned-image settings make a difference --
    readonly property bool spanFoldersInUse: cfg_SpanPaths.some(p => cfg_DisabledPaths.indexOf(p) === -1)
    readonly property bool severalMonitors: Desk.screenCount(Qt.application.screens) > 1
    readonly property bool spanSettingsApply: spanFoldersInUse && severalMonitors
    // The desk with every monitor at its real size.
    readonly property var physicalDesk: Desk.layout(Qt.application.screens, true, sizeCorrections)
    readonly property bool pixelSizesDiffer: physicalDesk.list.some(d => Math.abs(d.f - 1) > 0.005)
    // Centering a panorama on the join only moves it when the join isn't
    // already the middle of the monitors.
    readonly property bool joinMatters: {
        const desk = Desk.layout(Qt.application.screens, cfg_MatchPhysicalSize, sizeCorrections);
        if (desk.list.length < 2) {
            return false;
        }
        const join = Desk.joinBox(desk);
        return Math.abs(join.w - desk.box.w) > 1 || Math.abs(join.h - desk.box.h) > 1;
    }
    // Why some of them are greyed out.
    readonly property string spanNote: {
        if (!spanFoldersInUse) {
            return i18nd("plasma_wallpaper_com.github.vasilkalchev.multimonitorslideshow", "These only affect images from spanning folders, and no spanning folder is in use.");
        }
        if (!severalMonitors) {
            return i18nd("plasma_wallpaper_com.github.vasilkalchev.multimonitorslideshow", "Only one monitor is connected, so spanned images are shown like individual ones.");
        }
        const notes = [];
        if (!physicalDesk.usePhys) {
            notes.push(i18nd("plasma_wallpaper_com.github.vasilkalchev.multimonitorslideshow", "A monitor doesn't report its size; enter it under Monitor Sizes."));
        } else if (!pixelSizesDiffer) {
            notes.push(i18nd("plasma_wallpaper_com.github.vasilkalchev.multimonitorslideshow", "Your monitors have the same pixel size, so spanned images are the same size on each already."));
        }
        if (!joinMatters) {
            notes.push(i18nd("plasma_wallpaper_com.github.vasilkalchev.multimonitorslideshow", "Your monitors are arranged symmetrically, so centering on the bezel changes nothing."));
        }
        return notes.join(" ");
    }

    // The shown context-menu entries, for the "Context Menu…" button's tooltip.
    readonly property var shownMenuEntries: {
        const names = [];
        if (cfg_ShowWallpaperHeader) names.push(i18nd("plasma_wallpaper_com.github.vasilkalchev.multimonitorslideshow", "\"Wallpaper\" label"));
        if (cfg_ShowOpenImageAction) names.push(i18nd("plasma_wallpaper_com.github.vasilkalchev.multimonitorslideshow", "Open Image"));
        if (cfg_ShowNextAction) names.push(i18nd("plasma_wallpaper_com.github.vasilkalchev.multimonitorslideshow", "Next"));
        if (cfg_ShowNextIndividualAction) names.push(i18nd("plasma_wallpaper_com.github.vasilkalchev.multimonitorslideshow", "Next Individual"));
        if (cfg_ShowNextSpannedAction) names.push(i18nd("plasma_wallpaper_com.github.vasilkalchev.multimonitorslideshow", "Next Spanned"));
        return names;
    }

    spacing: 0

    // The settings, laid out like the built-in Slideshow's.
    Kirigami.FormLayout {
        id: form
        Layout.bottomMargin: Kirigami.Units.largeSpacing

        RowLayout {
            Kirigami.FormData.label: i18nd("plasma_wallpaper_com.github.vasilkalchev.multimonitorslideshow", "Change every:")
            spacing: Kirigami.Units.smallSpacing

            QQC2.SpinBox {
                from: 1
                to: 1440
                editable: true
                value: Math.max(1, Math.round(root.cfg_SlideInterval / 60))
                textFromValue: (value, locale) => i18ndp("plasma_wallpaper_com.github.vasilkalchev.multimonitorslideshow", "%1 minute", "%1 minutes", value)
                valueFromText: (text, locale) => parseInt(text)
                onValueModified: { root.cfg_SlideInterval = value * 60; root.stamp(); }
            }

            QQC2.Label {
                Layout.leftMargin: Kirigami.Units.largeSpacing
                text: i18nd("plasma_wallpaper_com.github.vasilkalchev.multimonitorslideshow", "Order:")
            }

            QQC2.ComboBox {
                id: orderCombo
                model: [
                    i18nd("plasma_wallpaper_com.github.vasilkalchev.multimonitorslideshow", "Random"),
                    i18nd("plasma_wallpaper_com.github.vasilkalchev.multimonitorslideshow", "A to Z"),
                    i18nd("plasma_wallpaper_com.github.vasilkalchev.multimonitorslideshow", "Z to A"),
                    i18nd("plasma_wallpaper_com.github.vasilkalchev.multimonitorslideshow", "Newest first"),
                    i18nd("plasma_wallpaper_com.github.vasilkalchev.multimonitorslideshow", "Oldest first")
                ]
                currentIndex: Math.max(0, Math.min(4, root.cfg_SlideshowOrder))
                onActivated: (index) => { root.cfg_SlideshowOrder = index; root.stamp(); }

                QQC2.ToolTip.visible: hovered && !popup.visible
                QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                QQC2.ToolTip.text: i18nd("plasma_wallpaper_com.github.vasilkalchev.multimonitorslideshow", "Spanned and individual images take turns in one sequence. Random shuffles it. The other orders go through the images by file name or by date modified; on an individual turn the monitors show the next images in line, left to right.")
            }

            QQC2.Button {
                id: menuButton
                Layout.leftMargin: Kirigami.Units.largeSpacing
                icon.name: "application-menu"
                text: i18nd("plasma_wallpaper_com.github.vasilkalchev.multimonitorslideshow", "Context Menu…")
                onClicked: menuPopup.opened ? menuPopup.close() : menuPopup.open()

                QQC2.ToolTip.visible: hovered && !menuPopup.visible
                QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                QQC2.ToolTip.text: (root.shownMenuEntries.length > 0
                    ? i18nd("plasma_wallpaper_com.github.vasilkalchev.multimonitorslideshow", "Right-clicking the desktop shows: %1", root.shownMenuEntries.join(", "))
                    : i18nd("plasma_wallpaper_com.github.vasilkalchev.multimonitorslideshow", "Right-clicking the desktop shows no wallpaper entries"))
                    + "\n" + i18nd("plasma_wallpaper_com.github.vasilkalchev.multimonitorslideshow", "Click to choose the entries")

                QQC2.Popup {
                    id: menuPopup
                    y: menuButton.height

                    contentItem: ColumnLayout {
                        spacing: 0

                        QQC2.CheckBox {
                            text: i18nd("plasma_wallpaper_com.github.vasilkalchev.multimonitorslideshow", "\"Wallpaper\" separator label")
                            checked: root.cfg_ShowWallpaperHeader
                            onToggled: { root.cfg_ShowWallpaperHeader = checked; root.stamp(); }
                            QQC2.ToolTip.visible: hovered
                            QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                            QQC2.ToolTip.text: i18nd("plasma_wallpaper_com.github.vasilkalchev.multimonitorslideshow", "A grayed-out \"Wallpaper\" heading above the entries below")
                        }
                        QQC2.CheckBox {
                            text: i18nd("plasma_wallpaper_com.github.vasilkalchev.multimonitorslideshow", "Open Image")
                            checked: root.cfg_ShowOpenImageAction
                            onToggled: { root.cfg_ShowOpenImageAction = checked; root.stamp(); }
                            QQC2.ToolTip.visible: hovered
                            QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                            QQC2.ToolTip.text: i18nd("plasma_wallpaper_com.github.vasilkalchev.multimonitorslideshow", "Opens the image shown on that monitor in your image viewer")
                        }
                        QQC2.CheckBox {
                            text: i18nd("plasma_wallpaper_com.github.vasilkalchev.multimonitorslideshow", "Next")
                            checked: root.cfg_ShowNextAction
                            onToggled: { root.cfg_ShowNextAction = checked; root.stamp(); }
                            QQC2.ToolTip.visible: hovered
                            QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                            QQC2.ToolTip.text: i18nd("plasma_wallpaper_com.github.vasilkalchev.multimonitorslideshow", "Skips to the next image in the sequence, spanned or individual")
                        }
                        QQC2.CheckBox {
                            text: i18nd("plasma_wallpaper_com.github.vasilkalchev.multimonitorslideshow", "Next Individual")
                            checked: root.cfg_ShowNextIndividualAction
                            onToggled: { root.cfg_ShowNextIndividualAction = checked; root.stamp(); }
                            QQC2.ToolTip.visible: hovered
                            QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                            QQC2.ToolTip.text: i18nd("plasma_wallpaper_com.github.vasilkalchev.multimonitorslideshow", "Skips ahead to the next turn of individual images, one per monitor")
                        }
                        QQC2.CheckBox {
                            text: i18nd("plasma_wallpaper_com.github.vasilkalchev.multimonitorslideshow", "Next Spanned")
                            checked: root.cfg_ShowNextSpannedAction
                            onToggled: { root.cfg_ShowNextSpannedAction = checked; root.stamp(); }
                            QQC2.ToolTip.visible: hovered
                            QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                            QQC2.ToolTip.text: i18nd("plasma_wallpaper_com.github.vasilkalchev.multimonitorslideshow", "Skips ahead to the next spanned image")
                        }
                    }
                }
            }
        }

        RowLayout {
            Kirigami.FormData.label: i18nd("plasma_wallpaper_com.github.vasilkalchev.multimonitorslideshow", "Spanned images:")
            enabled: root.spanSettingsApply
            spacing: Kirigami.Units.smallSpacing

            QQC2.CheckBox {
                text: i18nd("plasma_wallpaper_com.github.vasilkalchev.multimonitorslideshow", "Same physical size on every monitor")
                enabled: root.pixelSizesDiffer
                checked: root.cfg_MatchPhysicalSize
                onToggled: { root.cfg_MatchPhysicalSize = checked; root.stamp(); }

                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                QQC2.ToolTip.text: i18nd("plasma_wallpaper_com.github.vasilkalchev.multimonitorslideshow", "Monitors with different pixel sizes show the same image at different sizes: a 23″ 1080p monitor's pixels are about 14% larger than a 27″ 1440p monitor's. When on, spanned images are scaled per monitor so they have the same real size on every monitor, and lines continue straight across the bezel. This uses the size each monitor reports; correct a wrong one under Monitor Sizes.")
            }

            QQC2.Button {
                id: sizesButton
                icon.name: "video-display"
                text: i18nd("plasma_wallpaper_com.github.vasilkalchev.multimonitorslideshow", "Monitor Sizes…")
                onClicked: sizesPopup.opened ? sizesPopup.close() : sizesPopup.open()

                QQC2.ToolTip.visible: hovered && !sizesPopup.visible
                QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                QQC2.ToolTip.text: i18nd("plasma_wallpaper_com.github.vasilkalchev.multimonitorslideshow", "In use: %1", root.monitors.map(m => m.name + " " + root.inchesText(m.inches)).join(", "))
                    + "\n" + i18nd("plasma_wallpaper_com.github.vasilkalchev.multimonitorslideshow", "Click to correct a monitor that reports a wrong size")

                QQC2.Popup {
                    id: sizesPopup
                    y: sizesButton.height

                    contentItem: ColumnLayout {
                        spacing: Kirigami.Units.smallSpacing

                        QQC2.Label {
                            Layout.maximumWidth: Kirigami.Units.gridUnit * 22
                            wrapMode: Text.Wrap
                            text: i18nd("plasma_wallpaper_com.github.vasilkalchev.multimonitorslideshow", "Each monitor's size, measured diagonally, as the monitor reports it. If one is wrong, enter the right one.")
                        }

                        Repeater {
                            model: root.monitors

                            delegate: RowLayout {
                                id: monitorRow
                                required property var modelData
                                spacing: Kirigami.Units.smallSpacing

                                QQC2.Label {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: Kirigami.Units.gridUnit * 8
                                    text: monitorRow.modelData.name
                                }

                                // In tenths of an inch.
                                QQC2.SpinBox {
                                    from: 50
                                    to: 1500
                                    editable: true
                                    value: Math.round(monitorRow.modelData.inches * 10)
                                    textFromValue: (value, locale) => root.inchesText(value / 10)
                                    valueFromText: (text, locale) => Math.round(parseFloat(text.replace(",", ".")) * 10)
                                    validator: RegularExpressionValidator {
                                        regularExpression: /\d{0,3}([.,]\d?)?\s*[″"]?/
                                    }
                                    onValueModified: root.setMonitorSize(monitorRow.modelData, value / 10)
                                }

                                QQC2.ToolButton {
                                    icon.name: "edit-undo"
                                    opacity: monitorRow.modelData.corrected ? 1 : 0
                                    enabled: monitorRow.modelData.corrected
                                    onClicked: root.setMonitorSize(monitorRow.modelData, 0)

                                    QQC2.ToolTip.visible: hovered
                                    QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                                    QQC2.ToolTip.text: i18nd("plasma_wallpaper_com.github.vasilkalchev.multimonitorslideshow", "Back to the reported size, %1", root.inchesText(monitorRow.modelData.reported))
                                }
                            }
                        }
                    }
                }
            }
        }

        QQC2.CheckBox {
            enabled: root.spanSettingsApply && root.joinMatters
            text: i18nd("plasma_wallpaper_com.github.vasilkalchev.multimonitorslideshow", "Always center on the bezel between the monitors")
            checked: root.cfg_SpanFit === 1
            onToggled: { root.cfg_SpanFit = checked ? 1 : 0; root.stamp(); }

            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
            QQC2.ToolTip.text: i18nd("plasma_wallpaper_com.github.vasilkalchev.multimonitorslideshow", "Full-width images, as wide as all of your monitors together (such as a 32:9 image on two 16:9 monitors), are always centered on the bezel. Other spanned images, panoramas, are centered on your monitors as a whole when this is off, which cuts off the least. When it's on, they're centered on the bezel between the two middle monitors too (with an odd number, on the middle monitor's center), so a two-part wallpaper made for other monitors, such as two 16:10 halves, still splits on the bezel. More is cut off at the edges.")
        }

        QQC2.Label {
            visible: text !== ""
            Layout.maximumWidth: Kirigami.Units.gridUnit * 26
            wrapMode: Text.Wrap
            font: Kirigami.Theme.smallFont
            color: Kirigami.Theme.disabledTextColor
            text: root.spanNote
        }
    }

    // Folders on the left, the selected folder's images on the right.
    RowLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: 0

        // Wide enough for most paths; longer ones wrap. Layouts fill by
        // default, so the width is fixed explicitly.
        ColumnLayout {
            Layout.fillWidth: false
            Layout.fillHeight: true
            Layout.preferredWidth: Kirigami.Units.gridUnit * 20
            spacing: 0

            Kirigami.Separator {
                Layout.fillWidth: true
            }

            FolderListSection {
                Layout.fillWidth: true
                Layout.fillHeight: true
                title: i18nd("plasma_wallpaper_com.github.vasilkalchev.multimonitorslideshow", "Individual folders")
                toolTip: i18nd("plasma_wallpaper_com.github.vasilkalchev.multimonitorslideshow", "Ordinary wallpapers, a different one on each monitor")
                paths: root.cfg_SinglePaths
                disabledPaths: root.cfg_DisabledPaths
                selectedFolder: root.selectedFolder
                onPathsEdited: (newPaths) => root.setPaths(false, newPaths)
                onFolderEnabledToggled: (folder, enabled) => root.setFolderEnabled(folder, enabled)
                onFolderSelected: (folder) => { root.selectedFolder = folder; }
            }

            Kirigami.Separator {
                Layout.fillWidth: true
            }

            FolderListSection {
                Layout.fillWidth: true
                Layout.fillHeight: true
                title: i18nd("plasma_wallpaper_com.github.vasilkalchev.multimonitorslideshow", "Spanning folders")
                toolTip: i18nd("plasma_wallpaper_com.github.vasilkalchev.multimonitorslideshow", "Wide images, each shown across all monitors together")
                paths: root.cfg_SpanPaths
                disabledPaths: root.cfg_DisabledPaths
                selectedFolder: root.selectedFolder
                onPathsEdited: (newPaths) => root.setPaths(true, newPaths)
                onFolderEnabledToggled: (folder, enabled) => root.setFolderEnabled(folder, enabled)
                onFolderSelected: (folder) => { root.selectedFolder = folder; }
            }
        }

        Kirigami.Separator {
            Layout.fillHeight: true
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            Kirigami.Separator {
                Layout.fillWidth: true
            }

            FolderImages {
                Layout.fillWidth: true
                Layout.fillHeight: true
                folder: root.selectedFolder
                isSpan: root.selectedIsSpan
                folderEnabled: root.cfg_DisabledPaths.indexOf(root.selectedFolder) === -1
                order: root.cfg_SlideshowOrder
            }
        }
    }
}
