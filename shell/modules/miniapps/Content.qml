pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Caelestia.Config
import qs.components
import qs.services

Item {
    id: root

    required property DrawerVisibilities visibilities

    // Carpeta abierta (ruta relativa a MiniApps), "" = solo la fila de categorías
    property string currentPath: ""

    // Nº de DropAreas con un drag encima; el Wrapper lo expone a ContentWindow
    // para mantener el panel abierto mientras se arrastra sobre él
    property int dragCount: 0

    property var hoverEntry: null

    readonly property int springDelay: 700
    readonly property real iconSize: 48
    readonly property real cellWidth: 96
    readonly property real cellHeight: iconSize + 46 // hueco para 2 renglones de etiqueta

    function reset(): void {
        currentPath = "";
        hoverEntry = null;
    }

    function goUp(): void {
        const i = currentPath.lastIndexOf("/");
        currentPath = i >= 0 ? currentPath.slice(0, i) : "";
    }

    function urisToPaths(urls: var): var {
        const paths = [];
        for (let i = 0; i < urls.length; i++)
            paths.push(decodeURIComponent(urls[i].toString().replace(/^file:\/\//, "")));
        return paths;
    }

    function runEntry(entry: var, urls: var): void {
        MiniApps.run(entry, urls ? urisToPaths(urls) : []);
        reset();
        visibilities.miniapps = false;
    }

    implicitWidth: layout.implicitWidth + Tokens.padding.large * 2
    implicitHeight: layout.implicitHeight + Tokens.padding.large * 2

    Column {
        id: layout

        x: Tokens.padding.large
        y: Tokens.padding.large
        spacing: Tokens.spacing.normal

        // Interior de la carpeta abierta
        Column {
            visible: root.currentPath !== ""
            spacing: Tokens.spacing.small

            Row {
                spacing: Tokens.spacing.small

                Item {
                    id: backTile

                    implicitWidth: 32
                    implicitHeight: 32

                    Component.onDestruction: {
                        if (backDrop.containsDrag)
                            root.dragCount--;
                    }

                    StyledRect {
                        anchors.fill: parent
                        radius: Tokens.rounding.small
                        color: Colours.palette.m3surfaceContainerHighest
                        opacity: backDrop.containsDrag || backMouse.containsMouse ? 1 : 0

                        Behavior on opacity {
                            Anim {}
                        }
                    }

                    MaterialIcon {
                        anchors.centerIn: parent
                        text: "arrow_back"
                    }

                    MouseArea {
                        id: backMouse

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.goUp()
                    }

                    DropArea {
                        id: backDrop

                        anchors.fill: parent
                        onContainsDragChanged: {
                            root.dragCount += containsDrag ? 1 : -1;
                            if (containsDrag)
                                backSpring.restart();
                            else
                                backSpring.stop();
                        }
                    }

                    Timer {
                        id: backSpring

                        interval: root.springDelay
                        onTriggered: {
                            if (backDrop.containsDrag)
                                root.goUp();
                        }
                    }
                }

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.currentPath.replace(/\//g, " › ")
                    font.pointSize: Tokens.font.size.normal
                    font.weight: Font.Medium
                }
            }

            Grid {
                id: grid

                columns: Math.min(Math.max(gridRepeater.count, 1), 5)
                spacing: Tokens.spacing.small

                Repeater {
                    id: gridRepeater

                    model: MiniApps.entries(root.currentPath)

                    delegate: EntryTile {}
                }
            }
        }

        // Fila de categorías (siempre visible)
        Row {
            id: catRow

            spacing: Tokens.spacing.small

            Repeater {
                model: MiniApps.categories

                delegate: EntryTile {
                    isCategory: true
                }
            }
        }

        // Cartela: resumen del elemento bajo el cursor. Altura fija de 2
        // renglones para que el panel no cambie de tamaño (y los iconos no
        // vibren) según la longitud del texto.
        Item {
            implicitWidth: 0 // No ensancha la columna: el texto se ajusta al ancho del panel
            implicitHeight: Math.ceil(infoMetrics.height) * 2
            width: layout.width

            FontMetrics {
                id: infoMetrics

                font: infoText.font
            }

            StyledText {
                id: infoText

                width: parent.width
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                color: Colours.palette.m3onSurfaceVariant
                font.pointSize: Tokens.font.size.small
                text: root.hoverEntry
                    ? (root.hoverEntry.summary || root.hoverEntry.name)
                    : qsTr("Suelta archivos sobre un script, o haz clic para ejecutarlo sin archivos")
            }
        }
    }

    component EntryTile: Item {
        id: tile

        required property var modelData
        property bool isCategory: false
        readonly property bool navigable: modelData.type === "dir"
        readonly property bool isOpenCategory: isCategory && root.currentPath.startsWith(modelData.rel)

        implicitWidth: root.cellWidth
        implicitHeight: root.cellHeight

        Component.onDestruction: {
            if (tileDrop.containsDrag)
                root.dragCount--;
            if (root.hoverEntry === modelData)
                root.hoverEntry = null;
        }

        StyledRect {
            anchors.fill: parent
            radius: Tokens.rounding.small
            color: Colours.palette.m3surfaceContainerHighest
            opacity: tileDrop.containsDrag ? 1 : tileMouse.containsMouse ? 0.7 : tile.isOpenCategory ? 0.4 : 0

            Behavior on opacity {
                Anim {}
            }
        }

        Column {
            // Anclado arriba (no centrado) para que los iconos queden alineados
            // entre tiles aunque las etiquetas ocupen 1 o 2 renglones
            anchors.top: parent.top
            anchors.topMargin: Tokens.padding.small
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 2

            Item {
                anchors.horizontalCenter: parent.horizontalCenter
                implicitWidth: root.iconSize
                implicitHeight: root.iconSize

                Image {
                    id: iconImg

                    anchors.fill: parent
                    // Icono propio (.DirIcon o Icon= con ruta absoluta) o, para
                    // .desktop, búsqueda del nombre en el tema de iconos del sistema
                    source: tile.modelData.icon
                        ? `file://${tile.modelData.icon}`
                        : tile.modelData.iconName
                            ? Quickshell.iconPath(tile.modelData.iconName, true)
                            : ""
                    sourceSize.width: root.iconSize * 2
                    sourceSize.height: root.iconSize * 2
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    visible: status === Image.Ready
                }

                MaterialIcon {
                    anchors.centerIn: parent
                    visible: iconImg.status !== Image.Ready
                    text: tile.navigable ? "folder" : "terminal"
                    font.pointSize: Tokens.font.size.extraLarge
                }
            }

            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                width: root.cellWidth - Tokens.padding.small * 2
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                maximumLineCount: 2
                elide: Text.ElideRight
                text: tile.modelData.name
                font.pointSize: Tokens.font.size.small
            }
        }

        MouseArea {
            id: tileMouse

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor

            onContainsMouseChanged: {
                if (containsMouse)
                    root.hoverEntry = tile.modelData;
                else if (root.hoverEntry === tile.modelData)
                    root.hoverEntry = null;
            }

            onClicked: {
                if (tile.navigable)
                    root.currentPath = tile.modelData.rel;
                else
                    root.runEntry(tile.modelData, null);
            }
        }

        DropArea {
            id: tileDrop

            anchors.fill: parent

            onContainsDragChanged: {
                root.dragCount += containsDrag ? 1 : -1;
                if (containsDrag) {
                    root.hoverEntry = tile.modelData;
                    // Resorte: las carpetas se abren manteniendo el drag encima
                    if (tile.navigable)
                        tileSpring.restart();
                } else {
                    tileSpring.stop();
                }
            }

            onDropped: drop => {
                if (tile.modelData.type === "dir") {
                    // Soltar sobre una carpeta solo la abre
                    root.currentPath = tile.modelData.rel;
                } else {
                    drop.accept();
                    root.runEntry(tile.modelData, drop.urls);
                }
            }
        }

        Timer {
            id: tileSpring

            interval: root.springDelay
            onTriggered: {
                if (tileDrop.containsDrag)
                    root.currentPath = tile.modelData.rel;
            }
        }
    }
}
