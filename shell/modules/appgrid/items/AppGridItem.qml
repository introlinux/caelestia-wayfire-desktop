pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Widgets
import Caelestia.Config
import qs.components
import qs.services
import qs.modules.launcher.services

Item {
    id: root

    required property DesktopEntry modelData
    required property var visibilities

    readonly property int itemMargin: Tokens.spacing.small
    readonly property int iconSize: 88

    // GridView no redimensiona el delegate automáticamente al tamaño de celda
    width: GridView.view?.cellWidth ?? 0
    height: GridView.view?.cellHeight ?? 0

    StateLayer {
        anchors.fill: parent
        anchors.margins: root.itemMargin
        radius: Tokens.rounding.normal

        // El m3onSurface por defecto al 8% queda invisible sobre el escritorio
        // oscurecido con m3scrim; aquí el fondo es arbitrario, así que blanco
        // con más peso (igual que el nombre de la app, también blanco fijo)
        color: "white"
        stateOpacity: pressed ? 0.26 : containsMouse ? 0.16 : 0

        onClicked: {
            Apps.launch(root.modelData);
            root.visibilities.appgrid = false;
        }
    }

    IconImage {
        id: icon

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: Tokens.spacing.large

        asynchronous: true
        source: Quickshell.iconPath(root.modelData?.icon, "image-missing")
        implicitSize: root.iconSize
    }

    StyledText {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: icon.bottom
        anchors.topMargin: Tokens.spacing.small

        text: root.modelData?.name ?? ""
        color: "white"
        font.pointSize: Tokens.font.size.normal
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        width: Math.min(implicitWidth, root.width - root.itemMargin * 2)
    }
}
