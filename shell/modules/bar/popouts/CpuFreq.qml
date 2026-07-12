pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.components.misc
import qs.services

Column {
    id: root

    // Presets: fresco = frecuencia base sin turbo; medio = punto intermedio;
    // máximo = todo abierto. base puede faltar (AMD): cae a la mitad del rango.
    readonly property int coolFreq: CpuFreq.base || Math.round((CpuFreq.hwMin + CpuFreq.hwMax) / 2)
    readonly property int midFreq: Math.round((coolFreq + CpuFreq.hwMax) / 2)

    spacing: Tokens.spacing.normal
    width: Tokens.sizes.bar.batteryWidth

    Ref {
        service: CpuFreq
    }

    StyledText {
        text: qsTr("Current: %1").arg(CpuFreq.formatGhz(CpuFreq.cur))
    }

    StyledText {
        text: qsTr("Limit: %1%2").arg(CpuFreq.formatGhz(CpuFreq.max)).arg(CpuFreq.turbo ? "" : qsTr(" (no turbo)"))
    }

    StyledRect {
        id: presets

        property string current: {
            if (CpuFreq.max <= root.coolFreq && !CpuFreq.turbo)
                return cool.icon;
            if (CpuFreq.max >= CpuFreq.hwMax && CpuFreq.turbo)
                return full.icon;
            return mid.icon;
        }

        anchors.horizontalCenter: parent.horizontalCenter

        implicitWidth: cool.implicitHeight + mid.implicitHeight + full.implicitHeight + Tokens.padding.normal * 2 + Tokens.spacing.large * 2
        implicitHeight: Math.max(cool.implicitHeight, mid.implicitHeight, full.implicitHeight) + Tokens.padding.small * 2

        color: Colours.tPalette.m3surfaceContainer
        radius: Tokens.rounding.full

        StyledRect {
            id: indicator

            color: Colours.palette.m3primary
            radius: Tokens.rounding.full
            state: presets.current

            states: [
                State {
                    name: cool.icon

                    Fill {
                        item: cool
                    }
                },
                State {
                    name: mid.icon

                    Fill {
                        item: mid
                    }
                },
                State {
                    name: full.icon

                    Fill {
                        item: full
                    }
                }
            ]

            transitions: Transition {
                AnchorAnim {
                    type: AnchorAnim.Emphasized
                }
            }
        }

        Preset {
            id: cool

            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: Tokens.padding.small

            icon: "ac_unit"
            maxFreq: root.coolFreq
            turbo: false
        }

        Preset {
            id: mid

            anchors.centerIn: parent

            icon: "thermostat"
            maxFreq: root.midFreq
            turbo: true
        }

        Preset {
            id: full

            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
            anchors.rightMargin: Tokens.padding.small

            icon: "rocket_launch"
            maxFreq: CpuFreq.hwMax
            turbo: true
        }
    }

    StyledSlider {
        id: slider

        anchors.left: parent.left
        anchors.right: parent.right
        implicitHeight: Tokens.padding.normal * 3

        from: CpuFreq.hwMin
        to: CpuFreq.hwMax
        stepSize: 100000

        // Mientras se arrastra manda el dedo; al soltar se aplica el tope
        Binding {
            target: slider
            property: "value"
            value: CpuFreq.max
            when: !slider.pressed
        }

        onPressedChanged: {
            if (!pressed)
                CpuFreq.setMax(value);
        }
    }

    StyledText {
        anchors.horizontalCenter: parent.horizontalCenter
        text: qsTr("Max limit: %1").arg(CpuFreq.formatGhz(slider.value))
        color: Colours.palette.m3outline
        font.pointSize: Tokens.font.size.small
    }

    IconTextButton {
        anchors.left: parent.left
        anchors.right: parent.right

        toggle: true
        checked: CpuFreq.turbo
        verticalPadding: Tokens.padding.small
        text: CpuFreq.turbo ? qsTr("Turbo on") : qsTr("Turbo off")
        icon: CpuFreq.turbo ? "bolt" : "energy_savings_leaf"

        onClicked: CpuFreq.setTurbo(!CpuFreq.turbo)
    }

    Loader {
        anchors.left: parent.left
        anchors.right: parent.right

        active: !CpuFreq.sudoOk
        visible: active

        sourceComponent: StyledText {
            text: qsTr("No permission: re-run install.sh\n(sudoers rule missing)")
            color: Colours.palette.m3error
            font.pointSize: Tokens.font.size.small
        }
    }

    component Fill: AnchorChanges {
        required property Item item

        target: indicator
        anchors.left: item.left
        anchors.right: item.right
        anchors.top: item.top
        anchors.bottom: item.bottom
    }

    component Preset: Item {
        id: preset

        required property string icon
        required property int maxFreq
        required property bool turbo

        implicitWidth: iconLabel.implicitHeight + Tokens.padding.small * 2
        implicitHeight: iconLabel.implicitHeight + Tokens.padding.small * 2

        StateLayer {
            radius: Tokens.rounding.full
            color: presets.current === preset.icon ? Colours.palette.m3onPrimary : Colours.palette.m3onSurface
            // Turbo ANTES que el tope: con el turbo apagado el kernel recorta
            // scaling_max_freq a la frecuencia base al escribirlo
            onClicked: {
                CpuFreq.setTurbo(preset.turbo);
                CpuFreq.setMax(preset.maxFreq);
            }
        }

        MaterialIcon {
            id: iconLabel

            anchors.centerIn: parent

            text: preset.icon
            font.pointSize: Tokens.font.size.large
            color: presets.current === text ? Colours.palette.m3onPrimary : Colours.palette.m3onSurface
            fill: presets.current === text ? 1 : 0

            Behavior on fill {
                Anim {}
            }
        }
    }
}
