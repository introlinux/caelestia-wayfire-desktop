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

    Label {
        Layout.topMargin: Tokens.padding.large * 2

        text: root.client?.title ?? qsTr("No active client")
        wrapMode: Text.WrapAtWordBoundaryOrAnywhere

        font.pointSize: Tokens.font.size.large
        font.weight: 500
    }

    Label {
        text: root.client?.appId ?? qsTr("No active client")
        color: Colours.palette.m3tertiary

        font.pointSize: Tokens.font.size.larger
    }

    StyledRect {
        Layout.fillWidth: true
        Layout.preferredHeight: 1
        Layout.leftMargin: Tokens.padding.large * 2
        Layout.rightMargin: Tokens.padding.large * 2
        Layout.topMargin: Tokens.spacing.normal
        Layout.bottomMargin: Tokens.spacing.large

        color: Colours.palette.m3secondary
    }

    Detail {
        icon: "workspaces"
        text: qsTr("Workspace: %1").arg(Hypr.activeWsId)
        color: Colours.palette.m3secondary
    }

    Detail {
        icon: "minimize"
        text: qsTr("Minimized: %1").arg(root.client?.minimized ? "yes" : "no")
        color: Colours.palette.m3primary
    }

    Detail {
        icon: "expand"
        text: qsTr("Maximized: %1").arg(root.client?.maximized ? "yes" : "no")
        color: Colours.palette.m3tertiary
    }

    Detail {
        icon: "fullscreen"
        text: qsTr("Fullscreen: %1").arg(root.client?.fullscreen ? "yes" : "no")
        color: Colours.palette.m3tertiary
    }

    Item {
        Layout.fillHeight: true
    }

    component Detail: RowLayout {
        id: detail

        required property string icon
        required property string text
        property alias color: icon.color

        Layout.leftMargin: Tokens.padding.large
        Layout.rightMargin: Tokens.padding.large
        Layout.fillWidth: true

        spacing: Tokens.spacing.smaller

        MaterialIcon {
            id: icon

            Layout.alignment: Qt.AlignVCenter
            text: detail.icon
        }

        StyledText {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter

            text: detail.text
            elide: Text.ElideRight
            font.pointSize: Tokens.font.size.normal
        }
    }

    component Label: StyledText {
        Layout.leftMargin: Tokens.padding.large
        Layout.rightMargin: Tokens.padding.large
        Layout.fillWidth: true
        elide: Text.ElideRight
        horizontalAlignment: Text.AlignHCenter
        animate: true
    }
}
