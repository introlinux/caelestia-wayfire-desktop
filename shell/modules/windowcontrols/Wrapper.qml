pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.services

Item {
    id: root

    required property DrawerVisibilities visibilities

    readonly property bool shouldBeActive: visibilities.windowControls
    property real offsetScale: shouldBeActive ? 0 : 1

    property var targetWindow: null

    onShouldBeActiveChanged: {
        if (shouldBeActive && Hypr.activeToplevel)
            targetWindow = Hypr.activeToplevel;
    }

    visible: offsetScale < 1
    anchors.topMargin: (-implicitHeight - 5) * offsetScale
    implicitHeight: Tokens.padding.large * 2 + buttonsRow.implicitHeight
    implicitWidth: Tokens.padding.large * 2 + buttonsRow.implicitWidth
    opacity: 1 - offsetScale

    Behavior on offsetScale {
        Anim {
            type: Anim.DefaultSpatial
        }
    }

    RowLayout {
        id: buttonsRow

        anchors.centerIn: parent
        spacing: Tokens.spacing.normal

        WinCtrlButton {
            iconName: "remove"
            iconColor: Colours.palette.m3secondary
            onActivated: {
                const win = root.targetWindow ?? Hypr.activeToplevel;
                if (win) win.minimized = true;
            }
        }

        WinCtrlButton {
            iconName: "expand"
            iconColor: Colours.palette.m3primary
            onActivated: {
                const win = root.targetWindow ?? Hypr.activeToplevel;
                if (win) win.maximized = !win.maximized;
            }
        }

        WinCtrlButton {
            iconName: "close"
            iconColor: Colours.palette.m3error
            onActivated: {
                const win = root.targetWindow ?? Hypr.activeToplevel;
                if (win) win.close();
            }
        }
    }

    component WinCtrlButton: StyledRect {
        property alias iconName: icon.text
        property alias iconColor: icon.color
        signal activated

        implicitWidth: icon.implicitWidth + Tokens.padding.small
        implicitHeight: icon.implicitHeight + Tokens.padding.small
        radius: Tokens.rounding.small
        color: ma.containsMouse ? Colours.tPalette.m3surfaceContainerHigh : "transparent"

        MaterialIcon {
            id: icon

            anchors.centerIn: parent
            font.pointSize: Tokens.font.size.large
        }

        MouseArea {
            id: ma

            anchors.fill: parent
            hoverEnabled: true
            onClicked: parent.activated()
        }
    }
}
