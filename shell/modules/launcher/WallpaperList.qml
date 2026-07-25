pragma ComponentBehavior: Bound

import "items"
import QtQuick
import Quickshell
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

PathView {
    id: root

    required property StyledTextField search
    required property var visibilities
    required property var panels
    required property var content

    readonly property int itemWidth: Tokens.sizes.launcher.wallpaperWidth * 0.8 + Tokens.padding.larger * 2

    // Deltas de rueda pendientes de completar una muesca
    property int wheelAccumulated: 0

    readonly property int numItems: {
        const screen = (QsWindow.window as QsWindow)?.screen;
        if (!screen)
            return 0;

        // Screen width - 4x outer rounding - 2x max side thickness (cause centered)
        const barMargins = Math.max(Config.border.thickness, panels.bar.implicitWidth);
        let outerMargins = 0;
        if (panels.popouts.hasCurrent && panels.popouts.currentCenter + panels.popouts.nonAnimHeight / 2 > screen.height - content.implicitHeight - Config.border.thickness * 2)
            outerMargins = panels.popouts.nonAnimWidth;
        if ((visibilities.utilities || visibilities.sidebar) && panels.utilities.implicitWidth > outerMargins)
            outerMargins = panels.utilities.implicitWidth;
        const maxWidth = screen.width - Config.border.rounding * 4 - (barMargins + outerMargins) * 2;

        if (maxWidth <= 0)
            return 0;

        const maxItemsOnScreen = Math.floor(maxWidth / itemWidth);
        const visible = Math.min(maxItemsOnScreen, Config.launcher.maxWallpapers, scriptModel.values.length);

        if (visible === 2)
            return 1;
        if (visible > 1 && visible % 2 === 0)
            return visible - 1;
        return visible;
    }

    model: ScriptModel {
        id: scriptModel

        readonly property string search: root.search.text.split(" ").slice(1).join(" ")

        values: Wallpapers.query(search)
        onValuesChanged: root.currentIndex = search ? 0 : values.findIndex(w => w.path === Wallpapers.actualCurrent)
    }

    Component.onCompleted: currentIndex = Wallpapers.list.findIndex(w => w.path === Wallpapers.actualCurrent)
    Component.onDestruction: Wallpapers.stopPreview()

    onCurrentItemChanged: {
        if (currentItem)
            Wallpapers.preview((currentItem as WallpaperItem).modelData.path);
    }

    implicitWidth: Math.min(numItems, count) * itemWidth
    pathItemCount: numItems
    cacheItemCount: 4

    snapMode: PathView.SnapToItem
    preferredHighlightBegin: 0.5
    preferredHighlightEnd: 0.5
    highlightRangeMode: PathView.StrictlyEnforceRange

    delegate: WallpaperItem {
        visibilities: root.visibilities
    }

    // La rueda y el hover de las zonas laterales tienen que capturarse por
    // encima de las miniaturas: cada delegado lleva su propio StateLayer, que es
    // un MouseArea y se queda con los eventos. Todos estos van con
    // `acceptedButtons: Qt.NoButton`, así que los clics siguen bajando hasta la
    // miniatura y solo interceptan lo que les toca.

    // Desplazamiento horizontal de dos dedos (o rueda) para recorrer el carrusel
    MouseArea {
        anchors.fill: parent
        z: 100

        acceptedButtons: Qt.NoButton

        onWheel: event => {
            const d = event.angleDelta;
            const delta = Math.abs(d.x) > Math.abs(d.y) ? d.x : d.y;
            if (delta === 0)
                return;

            // El touchpad manda muchos deltas pequeños: se acumulan hasta
            // completar una muesca (mismo criterio que CustomMouseArea)
            if (Math.sign(delta) !== Math.sign(root.wheelAccumulated))
                root.wheelAccumulated = 0;
            root.wheelAccumulated += delta;

            while (root.wheelAccumulated >= 120) {
                root.decrementCurrentIndex();
                root.wheelAccumulated -= 120;
            }
            while (root.wheelAccumulated <= -120) {
                root.incrementCurrentIndex();
                root.wheelAccumulated += 120;
            }
        }
    }

    ScrollZone {
        step: -1
        anchors.left: parent.left
    }

    ScrollZone {
        step: 1
        anchors.right: parent.right
    }

    // Franja en un lateral que avanza el carrusel mientras el ratón está encima.
    // Vive dentro del panel a propósito: salir del panel lo cierra, como en
    // cualquier otro drawer, así que la navegación tiene que quedar dentro.
    component ScrollZone: MouseArea {
        id: zone

        required property int step

        function scroll(): void {
            if (zone.step < 0)
                root.decrementCurrentIndex();
            else
                root.incrementCurrentIndex();
        }

        width: Math.round(root.itemWidth / 3)
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        z: 99

        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        cursorShape: Qt.PointingHandCursor

        onContainsMouseChanged: {
            if (containsMouse) {
                initialDelay.restart();
            } else {
                initialDelay.stop();
                autoScroll.stop();
            }
        }

        // Un retardo antes del primer paso evita que el carrusel se dispare solo
        // al pasar de largo camino de una miniatura del borde
        Timer {
            id: initialDelay

            interval: 250
            onTriggered: {
                zone.scroll();
                autoScroll.start();
            }
        }

        Timer {
            id: autoScroll

            interval: 400
            repeat: true
            onTriggered: zone.scroll()
        }

        MaterialIcon {
            anchors.centerIn: parent

            text: zone.step < 0 ? "chevron_left" : "chevron_right"
            color: Colours.palette.m3onSurfaceVariant
            font.pointSize: Tokens.font.size.extraLarge
            font.weight: 600

            opacity: zone.containsMouse ? 1 : 0

            Behavior on opacity {
                Anim {}
            }
        }
    }

    path: Path {
        startY: root.height / 2

        PathAttribute {
            name: "z"
            value: 0
        }
        PathLine {
            x: root.width / 2
            relativeY: 0
        }
        PathAttribute {
            name: "z"
            value: 1
        }
        PathLine {
            x: root.width
            relativeY: 0
        }
    }
}
