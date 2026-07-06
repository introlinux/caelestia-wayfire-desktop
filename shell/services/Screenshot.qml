pragma Singleton

import QtQuick
import Quickshell
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

    function take(): void {
        const dir = Paths.screenshotsdir;
        Quickshell.execDetached(["bash", "-c",
            `mkdir -p "${dir}" && grim "${dir}/screenshot_$(date +%Y%m%d_%H-%M-%S).png"`]);
    }

    function takeRegion(): void {
        const dir = Paths.screenshotsdir;
        Quickshell.execDetached(["bash", "-c",
            `mkdir -p "${dir}" && grim -g "$(slurp)" "${dir}/screenshot_$(date +%Y%m%d_%H-%M-%S).png"`]);
    }

    function takeRegionCopy(): void {
        Quickshell.execDetached(["bash", "-c", `slurp | grim -g - - | wl-copy`]);
    }
}
