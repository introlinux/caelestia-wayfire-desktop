pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Caelestia.Blobs
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.services
import qs.modules.bar

StyledWindow {
    id: root

    readonly property alias bar: bar
    readonly property alias interactionWrapper: interactions
    readonly property alias visibilities: visibilities

    readonly property bool hasFullscreen: Hypr.activeToplevel?.fullscreen ?? false
    property real borderThickness: hasFullscreen ? 0 : contentItem.Config.border.thickness
    readonly property real borderLayoutThickness: hasFullscreen ? 0 : contentItem.Config.border.thickness
    property real borderRounding: hasFullscreen ? 0 : contentItem.Config.border.rounding
    property real shadowOpacity: hasFullscreen ? 0 : 0.7

    readonly property int dragMaskPadding: {
        if (panels.popouts.isDetached)
            return 0;

        if (Hypr.toplevels.values.length > 0)
            return 0;

        const thresholds = [];
        for (const panel of ["dashboard", "launcher", "session", "sidebar"])
            if (contentItem.Config[panel].enabled)
                thresholds.push(contentItem.Config[panel].dragThreshold);
        return Math.max(...thresholds);
    }

    onHasFullscreenChanged: {
        visibilities.launcher = false;
        visibilities.session = false;
        visibilities.dashboard = false;
        visibilities.appgrid = false;
    }

    name: "drawers"
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: {
        if (visibilities.launcher || visibilities.session || visibilities.appgrid)
            return WlrKeyboardFocus.Exclusive;
        else if (panels.dashboard.needsKeyboard)
            return WlrKeyboardFocus.OnDemand;
        else
            return WlrKeyboardFocus.None;
    }

    Regions {
        id: regions
        bar: bar
        panels: panels
        win: root
    }

    mask: regions

    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true

    Behavior on borderThickness {
        Anim {
            type: Anim.DefaultSpatial
        }
    }

    Behavior on borderRounding {
        Anim {
            type: Anim.DefaultSpatial
        }
    }

    Behavior on shadowOpacity {
        Anim {
            type: Anim.DefaultSpatial
        }
    }

    // Click-outside-to-close: handled by LauncherDismissOverlay in Drawers.qml

    StyledRect {
        anchors.fill: parent
        opacity: (visibilities.session && Config.session.enabled) || visibilities.appgrid ? 0.5 : 0
        color: Colours.palette.m3scrim

        Behavior on opacity {
            Anim {}
        }
    }

    Item {
        anchors.fill: parent
        opacity: Colours.transparency.enabled ? Colours.transparency.base : 1
        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            blurMax: 15
            shadowColor: Qt.alpha(Colours.palette.m3shadow, Math.max(0, root.shadowOpacity))
        }

        BlobGroup {
            id: blobGroup

            color: Colours.palette.m3surface
            smoothing: root.contentItem.Config.border.smoothing

            Behavior on color {
                CAnim {}
            }
        }

        BlobInvertedRect {
            anchors.fill: parent
            anchors.margins: -50 // Make border thicker to smooth out bulge from closed drawers
            group: blobGroup
            radius: root.borderRounding
            borderLeft: bar.implicitWidth - anchors.margins
            borderRight: root.borderThickness - anchors.margins
            borderTop: root.borderThickness - anchors.margins
            borderBottom: root.borderThickness - anchors.margins
        }

        PanelBg {
            id: dashBg

            panel: panels.dashboard
            deformAmount: 0.1
        }

        PanelBg {
            id: launcherBg

            panel: panels.launcher
            deformAmount: 0.1
        }

        PanelBg {
            id: miniappsBg

            panel: panels.miniapps
            deformAmount: 0.1
        }

        PanelBg {
            id: sessionBg

            panel: panels.sessionWrapper
            deformAmount: 0.2
            x: panels.sessionWrapper.x + panels.session.x + bar.implicitWidth
            implicitWidth: panels.session.width
        }

        PanelBg {
            id: sidebarBg

            panel: panels.sidebar
            deformAmount: 0.03
            implicitHeight: panel.height * (1 / rawDeformMatrix.m22) + 2
            exclude: panels.sidebar.offsetScale > 0.08 ? [] : [utilsBg]
            bottomLeftRadius: Math.max(0, Math.min(1, panels.sidebar.offsetScale / 0.3)) * radius
        }

        PanelBg {
            id: osdBg

            panel: panels.osdWrapper
            deformAmount: 0.25
            x: panels.osdWrapper.x + panels.osd.x + bar.implicitWidth
            implicitWidth: panels.osd.width
        }

        PanelBg {
            id: notifsBg

            panel: panels.notifications
        }

        PanelBg {
            id: utilsBg

            panel: panels.utilities
            deformAmount: panels.sidebar.visible ? 0.1 : 0.15
            exclude: panels.sidebar.offsetScale > 0.08 ? [] : [sidebarBg]
            topLeftRadius: Math.max(0, Math.min(1, panels.sidebar.offsetScale / 0.3)) * radius
        }

        PanelBg {
            id: winControlsBg

            panel: panels.windowControls
            deformAmount: 0.15
        }

        PanelBg {
            id: popoutBg

            // Extra width to prevent vertical movement deformation partially detaching panel from bar
            property real extraWidth: panels.popouts.isDetached ? 0 : 0.2

            panel: panels.popoutsWrapper
            deformAmount: panels.popouts.isDetached ? 0.05 : panels.popouts.hasCurrent ? 0.15 : 0.1
            x: panels.popoutsWrapper.x + panels.popouts.x + bar.implicitWidth - panels.popouts.width * extraWidth
            implicitWidth: panels.popouts.width * (1 + extraWidth)

            Behavior on extraWidth {
                Anim {
                    type: Anim.DefaultSpatial
                }
            }
        }
    }

    // Apertura del dock MiniApps durante un drag externo: los MouseArea no
    // reciben eventos mientras se arrastra (solo los DropArea), así que esta
    // franja invisible en la esquina inferior izquierda detecta el drag y
    // despliega el panel. Mientras algún DropArea (este o los del contenido)
    // tenga el drag encima el panel sigue abierto; al perderlo todos, un
    // temporizador de gracia lo cierra (cubre el salto entre DropAreas).
    readonly property bool miniappsDragActive: miniappsDragTrigger.containsDrag || panels.miniapps.dragHovered

    onMiniappsDragActiveChanged: {
        if (miniappsDragActive) {
            miniappsCloseTimer.stop();
            visibilities.miniapps = true;
        } else {
            miniappsCloseTimer.restart();
        }
    }

    Timer {
        id: miniappsCloseTimer

        interval: 400
        onTriggered: {
            if (!root.miniappsDragActive)
                visibilities.miniapps = false;
        }
    }

    DropArea {
        id: miniappsDragTrigger

        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.leftMargin: bar.clampedWidth
        width: Math.max(260, panels.miniapps.width)
        height: root.contentItem.Config.border.clampedThickness + panels.miniapps.height * (1 - panels.miniapps.offsetScale)

        // Soltar en el fondo del dock no hace nada: cerrar
        onDropped: visibilities.miniapps = false
    }

    DrawerVisibilities {
        id: visibilities

        Component.onCompleted: Visibilities.load(root.screen, this)
    }

    Interactions {
        id: interactions

        screen: root.screen
        popouts: panels.popouts
        visibilities: visibilities
        panels: panels
        bar: bar
        borderThickness: root.borderLayoutThickness
        fullscreen: root.hasFullscreen
        miniappsDragActive: root.miniappsDragActive

        Panels {
            id: panels

            screen: root.screen
            visibilities: visibilities
            bar: bar
            borderThickness: root.borderThickness

            utilities.horizontalStretch: (sidebarBg.rawDeformMatrix.m11 - 1) / 2 + 1
            utilities.deformMatrix: utilsBg.rawDeformMatrix

            dashboard.transform: Matrix4x4 {
                matrix: dashBg.deformMatrix
            }
            launcher.transform: Matrix4x4 {
                matrix: launcherBg.deformMatrix
            }
            miniapps.transform: Matrix4x4 {
                matrix: miniappsBg.deformMatrix
            }
            session.transform: Matrix4x4 {
                matrix: sessionBg.deformMatrix
            }
            sidebar.transform: Matrix4x4 {
                matrix: sidebarBg.deformMatrix
            }
            osd.transform: Matrix4x4 {
                matrix: osdBg.deformMatrix
            }
            notifications.transform: Matrix4x4 {
                matrix: notifsBg.deformMatrix
            }
            utilities.transform: Matrix4x4 {
                matrix: utilsBg.deformMatrix
            }
            popouts.transform: Matrix4x4 {
                matrix: popoutBg.deformMatrix
            }
            windowControls.transform: Matrix4x4 {
                matrix: winControlsBg.deformMatrix
            }
        }

        BarWrapper {
            id: bar

            anchors.top: parent.top
            anchors.bottom: parent.bottom

            screen: root.screen
            visibilities: visibilities
            popouts: panels.popouts

            fullscreen: root.hasFullscreen

            Component.onCompleted: Visibilities.bars.set(root.screen, this)
        }
    }

    component PanelBg: BlobRect {
        required property Item panel
        property real deformAmount: 0.15

        group: blobGroup
        x: panel.x + bar.implicitWidth
        y: panel.y + root.borderThickness
        implicitWidth: panel.width
        implicitHeight: panel.height
        radius: Tokens.rounding.large
        deformScale: (deformAmount * Config.appearance.deformScale) / 10000
    }
}
