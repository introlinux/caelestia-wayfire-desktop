pragma ComponentBehavior: Bound

import ".."
import QtQuick
import Caelestia.Config
import Caelestia.Models
import qs.components
import qs.components.controls
import qs.components.effects
import qs.components.images
import qs.services

GridView {
    id: root

    required property Session session

    readonly property int minCellWidth: 200 + Tokens.spacing.normal
    readonly property int columnsCount: Math.max(1, Math.floor(width / minCellWidth))

    cellWidth: width / columnsCount
    cellHeight: 140 + Tokens.spacing.normal

    model: Wallpapers.list

    clip: true

    StyledScrollBar.vertical: StyledScrollBar {
        flickable: root
    }

    delegate: Item {
        required property var modelData
        required property int index
        readonly property bool isCurrent: modelData && modelData.path === Wallpapers.actualCurrent
        readonly property bool isAnimated: modelData && Wallpapers.isVideo(modelData.path)
        readonly property real itemMargin: Tokens.spacing.normal / 2
        readonly property real itemRadius: Tokens.rounding.normal

        readonly property string thumbPath: Wallpapers.videoThumbs[modelData.path] ?? ""
        readonly property string displayPath: isAnimated ? thumbPath : modelData.path

        width: root.cellWidth
        height: root.cellHeight

        Component.onCompleted: {
            if (isAnimated)
                Wallpapers.requestVideoThumb(modelData.path);
        }

        StateLayer {
            onClicked: {
                Wallpapers.setWallpaper(modelData.path);
            }

            anchors.fill: parent
            anchors.leftMargin: itemMargin
            anchors.rightMargin: itemMargin
            anchors.topMargin: itemMargin
            anchors.bottomMargin: itemMargin
            radius: itemRadius
        }

        StyledClippingRect {
            id: image

            anchors.fill: parent
            anchors.leftMargin: itemMargin
            anchors.rightMargin: itemMargin
            anchors.topMargin: itemMargin
            anchors.bottomMargin: itemMargin
            color: Colours.tPalette.m3surfaceContainer
            radius: itemRadius
            antialiasing: true
            layer.enabled: true
            layer.smooth: true

            CachingImage {
                id: cachingImage

                path: displayPath
                anchors.fill: parent
                fillMode: Image.PreserveAspectCrop
                cache: true
                visible: opacity > 0
                antialiasing: true
                smooth: true
                sourceSize: Qt.size(width, height)

                opacity: status === Image.Ready ? 1 : 0

                Behavior on opacity {
                    NumberAnimation {
                        duration: 1000
                        easing.type: Easing.OutQuad
                    }
                }
            }

            // Fallback if CachingImage fails to load
            Image {
                id: fallbackImage

                anchors.fill: parent
                source: fallbackTimer.triggered && cachingImage.status !== Image.Ready ? displayPath : ""
                asynchronous: true
                fillMode: Image.PreserveAspectCrop
                cache: true
                visible: opacity > 0
                antialiasing: true
                smooth: true
                sourceSize: Qt.size(width, height)

                opacity: status === Image.Ready && cachingImage.status !== Image.Ready ? 1 : 0

                Behavior on opacity {
                    NumberAnimation {
                        duration: 1000
                        easing.type: Easing.OutQuad
                    }
                }
            }

            Timer {
                id: fallbackTimer

                property bool triggered: false

                interval: 800
                running: cachingImage.status === Image.Loading || cachingImage.status === Image.Null
                onTriggered: triggered = true
            }

            // Filmstrip Top Border (film perforations)
            Rectangle {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: 10
                color: Qt.rgba(0, 0, 0, 0.75)
                visible: isAnimated
                z: 2

                Row {
                    anchors.centerIn: parent
                    spacing: 6
                    Repeater {
                        model: Math.floor(root.cellWidth / 12)
                        Rectangle {
                            width: 5
                            height: 4
                            radius: 1
                            color: Qt.rgba(1, 1, 1, 0.65)
                        }
                    }
                }
            }

            // Filmstrip Bottom Border
            Rectangle {
                anchors.bottom: filenameOverlay.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: 10
                color: Qt.rgba(0, 0, 0, 0.75)
                visible: isAnimated
                z: 2

                Row {
                    anchors.centerIn: parent
                    spacing: 6
                    Repeater {
                        model: Math.floor(root.cellWidth / 12)
                        Rectangle {
                            width: 5
                            height: 4
                            radius: 1
                            color: Qt.rgba(1, 1, 1, 0.65)
                        }
                    }
                }
            }

            // Center Play Icon Overlay
            Rectangle {
                anchors.centerIn: parent
                width: 36
                height: 36
                radius: 18
                color: Qt.rgba(0, 0, 0, 0.55)
                border.color: Qt.rgba(255, 255, 255, 0.6)
                border.width: 1.5
                visible: isAnimated
                z: 3

                MaterialIcon {
                    anchors.centerIn: parent
                    text: "play_arrow"
                    color: "white"
                    font.pointSize: Tokens.font.size.large
                }
            }

            // Top-Left MP4 Pill Badge
            StyledClippingRect {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.margins: Tokens.padding.small + 2
                visible: isAnimated
                color: Qt.rgba(Colours.palette.m3primary.r, Colours.palette.m3primary.g, Colours.palette.m3primary.b, 0.9)
                radius: Tokens.rounding.full
                implicitWidth: animRow.implicitWidth + Tokens.padding.small * 1.5
                implicitHeight: animRow.implicitHeight + Tokens.padding.smaller
                z: 4

                Row {
                    id: animRow
                    anchors.centerIn: parent
                    spacing: 3
                    MaterialIcon {
                        text: "videocam"
                        color: Colours.palette.m3onPrimary
                        font.pointSize: Tokens.font.size.smaller - 2
                    }
                    StyledText {
                        text: "MP4"
                        color: Colours.palette.m3onPrimary
                        font.pointSize: Tokens.font.size.smaller - 2
                        font.bold: true
                    }
                }
            }

            // Gradient overlay for filename
            Rectangle {
                id: filenameOverlay

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom

                implicitHeight: filenameText.implicitHeight + Tokens.padding.normal * 1.5
                radius: 0

                gradient: Gradient {
                    GradientStop {
                        position: 0.0
                        color: Qt.rgba(Colours.palette.m3surface.r, Colours.palette.m3surface.g, Colours.palette.m3surface.b, 0)
                    }
                    GradientStop {
                        position: 0.3
                        color: Qt.rgba(Colours.palette.m3surface.r, Colours.palette.m3surface.g, Colours.palette.m3surface.b, 0.7)
                    }
                    GradientStop {
                        position: 0.6
                        color: Qt.rgba(Colours.palette.m3surface.r, Colours.palette.m3surface.g, Colours.palette.m3surface.b, 0.9)
                    }
                    GradientStop {
                        position: 1.0
                        color: Qt.rgba(Colours.palette.m3surface.r, Colours.palette.m3surface.g, Colours.palette.m3surface.b, 0.95)
                    }
                }

                opacity: 0

                Component.onCompleted: {
                    opacity = 1;
                }

                Behavior on opacity {
                    NumberAnimation {
                        duration: 1000
                        easing.type: Easing.OutCubic
                    }
                }
            }
        }

        Rectangle {
            anchors.fill: parent
            anchors.leftMargin: itemMargin
            anchors.rightMargin: itemMargin
            anchors.topMargin: itemMargin
            anchors.bottomMargin: itemMargin
            color: "transparent"
            radius: itemRadius + border.width
            border.width: isCurrent ? 2 : 0
            border.color: Colours.palette.m3primary
            antialiasing: true
            smooth: true

            Behavior on border.width {
                NumberAnimation {
                    duration: 150
                    easing.type: Easing.OutQuad
                }
            }

            MaterialIcon {
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Tokens.padding.small

                visible: isCurrent
                text: "check_circle"
                color: Colours.palette.m3primary
                font.pointSize: Tokens.font.size.large
            }
        }

        StyledText {
            id: filenameText

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.leftMargin: Tokens.padding.normal + Tokens.spacing.normal / 2
            anchors.rightMargin: Tokens.padding.normal + Tokens.spacing.normal / 2
            anchors.bottomMargin: Tokens.padding.normal

            text: modelData.name
            font.pointSize: Tokens.font.size.smaller
            font.weight: 500
            color: isCurrent ? Colours.palette.m3primary : Colours.palette.m3onSurface
            elide: Text.ElideMiddle
            maximumLineCount: 1
            horizontalAlignment: Text.AlignHCenter

            opacity: 0

            Component.onCompleted: {
                opacity = 1;
            }

            Behavior on opacity {
                NumberAnimation {
                    duration: 1000
                    easing.type: Easing.OutCubic
                }
            }
        }
    }
}
