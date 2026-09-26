/*
    Settings UI for the Multi-Monitor Slideshow wallpaper plugin.
*/
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

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
    // SpanState.offerConfig()).
    property string cfg_ConfigStamp: ""
    property string cfg_ConfigStampDefault: ""
    function stamp() {
        cfg_ConfigStamp = String(Date.now());
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
            spacing: Kirigami.Units.smallSpacing

            QQC2.ComboBox {
                id: fitCombo
                textRole: "text"
                model: [
                    {
                        text: i18nd("plasma_wallpaper_com.github.vasilkalchev.multimonitorslideshow", "Detect pre-split images"),
                        help: i18nd("plasma_wallpaper_com.github.vasilkalchev.multimonitorslideshow", "Images made of one monitor-shaped part per monitor are split so each part lands on its own monitor. Everything else is treated as one panorama, centered and scaled until all monitors are covered.")
                    },
                    {
                        text: i18nd("plasma_wallpaper_com.github.vasilkalchev.multimonitorslideshow", "Center on the monitor join"),
                        help: i18nd("plasma_wallpaper_com.github.vasilkalchev.multimonitorslideshow", "Every image is centered horizontally on the edge between your monitors (vertically on your largest monitor) and scaled until all monitors are covered. A two-part wallpaper splits on the bezel; wider or taller images lose more at the edges.")
                    }
                ]
                currentIndex: root.cfg_SpanFit === 1 ? 1 : 0
                onActivated: (index) => { root.cfg_SpanFit = index; root.stamp(); }

                delegate: QQC2.ItemDelegate {
                    required property var modelData
                    required property int index
                    width: ListView.view ? ListView.view.width : implicitWidth
                    text: modelData.text
                    highlighted: fitCombo.highlightedIndex === index
                    hoverEnabled: true
                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                    QQC2.ToolTip.text: modelData.help
                }

                QQC2.ToolTip.visible: hovered && !popup.visible
                QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                QQC2.ToolTip.text: model[currentIndex].help
            }

            QQC2.CheckBox {
                Layout.leftMargin: Kirigami.Units.largeSpacing
                text: i18nd("plasma_wallpaper_com.github.vasilkalchev.multimonitorslideshow", "Compensate for pixel size")
                checked: root.cfg_MatchPhysicalSize
                onToggled: { root.cfg_MatchPhysicalSize = checked; root.stamp(); }

                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                QQC2.ToolTip.text: i18nd("plasma_wallpaper_com.github.vasilkalchev.multimonitorslideshow", "Monitors with different pixel sizes show the same picture at different physical sizes: a 23\" 1080p monitor's pixels are about 14% larger than a 27\" 1440p monitor's. When on, spanned images are scaled per monitor so they have the same real size on every monitor and lines continue straight across the bezel. Uses the size each monitor reports; turn it off if one reports a wrong size.")
            }
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
