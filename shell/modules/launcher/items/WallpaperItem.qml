import QtQuick
import Caelestia.Config
import Caelestia.Models
import qs.components
import qs.components.effects
import qs.components.images
import qs.services

Item {
    id: root

    required property FileSystemEntry modelData
    required property DrawerVisibilities visibilities

    readonly property bool isAnimated: root.modelData && Wallpapers.isVideo(root.modelData.path)
    readonly property string thumbPath: Wallpapers.videoThumbs[root.modelData.path] ?? ""

    scale: 0.5
    opacity: 0
    z: PathView.z ?? 0 // qmllint disable missing-property

    Component.onCompleted: {
        if (isAnimated)
            Wallpapers.requestVideoThumb(root.modelData.path);

        scale = Qt.binding(() => PathView.isCurrentItem ? 1 : PathView.onPath ? 0.8 : 0);
        opacity = Qt.binding(() => PathView.onPath ? 1 : 0);
    }

    implicitWidth: image.width + Tokens.padding.larger * 2
    implicitHeight: image.height + label.height + Tokens.spacing.small / 2 + Tokens.padding.large + Tokens.padding.normal

    StateLayer {
        radius: Tokens.rounding.normal
        onClicked: {
            Wallpapers.setWallpaper(root.modelData.path);
            Wallpapers.preview(root.modelData.path);
        }
    }

    Elevation {
        anchors.fill: image
        radius: image.radius
        opacity: root.PathView.isCurrentItem ? 1 : 0
        level: 4

        Behavior on opacity {
            Anim {}
        }
    }

    StyledClippingRect {
        id: image

        anchors.horizontalCenter: parent.horizontalCenter
        y: Tokens.padding.large
        color: Colours.tPalette.m3surfaceContainer
        radius: Tokens.rounding.normal

        implicitWidth: Tokens.sizes.launcher.wallpaperWidth
        implicitHeight: implicitWidth / 16 * 9

        MaterialIcon {
            anchors.centerIn: parent
            text: isAnimated ? "videocam" : "image"
            color: Colours.tPalette.m3outline
            font.pointSize: Tokens.font.size.extraLarge * 2
            font.weight: 600
        }

        // Static wallpaper image
        CachingImage {
            path: isAnimated ? "" : root.modelData.path
            smooth: !root.PathView.view.moving
            cache: true
            visible: !isAnimated

            anchors.fill: parent
        }

        // Animated video wallpaper thumbnail
        Image {
            id: videoThumbImage
            source: isAnimated && thumbPath ? (thumbPath.startsWith("file://") ? thumbPath : "file://" + thumbPath) : ""
            smooth: !root.PathView.view.moving
            asynchronous: true
            fillMode: Image.PreserveAspectCrop
            cache: true
            visible: isAnimated && opacity > 0
            anchors.fill: parent

            opacity: status === Image.Ready ? 1 : 0

            Behavior on opacity {
                NumberAnimation {
                    duration: 400
                    easing.type: Easing.OutQuad
                }
            }
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
                    model: Math.floor(image.width / 12)
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
            anchors.bottom: parent.bottom
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
                    model: Math.floor(image.width / 12)
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
    }

    StyledText {
        id: label

        anchors.top: image.bottom
        anchors.topMargin: Tokens.spacing.small / 2
        anchors.horizontalCenter: parent.horizontalCenter

        width: image.width - Tokens.padding.normal * 2
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        renderType: Text.QtRendering
        text: root.modelData.relativePath
        font.pointSize: Tokens.font.size.normal
    }

    Behavior on scale {
        Anim {}
    }

    Behavior on opacity {
        Anim {}
    }
}
