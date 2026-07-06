import QtQuick
import Quickshell
import Caelestia.Config
import qs.components
import qs.services

Column {
    id: root

    spacing: Tokens.spacing.normal

    LaunchButton {
        icon: "public"
        colour: Colours.palette.m3tertiary
        onClicked: Quickshell.execDetached(["sh", "-c", "gtk-launch \"$(xdg-settings get default-web-browser)\""])
    }

    LaunchButton {
        icon: "folder"
        colour: Colours.palette.m3secondary
        onClicked: Quickshell.execDetached(["sh", "-c", "xdg-open \"$HOME\""])
    }

    component LaunchButton: Item {
        id: button

        required property string icon
        required property color colour

        signal clicked

        implicitWidth: buttonIcon.implicitHeight + Tokens.padding.small * 2
        implicitHeight: buttonIcon.implicitHeight

        StateLayer {
            // Cursed workaround to make the height larger than the parent
            anchors.fill: undefined
            anchors.centerIn: parent
            implicitWidth: implicitHeight
            implicitHeight: buttonIcon.implicitHeight + Tokens.padding.small * 2
            radius: Tokens.rounding.full
            onClicked: button.clicked()
        }

        MaterialIcon {
            id: buttonIcon

            anchors.centerIn: parent
            text: button.icon
            color: button.colour
            font.pointSize: Tokens.font.size.large
        }
    }
}
