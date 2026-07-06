import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.components.images
import qs.services
import qs.utils

Item {
    id: root

    required property PopoutState popouts

    // Keep the last non-null hovered toplevel so the popup content stays
    // stable while the user moves their mouse from the task icon into the popup.
    property var lastHoveredToplevel: null
    readonly property var previewToplevel: Hypr.hoveredToplevel ?? lastHoveredToplevel ?? Hypr.activeToplevel

    Connections {
        target: Hypr
        function onHoveredToplevelChanged() {
            if (Hypr.hoveredToplevel !== null)
                root.lastHoveredToplevel = Hypr.hoveredToplevel
        }
    }

    implicitWidth: previewToplevel ? child.implicitWidth : -Tokens.padding.large * 2
    implicitHeight: child.implicitHeight

    // Process for sending a window to a workspace via key injection
    Process {
        id: sendToWsProc
        running: false
        onExited: running = false
    }

    // Process for force quitting an application
    Process {
        id: forceQuitProc
        running: false
        onExited: running = false
    }

    Column {
        id: child

        anchors.centerIn: parent
        spacing: Tokens.spacing.normal

        // Header: app icon + title / appId
        RowLayout {
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: Tokens.spacing.normal

            MaterialIcon {
                Layout.alignment: Qt.AlignVCenter
                text: Icons.getAppCategoryIcon(root.previewToplevel?.appId ?? "", "desktop_windows")
                color: Colours.palette.m3primary
                font.pointSize: Tokens.font.size.extraLarge
            }

            ColumnLayout {
                spacing: 0
                Layout.fillWidth: true

                StyledText {
                    Layout.fillWidth: true
                    text: root.previewToplevel?.title ?? ""
                    font.pointSize: Tokens.font.size.normal
                    elide: Text.ElideRight
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.previewToplevel?.appId ?? ""
                    color: Colours.palette.m3onSurfaceVariant
                    elide: Text.ElideRight
                }
            }
        }

        // App icon (wlr-screencopy cannot capture individual toplevels in Wayfire)
        CachingIconImage {
            anchors.horizontalCenter: parent.horizontalCenter
            implicitSize: 96
            width: 96
            height: 96
            source: Icons.getAppIcon(root.previewToplevel?.appId ?? "", "application-x-executable")
        }

        // Workspace send buttons (workspaces 1-4)
        RowLayout {
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: Tokens.spacing.smaller

            Repeater {
                model: 4

                TextButton {
                    required property int index

                    Layout.fillWidth: true
                    text: (index + 1).toString()
                    type: TextButton.Tonal

                    onClicked: {
                        const t = root.previewToplevel
                        if (!t) return
                        const wsNum = index + 1
                        const appId = t.appId ?? ""
                        // Close popup first so the layer shell doesn't hold focus
                        root.popouts.hasCurrent = false
                        t.activate()
                        if (sendToWsProc.running) sendToWsProc.running = false
                        sendToWsProc.command = ["wayfire-send-to-ws", wsNum.toString(), appId, t.title ?? ""]
                        sendToWsProc.running = true
                    }
                }
            }
        }

        // Force quit button (full width, error colour)
        TextButton {
            anchors.left: parent.left
            anchors.right: parent.right
            text: qsTr("Force quit")
            type: TextButton.Filled
            inactiveColour: Colours.palette.m3error
            inactiveOnColour: Colours.palette.m3onError

            onClicked: {
                const target = root.previewToplevel
                if (!target) return
                const appId = target.appId ?? ""
                console.log("[ActiveWindow] force-quit appId:", appId)
                // Send Wayland close request first
                target.close()
                // Also try to kill by process name as fallback for frozen apps
                if (appId) {
                    if (forceQuitProc.running) forceQuitProc.running = false
                    forceQuitProc.command = ["caelestia-force-quit", appId]
                    forceQuitProc.running = true
                }
                root.popouts.hasCurrent = false
            }
        }
    }
}
