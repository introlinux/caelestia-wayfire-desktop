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
        font.pointSize: Tokens.font.size.small
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        width: Math.min(implicitWidth, root.width - root.itemMargin * 2)
    }
}
