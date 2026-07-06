pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Caelestia.Config
import Caelestia.Models
import qs.components
import qs.components.containers
import qs.components.controls
import qs.services
import qs.utils

ColumnLayout {
    id: root

    required property var props
    required property DrawerVisibilities visibilities

    spacing: 0

    WrapperMouseArea {
        Layout.fillWidth: true

        cursorShape: Qt.PointingHandCursor
        onClicked: root.props.screenshotListExpanded = !root.props.screenshotListExpanded

        RowLayout {
            spacing: Tokens.spacing.smaller

            MaterialIcon {
                Layout.alignment: Qt.AlignVCenter
                text: "list"
                font.pointSize: Tokens.font.size.large
            }

            StyledText {
                Layout.alignment: Qt.AlignVCenter
                Layout.fillWidth: true
                text: qsTr("Screenshots")
                font.pointSize: Tokens.font.size.normal
            }

            IconButton {
                icon: root.props.screenshotListExpanded ? "unfold_less" : "unfold_more"
                type: IconButton.Text
                label.animate: true
                onClicked: root.props.screenshotListExpanded = !root.props.screenshotListExpanded
            }
        }
    }

    StyledListView {
        id: list

        model: FileSystemModel {
            path: Paths.screenshotsdir
            nameFilters: ["screenshot_*.png"]
            sortReverse: true
        }

        Layout.fillWidth: true
        Layout.rightMargin: -Tokens.spacing.small
        implicitHeight: (Tokens.font.size.larger + Tokens.padding.small) * (root.props.screenshotListExpanded ? 10 : 3)
        clip: true

        StyledScrollBar.vertical: StyledScrollBar {
            flickable: list
        }

        delegate: RowLayout {
            id: screenshot

            required property FileSystemEntry modelData
            property string baseName

            anchors.left: list.contentItem.left
            anchors.right: list.contentItem.right
            anchors.rightMargin: Tokens.spacing.small
            spacing: Tokens.spacing.small / 2

            Component.onCompleted: baseName = modelData.baseName

            StyledText {
                Layout.fillWidth: true
                Layout.rightMargin: Tokens.spacing.small / 2
                text: {
                    const matches = screenshot.baseName.match(/^screenshot_(\d{4})(\d{2})(\d{2})_(\d{2})-(\d{2})-(\d{2})/);
                    if (!matches)
                        return screenshot.baseName;
                    const date = new Date(...matches.slice(1));
                    date.setMonth(date.getMonth() - 1);
                    return qsTr("Screenshot at %1").arg(Qt.formatDateTime(date, Qt.locale()));
                }
                color: Colours.palette.m3onSurfaceVariant
                elide: Text.ElideRight
            }

            IconButton {
                icon: "open_in_new"
                type: IconButton.Text
                onClicked: {
                    root.visibilities.utilities = false;
                    root.visibilities.sidebar = false;
                    Quickshell.execDetached(["xdg-open", screenshot.modelData.path]);
                }
            }

            IconButton {
                icon: "folder"
                type: IconButton.Text
                onClicked: {
                    root.visibilities.utilities = false;
                    root.visibilities.sidebar = false;
                    const dir = screenshot.modelData.path.substring(0, screenshot.modelData.path.lastIndexOf('/'));
                    Quickshell.execDetached(["xdg-open", dir]);
                }
            }

            IconButton {
                icon: "delete_forever"
                type: IconButton.Text
                label.color: Colours.palette.m3error
                stateLayer.color: Colours.palette.m3error
                onClicked: root.props.screenshotConfirmDelete = screenshot.modelData.path
            }
        }

        add: Transition {
            Anim {
                property: "opacity"
                from: 0
                to: 1
            }
            Anim {
                property: "scale"
                from: 0.5
                to: 1
            }
        }

        remove: Transition {
            Anim {
                property: "opacity"
                to: 0
            }
            Anim {
                property: "scale"
                to: 0.5
            }
        }

        displaced: Transition {
            Anim {
                properties: "opacity,scale"
                to: 1
            }
            Anim {
                property: "y"
            }
        }

        Loader {
            asynchronous: true
            anchors.centerIn: parent

            opacity: list.count === 0 ? 1 : 0
            active: opacity > 0

            sourceComponent: RowLayout {
                spacing: Tokens.spacing.smaller

                MaterialIcon {
                    Layout.alignment: Qt.AlignHCenter
                    text: "photo_library"
                    color: Colours.palette.m3outline
                }

                StyledText {
                    text: qsTr("No screenshots found")
                    color: Colours.palette.m3outline
                }
            }

            Behavior on opacity {
                Anim {}
            }
        }

        Behavior on implicitHeight {
            Anim {
                type: Anim.DefaultSpatial
            }
        }
    }
}
