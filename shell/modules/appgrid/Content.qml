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

    // Oscurecimiento extra para que los iconos resalten sobre el escritorio
    // (el blur con ScreencopyView crashea quickshell y con grim aparecía
    // después que los iconos — descartado, ver notas)
    StyledRect {
        anchors.fill: parent
        color: Colours.palette.m3scrim
        opacity: 0.4
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
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Tokens.spacing.small
            anchors.rightMargin: Tokens.padding.large

            topPadding: Tokens.padding.larger
            bottomPadding: Tokens.padding.larger

            font.pointSize: Tokens.font.size.larger

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
            id: gridScroll

            flickable: grid
        }
    }

    // Clic fuera de los iconos y de la búsqueda cierra la grid, igual que en
    // GNOME/Ubuntu Activities. Va por encima de todo porque el GridView es un
    // Flickable y se tragaba los clics en los huecos entre celdas; cuando el
    // punto sí cae sobre algo pulsable dejamos pasar el evento (accepted =
    // false) para no robarle el clic al delegado ni a la caja de búsqueda.
    MouseArea {
        id: dismissArea

        anchors.fill: parent

        function inItem(item: Item, x: real, y: real): bool {
            if (!item || item.width <= 0 || item.height <= 0)
                return false;
            const p = mapToItem(item, x, y);
            return p.x >= 0 && p.y >= 0 && p.x < item.width && p.y < item.height;
        }

        function isClickable(x: real, y: real): bool {
            if (inItem(searchWrapper, x, y) || inItem(gridScroll, x, y))
                return true;

            if (!inItem(grid, x, y))
                return false;

            // Coordenadas dentro del contenido del GridView, no del viewport
            const p = mapToItem(grid, x, y);
            const cx = p.x + grid.contentX;
            const cy = p.y + grid.contentY;
            const item = grid.itemAt(cx, cy);
            if (!item)
                return false;

            // Solo cuenta el área de la StateLayer, no el margen de la celda
            const m = item.itemMargin;
            const lx = cx - item.x;
            const ly = cy - item.y;
            return lx >= m && ly >= m && lx < item.width - m && ly < item.height - m;
        }

        onPressed: event => event.accepted = !isClickable(event.x, event.y)
        onClicked: root.visibilities.appgrid = false
    }
}
