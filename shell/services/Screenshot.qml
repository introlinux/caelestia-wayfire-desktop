pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.components.containers
import qs.services
import qs.utils

Singleton {
    id: root

    // Timer lives here (singleton) so it survives panel close
    Timer {
        id: shootTimer

        property int mode: 0

        interval: 300
        onTriggered: {
            if (mode === 0)
                root.take();
            else if (mode === 1)
                root.takeRegion();
            else
                root.takeRegionCopy();
        }
    }

    function shoot(m): void {
        shootTimer.mode = m;
        shootTimer.restart();
    }

    function newPath(): string {
        return `${Paths.screenshotsdir}/screenshot_${Qt.formatDateTime(new Date(), "yyyyMMdd_HH-mm-ss")}.png`;
    }

    function take(): void {
        const path = newPath();
        spawn(["bash", "-c", `mkdir -p "${Paths.screenshotsdir}" && grim "${path}"`], path, false);
    }

    // Dim the screen while slurp waits; a bare slurp only changes the cursor
    // and it is easy to not realise it is running.
    // </dev/null is load-bearing: with a non-tty stdin (quickshell gives its
    // children a never-closing pipe) slurp blocks reading boxes from stdin
    // before even connecting to the compositor.
    readonly property string slurpCmd: `slurp -d -w 2 -b '#00000066' -c '#ffffffdd' < /dev/null`

    function takeRegion(): void {
        const path = newPath();
        spawn(["bash", "-c", `mkdir -p "${Paths.screenshotsdir}" && grim -g "$(${slurpCmd})" "${path}"`], path, true);
    }

    function takeRegionCopy(): void {
        spawn(["bash", "-c", `${slurpCmd} | grim -g - - | wl-copy`], "", true);
    }

    // One process per shot: a slurp left waiting must not block later shots
    function spawn(cmd: list<string>, path: string, interactive: bool): void {
        shotProc.createObject(root, {
            command: cmd,
            path: path,
            interactive: interactive
        });
    }

    // Camera sound + flash; notification says where the file went
    function feedback(path: string): void {
        flash.activeAsync = true;
        flashOff.restart();
        Sounds.play(`${Quickshell.shellDir}/assets/sound-camera.mp3`);
        if (path)
            Quickshell.execDetached(["notify-send", "-a", "caelestia-shell", "-i", path, "Screenshot taken", `Saved in ${Paths.shortenHome(path)}`]);
        else
            Quickshell.execDetached(["notify-send", "-a", "caelestia-shell", "Screenshot taken", "Screenshot copied to clipboard"]);
    }

    Component {
        id: shotProc

        Process {
            id: proc

            property string path
            property bool interactive

            running: true

            onExited: code => { // qmllint disable signal-handler-parameters
                if (code === 0)
                    root.feedback(path);
                else if (!interactive)
                    // Cancelling slurp (interactive) is not an error; a failed grim is
                    Quickshell.execDetached(["notify-send", "-a", "caelestia-shell", "-u", "critical", "Screenshot failed", "grim exited with an error"]);
                proc.destroy();
            }
        }
    }

    Timer {
        id: flashOff

        interval: 450
        onTriggered: flash.active = false
    }

    LazyLoader {
        id: flash

        Variants {
            model: Quickshell.screens

            StyledWindow {
                id: win

                required property ShellScreen modelData

                screen: modelData
                name: "screenshot-flash"
                WlrLayershell.exclusionMode: ExclusionMode.Ignore
                WlrLayershell.layer: WlrLayer.Overlay
                mask: Region {}

                anchors.top: true
                anchors.bottom: true
                anchors.left: true
                anchors.right: true

                Rectangle {
                    anchors.fill: parent
                    color: "white"
                    opacity: 0

                    Component.onCompleted: fade.start()

                    NumberAnimation on opacity {
                        id: fade

                        running: false
                        from: 0.75
                        to: 0
                        duration: 400
                        easing.type: Easing.OutQuad
                    }
                }
            }
        }
    }
}
