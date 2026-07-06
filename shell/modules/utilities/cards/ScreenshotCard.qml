pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

StyledRect {
    id: root

    required property var props
    required property DrawerVisibilities visibilities

    Layout.fillWidth: true
    implicitHeight: layout.implicitHeight + layout.anchors.margins * 2

    radius: Tokens.rounding.normal
    color: Colours.tPalette.m3surfaceContainer

    function shoot(m) {
        visibilities.utilities = false;
        visibilities.sidebar = false;
        Screenshot.shoot(m);
    }

    ColumnLayout {
        id: layout

        anchors.fill: parent
        anchors.margins: Tokens.padding.large
        spacing: Tokens.spacing.normal

        RowLayout {
            spacing: Tokens.spacing.normal

            StyledRect {
                implicitWidth: implicitHeight
                implicitHeight: {
                    const h = icon.implicitHeight + Tokens.padding.smaller * 2;
                    return h - (h % 2);
                }

                radius: Tokens.rounding.full
                color: Colours.palette.m3secondaryContainer

                MaterialIcon {
                    id: icon

                    anchors.centerIn: parent
                    anchors.horizontalCenterOffset: -0.5
                    anchors.verticalCenterOffset: 1.5
                    text: "screenshot"
                    color: Colours.palette.m3onSecondaryContainer
                    font.pointSize: Tokens.font.size.large
                }
            }

            StyledText {
                Layout.fillWidth: true
                text: qsTr("Screenshot")
                font.pointSize: Tokens.font.size.normal
            }

            IconButton {
                icon: "fullscreen"
                type: IconButton.Tonal
                font.pointSize: Tokens.font.size.large
                onClicked: root.shoot(0)
            }

            IconButton {
                icon: "screenshot_region"
                type: IconButton.Tonal
                font.pointSize: Tokens.font.size.large
                onClicked: root.shoot(1)
            }

            IconButton {
                icon: "content_copy"
                type: IconButton.Tonal
                font.pointSize: Tokens.font.size.large
                onClicked: root.shoot(2)
            }
        }

        ScreenshotList {
            props: root.props
            visibilities: root.visibilities
            Layout.fillWidth: true
        }
    }
}
