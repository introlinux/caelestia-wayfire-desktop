pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.services

ColumnLayout {
    id: root
    spacing: Tokens.spacing.small

    readonly property var activeToplevel: Hypr.activeToplevel

    // Botón Cerrar
    ControlButton {
        icon: "close"
        color: Colours.palette.m3error
        onClicked: {
            const win = root.activeToplevel;
            if (win) win.close();
        }
    }

    // Botón Maximizar
    ControlButton {
        icon: "expand"
        color: Colours.palette.m3primary
        onClicked: {
            const win = root.activeToplevel;
            if (win) win.maximized = !win.maximized;
        }
    }

    // Botón Minimizar
    ControlButton {
        icon: "remove"
        color: Colours.palette.m3secondary
        onClicked: {
            const win = root.activeToplevel;
            if (win) win.minimized = true;
        }
    }

    component ControlButton: StyledRect {
        property alias icon: iconItem.text
        property alias color: iconItem.color
        signal clicked

        implicitWidth: iconItem.implicitWidth + Tokens.padding.small
        implicitHeight: iconItem.implicitHeight + Tokens.padding.small
        radius: Tokens.rounding.small
        color: mouseArea.containsMouse ? Colours.tPalette.m3surfaceContainerHigh : "transparent"

        MaterialIcon {
            id: iconItem
            anchors.centerIn: parent
            font.pointSize: Tokens.font.size.large
        }

        MouseArea {
            id: mouseArea
            anchors.fill: parent
            hoverEnabled: true
            onClicked: parent.clicked()
        }
    }
}
