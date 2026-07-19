pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.services

// OSD de entrada para videotutoriales: muestra las teclas pulsadas y los
// gestos de touchpad (swipe/pinch/hold de libinput + scroll de 2 dedos).
// Se alimenta de bin/caelestia-input-watch, que corre como root vía
// `sudo -n` (regla NOPASSWD instalada por install.sh). Conmutable con:
//   qs -c caelestia ipc call inputosd toggle    (atajo: Super+K)
// Los textos van en castellano directamente (sin qsTr) para no arrastrar
// el ciclo de traducción del plugin: este fork es es_ES.
Scope {
    id: root

    property bool enabled: false

    // Gesto/scroll en curso o recién terminado
    property string gIcon: ""
    property string gText: ""
    property bool gActive: false

    function dirIcon(dx: real, dy: real): string {
        if (Math.abs(dx) >= Math.abs(dy))
            return dx > 0 ? "arrow_forward" : "arrow_back";
        return dy > 0 ? "arrow_downward" : "arrow_upward";
    }

    function dirIconNamed(dir: string): string {
        switch (dir) {
        case "left": return "arrow_back";
        case "right": return "arrow_forward";
        case "up": return "arrow_upward";
        case "down": return "arrow_downward";
        }
        return "";
    }

    function handle(ev: var): void {
        if (ev.t === "key") {
            const label = ev.mods.length > 0 ? ev.mods.join(" + ") + " + " + ev.key : ev.key;
            // Una pulsación repetida refresca el chip en vez de duplicarlo
            const last = keysModel.count > 0 ? keysModel.get(keysModel.count - 1) : null;
            if (last && last.label === label) {
                keysModel.setProperty(keysModel.count - 1, "count", last.count + 1);
                keysModel.setProperty(keysModel.count - 1, "ts", Date.now());
            } else {
                keysModel.append({
                    label: label,
                    count: 1,
                    ts: Date.now()
                });
                if (keysModel.count > 4)
                    keysModel.remove(0);
            }
            expiry.restart();
        } else if (ev.t === "button") {
            const names = {
                left: "Clic izq",
                right: "Clic dcho",
                middle: "Clic central"
            };
            root.gIcon = "mouse";
            root.gText = names[ev.btn] ?? ev.btn;
            root.gActive = false;
            gestureHide.restart();
        } else if (ev.t === "gesture") {
            if (ev.state === "update") {
                root.gActive = true;
                gestureHide.stop();
                if (ev.kind === "hold") {
                    root.gIcon = "touch_app";
                    root.gText = `${ev.fingers} dedos (mantener)`;
                } else if (ev.kind === "pinch") {
                    root.gIcon = "pinch";
                    root.gText = `Pellizco ${ev.fingers} dedos`;
                } else {
                    root.gIcon = root.dirIcon(ev.dx, ev.dy);
                    root.gText = `${ev.fingers} dedos`;
                }
            } else if (ev.state === "end") {
                if (ev.kind === "pinch")
                    root.gIcon = ev.dir === "in" ? "zoom_in_map" : "zoom_out_map";
                else if (ev.kind === "swipe")
                    root.gIcon = root.dirIconNamed(ev.dir);
                root.gActive = false;
                gestureHide.restart();
            } else {
                root.gActive = false;
                gestureHide.restart();
            }
        } else if (ev.t === "scroll") {
            if (ev.state === "update") {
                root.gActive = true;
                gestureHide.stop();
                root.gIcon = root.dirIcon(ev.dx, ev.dy);
                root.gText = "Scroll 2 dedos";
            } else {
                root.gActive = false;
                gestureHide.restart();
            }
        }
    }

    IpcHandler {
        target: "inputosd"

        function toggle(): void {
            root.enabled = !root.enabled;
        }

        function enable(): void {
            root.enabled = true;
        }

        function disable(): void {
            root.enabled = false;
        }
    }

    ListModel {
        id: keysModel
    }

    // Caducidad de los chips de teclas (se van borrando al envejecer)
    Timer {
        id: expiry

        interval: 500
        repeat: true
        onTriggered: {
            const now = Date.now();
            while (keysModel.count > 0 && now - keysModel.get(0).ts > 2500)
                keysModel.remove(0);
            if (keysModel.count === 0)
                stop();
        }
    }

    Timer {
        id: gestureHide

        interval: 900
        onTriggered: {
            root.gIcon = "";
            root.gText = "";
        }
    }

    Process {
        id: watcher

        running: root.enabled
        command: ["sudo", "-n", "/usr/local/bin/caelestia-input-watch"]

        stdout: SplitParser {
            onRead: data => {
                try {
                    root.handle(JSON.parse(data));
                } catch (e) {}
            }
        }

        onExited: (code, status) => {
            // sudo -n sin regla NOPASSWD (u otro fallo): no reintentar en bucle
            if (root.enabled) {
                root.enabled = false;
                keysModel.clear();
                root.gIcon = "error";
                root.gText = "inputosd: sin permisos (¿sudoers?)";
                gestureHide.restart();
            }
        }
    }

    LazyLoader {
        active: root.enabled || root.gText !== "" || keysModel.count > 0

        Variants {
            model: Quickshell.screens

            StyledWindow {
                id: win

                required property ShellScreen modelData

                screen: modelData
                name: "input-osd"
                WlrLayershell.exclusionMode: ExclusionMode.Ignore
                WlrLayershell.layer: WlrLayer.Overlay
                mask: Region {}

                anchors.bottom: true
                anchors.left: true
                anchors.right: true
                implicitHeight: 96

                RowLayout {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: Tokens.padding.large * 2
                    spacing: Tokens.spacing.normal

                    // Indicador de gesto / botón de ratón
                    StyledRect {
                        visible: root.gText !== ""
                        radius: Tokens.rounding.full
                        color: Qt.alpha(Colours.palette.m3surfaceContainer, 0.92)
                        implicitWidth: gestureRow.implicitWidth + Tokens.padding.large * 2
                        implicitHeight: 44

                        opacity: root.gActive ? 1 : 0.85

                        RowLayout {
                            id: gestureRow

                            anchors.centerIn: parent
                            spacing: Tokens.spacing.small

                            MaterialIcon {
                                visible: root.gIcon !== ""
                                text: root.gIcon
                                color: Colours.palette.m3primary
                                font.pointSize: Tokens.font.size.large
                            }

                            StyledText {
                                text: root.gText
                                color: Colours.palette.m3onSurface
                                font.pointSize: Tokens.font.size.normal
                            }
                        }
                    }

                    // Chips de teclas
                    Repeater {
                        model: keysModel

                        StyledRect {
                            id: chip

                            required property string label
                            required property int count

                            radius: Tokens.rounding.normal
                            color: Qt.alpha(Colours.palette.m3inverseSurface, 0.92)
                            implicitWidth: chipText.implicitWidth + Tokens.padding.large * 2
                            implicitHeight: 44

                            scale: 0
                            Component.onCompleted: scale = 1

                            Behavior on scale {
                                Anim {}
                            }

                            StyledText {
                                id: chipText

                                anchors.centerIn: parent
                                text: chip.count > 1 ? `${chip.label} ×${chip.count}` : chip.label
                                color: Colours.palette.m3inverseOnSurface
                                font.pointSize: Tokens.font.size.normal
                                font.weight: 500
                            }
                        }
                    }
                }
            }
        }
    }
}
