import QtQuick
import qs.services

QtObject {
    id: root

    property string currentName
    property bool hasCurrent

    // Swoosh when a bar popout slides in or out: the window preview on the bar
    // and the status ones (volume, mic, network, bluetooth, battery...). Only
    // on open/close, not when moving between icons while one is already open.
    onHasCurrentChanged: Sounds.slide(false)

    // While true, hover must not (re)open popouts. Used by the task list so
    // that clicking an icon closes the preview and it stays closed during the
    // compositor's minimize/restore animation, even if the pointer moves.
    property bool suppressed: false

    readonly property Timer suppressTimer: Timer {
        interval: 800
        onTriggered: root.suppressed = false
    }

    function suppressBriefly(): void {
        hasCurrent = false;
        suppressed = true;
        suppressTimer.restart();
    }

    signal detachRequested(mode: string)
}
