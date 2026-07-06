pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.components
import qs.services
import qs.utils

Item {
    id: root

    required property ShellScreen screen
    required property var client

    Layout.preferredWidth: Tokens.sizes.winfo.detailsWidth
    Layout.fillHeight: true

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Tokens.padding.large
        spacing: Tokens.spacing.normal

        Item { Layout.fillHeight: true }

        MaterialIcon {
            Layout.alignment: Qt.AlignHCenter
            text: root.client
                ? Icons.getAppCategoryIcon(root.client.appId, "desktop_windows")
                : "web_asset_off"
            color: root.client ? Colours.palette.m3primary : Colours.palette.m3outline
            font.pointSize: Tokens.font.size.extraLarge * 4
        }

        StyledText {
            Layout.alignment: Qt.AlignHCenter
            Layout.fillWidth: true
            text: root.client?.appId ?? qsTr("No active client")
            color: Colours.palette.m3outline
            font.pointSize: Tokens.font.size.large
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
        }

        Item { Layout.fillHeight: true }
    }
}
