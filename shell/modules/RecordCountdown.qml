pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.services

// Fullscreen 3-2-1 countdown shown before a recording starts.
// Triggered over IPC by caelestia-record-wayfire:
//   qs -c caelestia ipc call record countdown 3
Scope {
    id: root

    property int remaining

    function start(seconds: int): void {
        remaining = seconds;
        loader.activeAsync = true;
        tick.restart();
    }

    Timer {
        id: tick

        interval: 1000
        repeat: true
        onTriggered: {
            if (--root.remaining <= 0) {
                stop();
                loader.active = false;
            }
        }
    }

    IpcHandler {
        target: "record"

        function countdown(seconds: int): void {
            root.start(seconds);
        }
    }

    LazyLoader {
        id: loader

        Variants {
            model: Quickshell.screens

            StyledWindow {
                id: win

                required property ShellScreen modelData

                screen: modelData
                name: "record-countdown"
                WlrLayershell.exclusionMode: ExclusionMode.Ignore
                WlrLayershell.layer: WlrLayer.Overlay
                mask: Region {}

                anchors.top: true
                anchors.bottom: true
                anchors.left: true
                anchors.right: true

                StyledRect {
                    anchors.centerIn: parent
                    implicitWidth: 220
                    implicitHeight: 220
                    radius: Tokens.rounding.full
                    color: Qt.alpha(Colours.palette.m3surface, 0.85)

                    StyledText {
                        id: number

                        anchors.centerIn: parent
                        text: Math.max(1, root.remaining)
                        color: Colours.palette.m3onSurface
                        font.pointSize: Tokens.font.size.extraLarge * 3
                        font.bold: true

                        // Pop on every tick
                        onTextChanged: pop.restart()

                        NumberAnimation on scale {
                            id: pop

                            running: true
                            from: 1.3
                            to: 1
                            duration: 350
                            easing.type: Easing.OutBack
                        }
                    }
                }
            }
        }
    }
}
