import QtQuick
import QtQuick.Controls
import Quickshell
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.modules.bar as Bar
import qs.modules.bar.popouts as BarPopouts

CustomMouseArea {
    id: root

    required property ShellScreen screen
    required property BarPopouts.Wrapper popouts
    required property DrawerVisibilities visibilities
    required property Panels panels
    required property Bar.BarWrapper bar
    required property real borderThickness
    required property bool fullscreen

    // True mientras un drag externo mantiene abierto el dock MiniApps
    // (lo gestiona ContentWindow); bloquea el cierre por hover.
    property bool miniappsDragActive

    property point dragStart
    property bool dashboardShortcutActive
    property bool launcherShortcutActive
    property bool osdShortcutActive
    property bool utilitiesShortcutActive
    property bool windowControlsShortcutActive

    function withinPanelHeight(panel: Item, x: real, y: real): bool {
        const panelY = root.borderThickness + panel.y;
        return y >= panelY - Config.border.rounding && y <= panelY + panel.height + Config.border.rounding;
    }

    function withinPanelWidth(panel: Item, x: real, y: real): bool {
        const panelX = bar.implicitWidth + panel.x;
        return x >= panelX - Config.border.rounding && x <= panelX + panel.width + Config.border.rounding;
    }

    function inLeftPanel(panel: Item, x: real, y: real): bool {
        return x < bar.implicitWidth + panel.x + panel.width && withinPanelHeight(panel, x, y);
    }

    function inRightPanel(panel: Item, x: real, y: real): bool {
        return x > Math.min(width - Config.border.minThickness, bar.implicitWidth + panel.x) && withinPanelHeight(panel, x, y);
    }

    function inTopPanel(panel: Item, x: real, y: real): bool {
        const panelHeight = panel.height * (1 - (panel.offsetScale ?? 0)); // qmllint disable missing-property
        return y < Config.border.minThickness + panelHeight && withinPanelWidth(panel, x, y);
    }

    function inBottomPanel(panel: Item, x: real, y: real, isCorner = false): bool {
        const panelHeight = panel.height * (1 - (panel.offsetScale ?? 0)); // qmllint disable missing-property
        return y > height - Config.border.minThickness - panelHeight - (isCorner ? Config.border.rounding : 0) && withinPanelWidth(panel, x, y);
    }

    // Edge-only trigger when hidden; full panel size once open (avoids the race where the
    // animated zone grows slower than the mouse moves into the opening panel).
    function inOsdArea(x: real, y: real): bool {
        const panelWidth = (panels.osd.offsetScale ?? 1) < 1 ? panels.osdWrapper.width : 0;
        return x > width - Config.border.minThickness - panelWidth && withinPanelHeight(panels.osdWrapper, x, y);
    }

    function inMiniAppsArea(x: real, y: real): bool {
        const p = panels.miniapps;
        const panelHeight = (p.offsetScale ?? 1) < 1 ? p.height : 0; // qmllint disable missing-property
        return y > height - Config.border.minThickness - panelHeight && x > bar.implicitWidth && x < bar.implicitWidth + p.x + p.width + Config.border.rounding;
    }

    function inLauncherArea(x: real, y: real): bool {
        const panelHeight = (panels.launcher.offsetScale ?? 1) < 1 ? panels.launcher.height : 0; // qmllint disable missing-property
        return y > height - Config.border.minThickness - panelHeight && withinPanelWidth(panels.launcher, x, y);
    }

    // Edge-only trigger when hidden (last pixels of the frame, not the whole
    // rounded corner); full panel size once open — same pattern as the OSD
    // and the launcher.
    function inUtilitiesArea(x: real, y: real): bool {
        const panelHeight = (panels.utilities.offsetScale ?? 1) < 1 ? panels.utilities.height : 0; // qmllint disable missing-property
        return y > height - Config.border.minThickness - panelHeight && withinPanelWidth(panels.utilities, x, y);
    }

    function onWheel(event: WheelEvent): void {
        if (fullscreen)
            return;
        if (event.x < bar.implicitWidth) {
            bar.handleWheel(event.y, event.angleDelta);
        }
    }

    anchors.fill: parent
    acceptedButtons: fullscreen ? Qt.NoButton : Qt.AllButtons
    hoverEnabled: !fullscreen

    onPressed: event => {
        dragStart = Qt.point(event.x, event.y)
    }
    onContainsMouseChanged: {
        if (!containsMouse) {
            // Only hide if not activated by shortcut
            if (!osdShortcutActive) {
                visibilities.osd = false;
                root.panels.osd.hovered = false;
            }

            dashboardShowTimer.stop();
            if (!dashboardShortcutActive)
                visibilities.dashboard = false;

            if (!utilitiesShortcutActive)
                visibilities.utilities = false;

            if (!windowControlsShortcutActive)
                visibilities.windowControls = false;

            if (Config.launcher.showOnHover && !launcherShortcutActive)
                visibilities.launcher = false;

            if (!miniappsDragActive && visibilities.miniapps && !miniappsHideTimer.running)
                miniappsHideTimer.restart();

            if (!popouts.currentName.startsWith("traymenu") || ((popouts.current as StackView)?.depth ?? 0) <= 1) {
                popouts.hasCurrent = false;
                bar.closeTray();
            }

            if (Config.bar.showOnHover)
                bar.isHovered = false;
        }
    }

    onPositionChanged: event => {
        if (popouts.isDetached)
            return;

        const x = event.x;
        const y = event.y;
        const dragX = x - dragStart.x;
        const dragY = y - dragStart.y;

        // Show bar in non-exclusive mode on hover
        if (!visibilities.bar && Config.bar.showOnHover && x < bar.clampedWidth)
            bar.isHovered = true;

        // Show/hide bar on drag
        if (pressed && dragStart.x < bar.clampedWidth) {
            if (dragX > Config.bar.dragThreshold)
                visibilities.bar = true;
            else if (dragX < -Config.bar.dragThreshold)
                visibilities.bar = false;
        }

        if (panels.sidebar.offsetScale === 1) {
            // Show osd on hover
            const showOsd = inOsdArea(x, y);

            // Always update visibility based on hover if not in shortcut mode
            if (!osdShortcutActive) {
                visibilities.osd = showOsd;
                root.panels.osd.hovered = showOsd;
            } else if (showOsd) {
                // If hovering over OSD area while in shortcut mode, transition to hover control
                osdShortcutActive = false;
                root.panels.osd.hovered = true;
            }

            const showSidebar = pressed && dragStart.x > Math.min(width - Config.border.minThickness, bar.implicitWidth + panels.sidebar.x);

            // Show/hide session on drag
            if (pressed && inRightPanel(panels.sessionWrapper, dragStart.x, dragStart.y) && withinPanelHeight(panels.sessionWrapper, x, y)) {
                if (dragX < -Config.session.dragThreshold)
                    visibilities.session = true;
                else if (dragX > Config.session.dragThreshold)
                    visibilities.session = false;

                // Show sidebar on drag if in session area and session is nearly fully visible
                if (showSidebar && panels.session.offsetScale <= 0 && dragX < -Config.sidebar.dragThreshold)
                    visibilities.sidebar = true;
            } else if (showSidebar && dragX < -Config.sidebar.dragThreshold) {
                // Show sidebar on drag if not in session area
                visibilities.sidebar = true;
            }
        } else {
            const outOfSidebar = x < width - panels.sidebar.width * (1 - panels.sidebar.offsetScale);
            // Show osd on hover
            const showOsd = outOfSidebar && inOsdArea(x, y);

            // Always update visibility based on hover if not in shortcut mode
            if (!osdShortcutActive) {
                visibilities.osd = showOsd;
                root.panels.osd.hovered = showOsd;
            } else if (showOsd) {
                // If hovering over OSD area while in shortcut mode, transition to hover control
                osdShortcutActive = false;
                root.panels.osd.hovered = true;
            }

            // Show/hide session on drag
            if (pressed && outOfSidebar && inRightPanel(panels.sessionWrapper, dragStart.x, dragStart.y) && withinPanelHeight(panels.sessionWrapper, x, y)) {
                if (dragX < -Config.session.dragThreshold)
                    visibilities.session = true;
                else if (dragX > Config.session.dragThreshold)
                    visibilities.session = false;
            }

            // Hide sidebar on drag
            if (pressed && inRightPanel(panels.sidebar, dragStart.x, 0) && dragX > Config.sidebar.dragThreshold)
                visibilities.sidebar = false;
        }

        // Show launcher on hover: opens touching the bottom edge, stays while the cursor
        // is inside the deployed panel, hides as soon as it leaves (same pattern as dashboard)
        if (Config.launcher.showOnHover) {
            const showLauncher = inLauncherArea(x, y);
            if (!launcherShortcutActive) {
                visibilities.launcher = showLauncher;
            } else if (showLauncher) {
                // If hovering over launcher area while in shortcut mode, transition to hover control
                launcherShortcutActive = false;
            }
        } else if (pressed && inBottomPanel(panels.launcher, dragStart.x, dragStart.y) && withinPanelWidth(panels.launcher, x, y)) {
            if (dragY < -Config.launcher.dragThreshold)
                visibilities.launcher = true;
            else if (dragY > Config.launcher.dragThreshold)
                visibilities.launcher = false;
        }

        // Show miniapps dock on hover (bottom-left corner); during a drag the
        // visibility is driven by ContentWindow's DropAreas instead. Closing is
        // delayed: when navigating into a folder with fewer items the panel
        // shrinks and can leave the pointer outside — the grace period lets
        // the user re-enter before it hides.
        if (!miniappsDragActive) {
            if (inMiniAppsArea(x, y)) {
                // Exclusión mutua con los popouts de la barra: en la esquina
                // inferior-izquierda se solapan. Los popouts se cierran al
                // entrar aquí, salvo un submenú de tray abierto, que se
                // respeta (y entonces MiniApps no se abre encima).
                const deepTray = popouts.currentName.startsWith("traymenu") && ((popouts.current as StackView)?.depth ?? 0) > 1;
                if (popouts.hasCurrent && !deepTray) {
                    popouts.hasCurrent = false;
                    bar.closeTray();
                }
                // También exclusión con el launcher: si sigue visible (modo
                // atajo, o hover en la franja donde ambas zonas se rozan) no
                // se abre MiniApps encima. El cierre por hover del launcher
                // ya ha corrido en este mismo evento, unas líneas más arriba.
                if (!popouts.hasCurrent && !visibilities.launcher) {
                    miniappsHideTimer.stop();
                    visibilities.miniapps = true;
                }
            } else if (visibilities.miniapps && !miniappsHideTimer.running) {
                miniappsHideTimer.restart();
            }
        }

        // Show dashboard on hover. Opening is dwell-gated: the top edge is a
        // heavily trafficked zone (browser tabs live just under it) and an
        // instant hover-open fired constantly by accident — the pointer must
        // rest in the strip for dashboardShowTimer's interval before the
        // panel deploys. Closing stays immediate.
        const showDashboard = Config.dashboard.showOnHover && inTopPanel(panels.dashboard, x, y) && !visibilities.appgrid;

        if (!dashboardShortcutActive) {
            if (showDashboard) {
                if (!visibilities.dashboard && !dashboardShowTimer.running)
                    dashboardShowTimer.restart();
            } else {
                dashboardShowTimer.stop();
                visibilities.dashboard = false;
            }
        } else if (showDashboard) {
            // If hovering over dashboard area while in shortcut mode, transition to hover control
            dashboardShortcutActive = false;
        }

        // Show window controls on hover (top-right corner).
        // When hidden (offsetScale=1): edge-only 2px trigger.
        // When opening/open (offsetScale<1): use full implicitHeight to avoid a race condition
        // where the trigger zone shrinks faster than the panel can open as the mouse moves down.
        const wcFullHeight = panels.windowControls.implicitHeight;
        const isWcOpen = (panels.windowControls.offsetScale ?? 1) < 1;
        const showWindowControls =
            y < Config.border.minThickness + (isWcOpen ? wcFullHeight : 0) &&
            withinPanelWidth(panels.windowControls, x, y);

        if (!windowControlsShortcutActive) {
            visibilities.windowControls = showWindowControls;
        } else if (showWindowControls) {
            windowControlsShortcutActive = false;
        }

        // Show/hide dashboard on drag (for touchscreen devices)
        if (pressed && inTopPanel(panels.dashboard, dragStart.x, dragStart.y) && withinPanelWidth(panels.dashboard, x, y)) {
            if (dragY > Config.dashboard.dragThreshold)
                visibilities.dashboard = true;
            else if (dragY < -Config.dashboard.dragThreshold)
                visibilities.dashboard = false;
        }

        // Show utilities on hover. Exclusión con el launcher, su vecino de la
        // izquierda: si sigue visible (modo atajo, o la franja donde ambas
        // zonas se rozan) utilities no se abre encima. El cierre por hover
        // del launcher ya ha corrido en este mismo evento, más arriba.
        const showUtilities = inUtilitiesArea(x, y) && !visibilities.launcher;

        // Always update visibility based on hover if not in shortcut mode
        if (!utilitiesShortcutActive) {
            visibilities.utilities = showUtilities;
        } else if (showUtilities) {
            // If hovering over utilities area while in shortcut mode, transition to hover control
            utilitiesShortcutActive = false;
        }

        // Show popouts on hover
        if (x < bar.implicitWidth) {
            bar.checkPopout(y);
        } else if ((!popouts.currentName.startsWith("traymenu") || ((popouts.current as StackView)?.depth ?? 0) <= 1) && !inLeftPanel(panels.popoutsWrapper, x, y)) {
            popouts.hasCurrent = false;
            bar.closeTray();
        }

        // Exclusión mutua (sentido inverso): con un popout abierto y el
        // puntero fuera de la zona MiniApps, éste se cierra al instante en
        // vez de esperar la gracia de 800ms del timer.
        if (popouts.hasCurrent && visibilities.miniapps && !miniappsDragActive && !inMiniAppsArea(x, y)) {
            miniappsHideTimer.stop();
            visibilities.miniapps = false;
        }
    }

    // Estancia mínima antes de desplegar el dashboard. Al disparar se
    // recomprueba la posición, con containsMouse de guardia: mouseX/Y se
    // congelan al salir de la máscara de input y sin él un roce fugaz por el
    // borde (rumbo a las pestañas) abriría el panel igualmente.
    Timer {
        id: dashboardShowTimer

        interval: 350
        onTriggered: {
            if (root.containsMouse && !root.dashboardShortcutActive &&
                    root.inTopPanel(root.panels.dashboard, root.mouseX, root.mouseY))
                root.visibilities.dashboard = true;
        }
    }

    // Cierre incondicional: si el puntero vuelve al área antes de expirar, el
    // movimiento genera eventos que paran el timer. No se recomprueba la
    // posición aquí porque mouseX/Y se congelan al salir de la máscara de input.
    Timer {
        id: miniappsHideTimer

        interval: 800
        onTriggered: {
            if (!root.miniappsDragActive)
                root.visibilities.miniapps = false;
        }
    }

    // Monitor individual visibility changes
    Connections {
        function onLauncherChanged() {
            if (!root.visibilities.launcher) {
                root.launcherShortcutActive = false;
                root.dashboardShortcutActive = false;
                root.osdShortcutActive = false;
                root.utilitiesShortcutActive = false;

                // Also hide dashboard and OSD if they're not being hovered
                const inDashboardArea = root.inTopPanel(root.panels.dashboard, root.mouseX, root.mouseY);
                const hoveringOsd = root.inOsdArea(root.mouseX, root.mouseY);

                if (!inDashboardArea) {
                    root.visibilities.dashboard = false;
                }
                if (!hoveringOsd) {
                    root.visibilities.osd = false;
                    root.panels.osd.hovered = false;
                }
            } else {
                // Launcher became visible: if not triggered from the bottom edge, treat as shortcut
                if (!root.inLauncherArea(root.mouseX, root.mouseY))
                    root.launcherShortcutActive = true;

                // Exclusión con MiniApps: el launcher que se abre (por hover
                // o por atajo) cierra el dock al instante, sin la gracia de
                // 800ms del timer.
                if (root.visibilities.miniapps && !root.miniappsDragActive) {
                    miniappsHideTimer.stop();
                    root.visibilities.miniapps = false;
                }

                // Y con utilities, su vecino de la derecha
                if (root.visibilities.utilities)
                    root.visibilities.utilities = false;

                // Y con la app grid, que ocupa toda la pantalla
                if (root.visibilities.appgrid)
                    root.visibilities.appgrid = false;
            }
        }

        function onDashboardChanged() {
            if (root.visibilities.dashboard) {
                // Dashboard became visible, immediately check if this should be shortcut mode
                const inDashboardArea = root.inTopPanel(root.panels.dashboard, root.mouseX, root.mouseY);
                if (!inDashboardArea) {
                    root.dashboardShortcutActive = true;
                }

                // Exclusión con la app grid, que ocupa toda la pantalla
                if (root.visibilities.appgrid)
                    root.visibilities.appgrid = false;
            } else {
                // Dashboard hidden, clear shortcut flag
                root.dashboardShortcutActive = false;
            }
        }

        function onOsdChanged() {
            if (root.visibilities.osd) {
                // OSD became visible, immediately check if this should be shortcut mode
                if (!root.inOsdArea(root.mouseX, root.mouseY)) {
                    root.osdShortcutActive = true;
                }
            } else {
                // OSD hidden, clear shortcut flag
                root.osdShortcutActive = false;
            }
        }

        function onUtilitiesChanged() {
            if (root.visibilities.utilities) {
                // Exclusión con el launcher: por hover no puede pasar (el
                // guard de showUtilities lo impide), así que esto solo actúa
                // cuando utilities se abre por atajo — la acción más reciente
                // gana. Va antes de detectar el modo atajo porque cerrar el
                // launcher limpia utilitiesShortcutActive de rebote.
                if (root.visibilities.launcher)
                    root.visibilities.launcher = false;

                // Utilities became visible, immediately check if this should be shortcut mode
                const inUtilitiesArea = root.inUtilitiesArea(root.mouseX, root.mouseY);
                if (!inUtilitiesArea) {
                    root.utilitiesShortcutActive = true;
                }

                // Exclusión con la app grid, que ocupa toda la pantalla
                if (root.visibilities.appgrid)
                    root.visibilities.appgrid = false;
            } else {
                // Utilities hidden, clear shortcut flag
                root.utilitiesShortcutActive = false;
            }
        }

        // La app grid ocupa la mayor parte de la pantalla (solo por atajo, sin
        // zona de hover propia) — al abrirse cierra el resto de docks/paneles
        // que puedan solaparse con ella, mismo patrón "la acción más reciente
        // gana" que launcher/utilities/miniapps entre sí.
        function onAppgridChanged() {
            if (root.visibilities.appgrid) {
                root.visibilities.launcher = false;
                root.visibilities.dashboard = false;
                root.visibilities.utilities = false;
                root.visibilities.sidebar = false;

                if (root.visibilities.miniapps && !root.miniappsDragActive) {
                    miniappsHideTimer.stop();
                    root.visibilities.miniapps = false;
                }
            }
        }

        function onWindowControlsChanged() {
            if (root.visibilities.windowControls) {
                const wcH = root.panels.windowControls.implicitHeight;
                const isWcOpen = (root.panels.windowControls.offsetScale ?? 1) < 1;
                const inArea = root.mouseY < Config.border.minThickness + (isWcOpen ? wcH : 0) &&
                    root.withinPanelWidth(root.panels.windowControls, root.mouseX, root.mouseY);
                if (!inArea)
                    root.windowControlsShortcutActive = true;
            } else {
                root.windowControlsShortcutActive = false;
            }
        }

        target: root.visibilities
    }
}
