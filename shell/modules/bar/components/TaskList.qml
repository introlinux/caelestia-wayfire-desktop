pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.components
import qs.services
import qs.utils

ColumnLayout {
    id: root

    // Bar popouts wrapper; used to close the hover preview when clicking an
    // icon, so it does not cover the minimize/restore animation.
    property var popouts: null

    spacing: Tokens.spacing.normal

    // Shared timer: prevents flicker when moving quickly between window icons.
    Timer {
        id: hoverClearTimer
        interval: 150
        onTriggered: Hypr.hoveredToplevel = null
    }

    Repeater {
        model: Hypr.toplevels.values

        delegate: Item {
            id: wrapper
            required property var modelData

            Layout.alignment: Qt.AlignHCenter
            implicitWidth: icon.implicitWidth + Tokens.padding.small * 2
            implicitHeight: icon.implicitHeight + Tokens.padding.small * 2

            readonly property bool isActive: Hypr.activeToplevel === modelData
            readonly property bool isMinimized: modelData.minimized ?? false

            // Publish this icon's rect as the toplevel's minimize target so the
            // compositor's squeezimize (magic lamp) animation aims at the icon.
            function publishMinimizeRect(): void {
                const win = wrapper.QsWindow.window;
                if (!win || wrapper.width <= 0 || wrapper.height <= 0)
                    return;
                const pos = wrapper.mapToItem(null, 0, 0);
                wrapper.modelData.setRectangle(win, Qt.rect(
                    Math.round(pos.x), Math.round(pos.y),
                    Math.round(wrapper.width), Math.round(wrapper.height)));
            }

            Component.onCompleted: publishMinimizeRect()
            onXChanged: publishMinimizeRect()
            onYChanged: publishMinimizeRect()
            onWidthChanged: publishMinimizeRect()
            onHeightChanged: publishMinimizeRect()


            Rectangle {
                anchors.fill: parent
                radius: Tokens.rounding.small
                color: wrapper.isActive
                    ? Colours.palette.m3primaryContainer
                    : (mouseArea.containsMouse ? Colours.palette.m3surfaceContainerHigh : "transparent")
                opacity: wrapper.isMinimized ? 0.4 : 1.0

                Behavior on color   { ColorAnimation  { duration: 200 } }
                Behavior on opacity { NumberAnimation { duration: 200 } }

                Rectangle {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: 3
                    height: parent.height * 0.4
                    radius: 2
                    color: Colours.palette.m3primary
                    visible: wrapper.isActive
                }
            }

            MaterialIcon {
                id: icon
                anchors.centerIn: parent
                text: Icons.getAppCategoryIcon(wrapper.modelData.appId, "desktop_windows")
                color: wrapper.isActive
                    ? Colours.palette.m3onPrimaryContainer
                    : Colours.palette.m3onSurface
                font.pointSize: Tokens.font.size.extraLarge
            }

            MouseArea {
                id: mouseArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton

                onEntered: {
                    hoverClearTimer.stop()
                    Hypr.hoveredToplevel = wrapper.modelData
                    wrapper.publishMinimizeRect()
                }
                onExited: hoverClearTimer.restart()

                onClicked: {
                    root.popouts?.suppressBriefly()
                    wrapper.publishMinimizeRect()
                    if (wrapper.isMinimized) {
                        wrapper.modelData.minimized = false
                        wrapper.modelData.activate()
                    } else if (wrapper.isActive) {
                        wrapper.modelData.minimized = true
                    } else {
                        wrapper.modelData.activate()
                    }
                }
            }

            // Drag-over: raise window after hovering 600ms while dragging a file
            DropArea {
                anchors.fill: parent
                onEntered: dragRaiseTimer.restart()
                onExited:  dragRaiseTimer.stop()
            }

            Timer {
                id: dragRaiseTimer
                interval: 600
                onTriggered: {
                    wrapper.modelData.minimized = false
                    wrapper.modelData.activate()
                }
            }

            Rectangle {
                id: tooltip
                visible: mouseArea.containsMouse
                anchors.left: parent.right
                anchors.leftMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                width: tooltipText.implicitWidth + 20
                height: tooltipText.implicitHeight + 10
                color: Colours.palette.m3surfaceContainer
                radius: 5
                z: 100

                StyledText {
                    id: tooltipText
                    anchors.centerIn: parent
                    text: wrapper.modelData.title
                    font.pointSize: Tokens.font.size.small
                }
            }
        }
    }
}
