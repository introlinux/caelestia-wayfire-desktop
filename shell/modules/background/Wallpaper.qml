pragma ComponentBehavior: Bound

import QtQuick
import QtMultimedia
import Quickshell
import Caelestia.Config
import qs.components
import qs.components.filedialog
import qs.components.images
import qs.services
import qs.utils

Item {
    id: root

    property string source: Wallpapers.current
    readonly property bool isVideo: Wallpapers.isVideo(source)
    property Image current: one
    property bool completed
    property bool revealSent: false

    // Session-start reveal (wayfire-intro): the compositor keeps the screen
    // behind a black curtain until the desktop is actually worth showing.
    // The moment the wallpaper is on screen is that moment. The plugin
    // ignores repeated calls, so one call per monitor is fine.
    function sendReveal(): void {
        if (revealSent)
            return;
        revealSent = true;
        Quickshell.execDetached(["caelestia-intro-reveal"]);
    }

    onCurrentChanged: {
        if (current || isVideo)
            sendReveal();
    }

    onSourceChanged: {
        if (!source)
            current = null;
        else if (!Wallpapers.isVideo(source)) {
            if (current === one)
                two.update();
            else
                one.update();
        }
    }

    Component.onCompleted: {
        if (source)
            Qt.callLater(() => {
                if (!Wallpapers.isVideo(source))
                    one.update();
                completed = true;
            });
    }

    Loader {
        asynchronous: true
        anchors.fill: parent

        active: root.completed && !root.source

        sourceComponent: StyledRect {
            color: Colours.palette.m3surfaceContainer

            // No wallpaper configured: the "set one now" screen is what the
            // session opens onto, so reveal on it too.
            Component.onCompleted: root.sendReveal()

            Row {
                anchors.centerIn: parent
                spacing: Tokens.spacing.large

                MaterialIcon {
                    text: "sentiment_stressed"
                    color: Colours.palette.m3onSurfaceVariant
                    font.pointSize: Tokens.font.size.extraLarge * 5
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Tokens.spacing.small

                    StyledText {
                        text: qsTr("Wallpaper missing?")
                        color: Colours.palette.m3onSurfaceVariant
                        font.pointSize: Tokens.font.size.extraLarge * 2
                        font.bold: true
                    }

                    StyledRect {
                        implicitWidth: selectWallText.implicitWidth + Tokens.padding.large * 2
                        implicitHeight: selectWallText.implicitHeight + Tokens.padding.small * 2

                        radius: Tokens.rounding.full
                        color: Colours.palette.m3primary

                        FileDialog {
                            id: dialog

                            title: qsTr("Select a wallpaper")
                            filterLabel: qsTr("Media files")
                            filters: Images.validImageExtensions.concat(["*.mp4", "*.webm", "*.mkv", "*.mov", "*.avi"])
                            onAccepted: path => Wallpapers.setWallpaper(path)
                        }

                        StateLayer {
                            radius: parent.radius
                            color: Colours.palette.m3onPrimary
                            onClicked: dialog.open()
                        }

                        StyledText {
                            id: selectWallText

                            anchors.centerIn: parent

                            text: qsTr("Set it now!")
                            color: Colours.palette.m3onPrimary
                            font.pointSize: Tokens.font.size.large
                        }
                    }
                }
            }
        }
    }

    Item {
        id: videoContainer
        anchors.fill: parent
        opacity: isVideo && source ? 1 : 0
        visible: opacity > 0

        Behavior on opacity {
            NumberAnimation {
                duration: 600
                easing.type: Easing.OutQuad
            }
        }

        MediaPlayer {
            id: mediaPlayer
            source: isVideo && root.source ? (root.source.startsWith("file://") ? root.source : "file://" + root.source) : ""
            loops: MediaPlayer.Infinite
            audioOutput: null
            videoOutput: videoOutput

            property bool shouldPlay: isVideo && !Wallpapers.isCovered

            // Pausing while covered is the whole point of the video wallpaper:
            // a paused MediaPlayer stops decoding, so CPU/GPU drop to idle.
            function syncPlayback(): void {
                if (!source) {
                    stop();
                    return;
                }
                if (shouldPlay) {
                    if (playbackState !== MediaPlayer.PlayingState)
                        play();
                    root.sendReveal();
                } else if (playbackState === MediaPlayer.PlayingState) {
                    pause();
                }
            }

            onShouldPlayChanged: syncPlayback()
            onSourceChanged: syncPlayback()

            // The bindings above may settle before their handlers are connected,
            // so the initial state has to be applied explicitly.
            Component.onCompleted: syncPlayback()
        }

        VideoOutput {
            id: videoOutput
            anchors.fill: parent
            fillMode: VideoOutput.PreserveAspectCrop
        }
    }

    Img {
        id: one
        visible: !root.isVideo
    }

    Img {
        id: two
        visible: !root.isVideo
    }

    component Img: CachingImage {
        id: img

        function update(): void {
            if (path === root.source)
                root.current = this;
            else
                path = root.source;
        }

        anchors.fill: parent

        opacity: 0
        scale: Wallpapers.showPreview ? 1 : 0.8

        onStatusChanged: {
            if (status === Image.Ready)
                root.current = this;
        }

        states: State {
            name: "visible"
            when: root.current === img && !root.isVideo

            PropertyChanges {
                img.opacity: 1
                img.scale: 1
            }
        }

        transitions: Transition {
            Anim {
                target: img
                properties: "opacity,scale"
            }
        }
    }
}

