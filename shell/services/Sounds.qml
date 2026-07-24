pragma Singleton

import QtQuick
import Quickshell
import Caelestia.Config

/*
 * UI sound effects.
 *
 * `GlobalConfig.services.systemSounds` is the single master switch for every
 * sound in the desktop: the shell's own effects and the compositor's (the
 * ninjaslash sword swishes). Wayfire's side is pushed over IPC, which only
 * changes the running compositor and does not write wayfire.ini, so the switch
 * is re-applied on startup to keep the shell as the source of truth.
 */
Singleton {
    id: root

    readonly property bool enabled: GlobalConfig.services.systemSounds ?? true

    readonly property string slideBig: `${Quickshell.shellDir}/assets/slide2.mp3`
    readonly property string slideSmall: `${Quickshell.shellDir}/assets/slide1.mp3`

    // PersistentProperties restore the drawer state on startup and on every
    // config reload, which would fire a burst of slide sounds. Stay quiet until
    // the shell has settled.
    property bool _ready: false

    function play(path: string): void {
        if (!enabled)
            return;
        Quickshell.execDetached(["pw-play", path]);
    }

    /*
     * Panels can toggle together (Interactions.qml closes one drawer when
     * another opens, and each screen has its own visibilities object), so
     * coalesce a burst into a single sound, preferring the heavier one.
     */
    function slide(big: bool): void {
        if (!enabled || !_ready)
            return;
        _pending = true;
        if (big)
            _pendingBig = true;
        coalesce.restart();
    }

    property bool _pending: false
    property bool _pendingBig: false

    Timer {
        id: coalesce

        interval: 60
        onTriggered: {
            if (root._pending)
                root.play(root._pendingBig ? root.slideBig : root.slideSmall);
            root._pending = false;
            root._pendingBig = false;
        }
    }

    Timer {
        running: true
        interval: 1500
        onTriggered: root._ready = true
    }

    function syncCompositor(): void {
        Quickshell.execDetached(["caelestia-wayfire-opt", `ninjaslash/sound_enabled=${enabled ? "true" : "false"}`]);
    }

    onEnabledChanged: syncCompositor()
    Component.onCompleted: syncCompositor()
}
