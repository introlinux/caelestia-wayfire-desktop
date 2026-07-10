import QtQuick

QtObject {
    id: root

    property string currentName
    property bool hasCurrent

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
