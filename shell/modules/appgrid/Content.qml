pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.modules.launcher.services
import qs.modules.appgrid.items

Item {
    id: root

    required property DrawerVisibilities visibilities

    anchors.fill: parent

    readonly property int outerMargin: Tokens.spacing.large * 3 + Config.border.rounding * 2
    readonly property int minCellWidth: 150
    readonly property int cellHeight: 150

    // Clic en hueco vacío cierra la grid, igual que en GNOME/Ubuntu Activities
    MouseArea {
        anchors.fill: parent
        onClicked: root.visibilities.appgrid = false
    }

    StyledRect {
        id: searchWrapper

        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.topMargin: root.outerMargin

        width: 480
        color: Colours.layer(Colours.palette.m3surfaceContainer, 2)
        radius: Tokens.rounding.full

        implicitHeight: Math.max(searchIcon.implicitHeight, search.implicitHeight) + Tokens.padding.large * 2

        MaterialIcon {
            id: searchIcon

            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: Tokens.padding.large

            text: "search"
            color: Colours.palette.m3onSurfaceVariant
        }

        StyledTextField {
            id: search

            anchors.left: searchIcon.right
            anchors.right: parent.right
            anchors.leftMargin: Tokens.spacing.small
            anchors.rightMargin: Tokens.padding.large

            topPadding: Tokens.padding.larger
            bottomPadding: Tokens.padding.larger

            placeholderText: "Buscar aplicaciones…"

            onTextChanged: grid.currentIndex = 0

            onAccepted: {
                const item = grid.currentItem;
                if (item) {
                    Apps.launch(item.modelData);
                    root.visibilities.appgrid = false;
                }
            }

            Keys.onUpPressed: grid.moveCurrentIndexUp()
            Keys.onDownPressed: grid.moveCurrentIndexDown()
            Keys.onLeftPressed: grid.moveCurrentIndexLeft()
            Keys.onRightPressed: grid.moveCurrentIndexRight()

            Keys.onEscapePressed: root.visibilities.appgrid = false

            Component.onCompleted: forceActiveFocus()

            Connections {
                function onAppgridChanged(): void {
                    if (!root.visibilities.appgrid) {
                        search.text = "";
                    } else {
                        search.forceActiveFocus();
                    }
                }

                target: root.visibilities
            }

            Window.onActiveChanged: {
                if (Window.active && root.visibilities.appgrid) {
                    search.forceActiveFocus();
                }
            }
        }
    }

    StyledText {
        anchors.centerIn: grid
        visible: grid.count === 0
        text: "Sin resultados"
        color: Colours.palette.m3onSurfaceVariant
        font.pointSize: Tokens.font.size.large
    }

    GridView {
        id: grid

        readonly property int columns: Math.max(4, Math.floor(width / root.minCellWidth))

        anchors.top: searchWrapper.bottom
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: Tokens.spacing.large
        anchors.margins: root.outerMargin

        clip: true

        cellWidth: width / columns
        cellHeight: root.cellHeight

        model: Apps.search(search.text)

        delegate: AppGridItem {
            visibilities: root.visibilities
        }

        StyledScrollBar.vertical: StyledScrollBar {
            flickable: grid
        }
    }
}
