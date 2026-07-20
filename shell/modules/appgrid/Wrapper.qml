pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.components
import qs.modules.launcher.services

Item {
    id: root

    required property DrawerVisibilities visibilities

    readonly property bool shouldBeActive: visibilities.appgrid

    property real offsetScale: shouldBeActive ? 0 : 1

    visible: offsetScale < 1
    opacity: 1 - offsetScale
    scale: 1 - offsetScale * 0.06

    Component.onCompleted: Qt.callLater(() => Apps) // Load apps on init

    Behavior on offsetScale {
        Anim {
            type: Anim.DefaultSpatial
        }
    }

    Loader {
        id: content

        anchors.fill: parent

        active: root.shouldBeActive || root.visible

        sourceComponent: Content {
            visibilities: root.visibilities
        }
    }
}
