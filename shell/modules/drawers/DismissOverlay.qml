pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.components

// Fullscreen transparent layer shell window that captures clicks outside panels.
// When a drawer is open, this window is visible (no mask = full window interactive).
// It sits BELOW the drawers window (via z-order within the same layer).
// Any click on the desktop area hits this overlay first and closes the drawer.
PanelWindow {
    id: root

    required property ShellScreen screen
    required property DrawerVisibilities visibilities

    readonly property bool shouldShow: visibilities.launcher || visibilities.session ||
                                       visibilities.sidebar

    visible: shouldShow

    WlrLayershell.namespace: "caelestia-dismiss-overlay"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // No mask property → full window is interactive by default
    color: "transparent"

    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onClicked: {
            root.visibilities.launcher = false;
            root.visibilities.session = false;
            root.visibilities.sidebar = false;
            root.visibilities.dashboard = false;
        }
    }
}
