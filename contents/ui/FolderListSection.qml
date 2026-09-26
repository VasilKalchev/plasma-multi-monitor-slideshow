/*
    A titled, editable list of folder paths, used twice in config.qml
    (once for the individual folders, once for the spanning folders).
    Clicking a folder selects it, so config.qml can show its images.
*/
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import QtQuick.Dialogs as QtDialogs
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: root

    property string title: ""
    property string toolTip: ""
    property list<string> paths: []
    property list<string> disabledPaths: []
    property string selectedFolder: ""
    signal pathsEdited(var newPaths)
    signal folderSelected(string folder)
    signal folderEnabledToggled(string folder, bool enabled)

    // A folder URL as a readable path.
    function localPath(url) {
        const path = String(url).replace(/^file:\/\//, "").replace(/\/+$/, "");
        try {
            return decodeURIComponent(path);
        } catch (e) {
            return path;
        }
    }

    spacing: 0

    Kirigami.InlineViewHeader {
        Layout.fillWidth: true
        text: root.title
        actions: [
            Kirigami.Action {
                icon.name: "list-add-symbolic"
                text: i18ndc("plasma_wallpaper_com.github.vasilkalchev.multimonitorslideshow", "@action:button the thing being added is a folder", "Add…")
                Accessible.name: i18ndc("plasma_wallpaper_com.github.vasilkalchev.multimonitorslideshow", "@action:button", "Add Folder…")
                onTriggered: folderDialogLoader.active = true
            }
        ]

        HoverHandler {
            id: headerHover
        }
        QQC2.ToolTip.visible: headerHover.hovered && root.toolTip !== ""
        QQC2.ToolTip.text: root.toolTip
        QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
    }

    QQC2.ScrollView {
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.minimumHeight: Kirigami.Units.gridUnit * 4

        background: Rectangle {
            Kirigami.Theme.inherit: false
            Kirigami.Theme.colorSet: Kirigami.Theme.View
            color: Kirigami.Theme.backgroundColor
        }

        ListView {
            id: pathsView
            model: root.paths
            clip: true

            delegate: Kirigami.SubtitleDelegate {
                id: baseListItem

                required property string modelData
                required property int index
                readonly property string path: root.localPath(modelData)
                readonly property bool folderEnabled: root.disabledPaths.indexOf(modelData) === -1

                width: pathsView.width
                highlighted: baseListItem.modelData === root.selectedFolder
                onClicked: root.folderSelected(baseListItem.modelData)

                text: path.split("/").pop()
                // The parent folder; a zero-width space after each slash lets
                // a long path wrap there.
                subtitle: path.replace(/\/[^/]*$/, "").replace(/\//g, "/\u200b")

                contentItem: RowLayout {
                    spacing: Kirigami.Units.smallSpacing

                    QQC2.CheckBox {
                        checked: baseListItem.folderEnabled
                        onToggled: root.folderEnabledToggled(baseListItem.modelData, checked)
                        QQC2.ToolTip.visible: hovered
                        QQC2.ToolTip.text: i18nd("plasma_wallpaper_com.github.vasilkalchev.multimonitorslideshow", "Use this folder in the slideshow")
                        QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                    }

                    Kirigami.TitleSubtitle {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        opacity: baseListItem.folderEnabled ? 1 : 0.5
                        title: baseListItem.text
                        subtitle: baseListItem.subtitle
                        selected: baseListItem.highlighted
                    }

                    QQC2.ToolButton {
                        icon.name: "edit-delete-remove-symbolic"
                        text: i18nd("plasma_wallpaper_com.github.vasilkalchev.multimonitorslideshow", "Remove Folder")
                        display: QQC2.Button.IconOnly
                        onClicked: {
                            const list = root.paths.slice();
                            list.splice(baseListItem.index, 1);
                            root.pathsEdited(list);
                        }
                        QQC2.ToolTip.visible: hovered
                        QQC2.ToolTip.text: text
                        QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                    }

                    QQC2.ToolButton {
                        icon.name: "document-open-folder"
                        text: i18nd("plasma_wallpaper_com.github.vasilkalchev.multimonitorslideshow", "Open Folder…")
                        display: QQC2.Button.IconOnly
                        onClicked: Qt.openUrlExternally(baseListItem.modelData)
                        QQC2.ToolTip.visible: hovered
                        QQC2.ToolTip.text: text
                        QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                    }
                }
            }

            Kirigami.PlaceholderMessage {
                anchors.centerIn: parent
                width: parent.width - Kirigami.Units.largeSpacing * 4
                visible: pathsView.count === 0
                text: i18nd("plasma_wallpaper_com.github.vasilkalchev.multimonitorslideshow", "There are no folders configured")
            }
        }
    }

    Loader {
        id: folderDialogLoader
        active: false
        sourceComponent: QtDialogs.FolderDialog {
            visible: folderDialogLoader.status === Loader.Ready
            onAccepted: {
                const list = root.paths.slice();
                const f = selectedFolder.toString();
                if (list.indexOf(f) === -1) {
                    list.push(f);
                    root.pathsEdited(list);
                }
                root.folderSelected(f);
                folderDialogLoader.active = false;
            }
            onRejected: folderDialogLoader.active = false
        }
    }
}
