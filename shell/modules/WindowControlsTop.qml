pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Caelestia.Config
import qs.components
import qs.services

ShellWindow {
    id: root
    
    name: "window-controls-top"
    
    // Posicionamiento en la esquina superior derecha
    anchors.top: true
    anchors.right: true
    anchors.margins: 10

    // Tamaño automático basado en los botones
    width: layout.implicitWidth + 10
    height: layout.implicitHeight + 10

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.exclusionMode: ExclusionMode.None
    
    // IMPORTANTE: Esto evita que la ventana robe el foco o bloquee el sistema
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    color: "transparent"

    StyledRect {
        anchors.fill: parent
        color: Qt.alpha(Colours.tPalette.m3surfaceContainer, 0.8)
        radius: Tokens.rounding.normal
        
        RowLayout {
            id: layout
            anchors.centerIn: parent
            spacing: Tokens.spacing.small

            // Botón Minimizar
            ControlButton {
                icon: "remove"
                color: Colours.palette.m3secondary
                onClicked: {
                    const win = Hypr.activeToplevel;
                    if (win) win.minimized = true;
                }
            }

            // Botón Maximizar
            ControlButton {
                icon: "expand"
                color: Colours.palette.m3primary
                onClicked: {
                    const win = Hypr.activeToplevel;
                    if (win) win.maximized = !win.maximized;
                }
            }

            // Botón Cerrar
            ControlButton {
                icon: "close"
                color: Colours.palette.m3error
                onClicked: {
                    const win = Hypr.activeToplevel;
                    if (win) win.close();
                }
            }
        }
    }

    component ControlButton: Item {
        property alias icon: iconItem.text
        property alias color: iconItem.color
        signal clicked

        implicitWidth: iconItem.implicitWidth + 8
        implicitHeight: iconItem.implicitHeight + 8

        MaterialIcon {
            id: iconItem
            anchors.centerIn: parent
            font.pointSize: Tokens.font.size.medium
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onClicked: parent.clicked()
            
            Rectangle {
                anchors.fill: parent
                color: parent.containsMouse ? Colours.palette.m3surfaceContainerHigh : "transparent"
                opacity: 0.4
                radius: 4
            }
        }
    }
}
