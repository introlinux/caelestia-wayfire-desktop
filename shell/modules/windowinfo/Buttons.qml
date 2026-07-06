pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.services

ColumnLayout {
    id: root

    required property var client

    anchors.fill: parent
    spacing: Tokens.spacing.small

    Item { Layout.fillHeight: true }

    Button {
        Layout.fillWidth: true
        Layout.leftMargin: Tokens.padding.large
        Layout.rightMargin: Tokens.padding.large
        Layout.bottomMargin: Tokens.padding.large

        color: Colours.palette.m3errorContainer
        onColor: Colours.palette.m3onErrorContainer
        text: qsTr("Kill")
        onClicked: root.client?.close()
    }

    component Button: StyledRect {
        property color onColor: Colours.palette.m3onSurface
        property alias text: label.text

        signal clicked

        radius: Tokens.rounding.small
        implicitHeight: label.implicitHeight + Tokens.padding.small * 2

        StateLayer {
            color: parent.onColor
            onClicked: parent.clicked()
        }

        StyledText {
            id: label
            anchors.centerIn: parent
            animate: true
            color: parent.onColor
            font.pointSize: Tokens.font.size.normal
        }
    }
}
