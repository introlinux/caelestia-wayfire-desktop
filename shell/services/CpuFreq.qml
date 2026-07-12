pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // Siempre la copia de /usr/local/bin: es la que posee root y la única a la
    // que apunta la regla sudoers instalada por install.sh.
    readonly property string helper: "/usr/local/bin/caelestia-cpufreq"

    property bool available: false
    // Sin permisos sudo (regla no instalada): el popout muestra el aviso.
    property bool sudoOk: true

    // Frecuencias en kHz, como en sysfs
    property int cur
    property int max
    property int base
    property int hwMin
    property int hwMax
    property bool turbo: true

    // Hay un tope activo (frecuencia capada o turbo apagado)
    readonly property bool limited: available && (max < hwMax || !turbo)

    property int refCount

    function setMax(khz: int): void {
        setter.run(["set-max", String(Math.round(khz))]);
    }

    function setTurbo(on: bool): void {
        setter.run(["turbo", on ? "on" : "off"]);
    }

    function formatGhz(khz: int): string {
        return `${(khz / 1000000).toFixed(khz % 1000000 === 0 ? 1 : 2)} GHz`;
    }

    // Sondeo rápido con el popout abierto; lento de fondo para el icono
    Timer {
        running: true
        interval: root.refCount > 0 ? 1000 : 15000
        repeat: true
        triggeredOnStart: true
        onTriggered: status.running = true
    }

    Process {
        id: status

        command: [root.helper, "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const s = JSON.parse(text);
                    root.cur = s.cur;
                    root.max = s.max;
                    root.base = s.base;
                    root.hwMin = s.hwMin;
                    root.hwMax = s.hwMax;
                    root.turbo = s.turbo;
                    // Sin rango que regular (CPU de frecuencia fija) = sin indicador
                    root.available = s.hwMin < s.hwMax;
                } catch (e) {
                    root.available = false;
                }
            }
        }
    }

    Process {
        id: setter

        // Un preset lanza dos comandos seguidos (set-max + turbo): se encolan
        // para que el segundo no se pierda mientras corre el primero.
        property var queue: []

        function run(args: list<string>): void {
            if (running) {
                queue.push(args);
                return;
            }
            command = ["sudo", "-n", root.helper, ...args];
            running = true;
        }

        onExited: code => { // qmllint disable signal-handler-parameters
            root.sudoOk = code === 0;
            if (queue.length > 0) {
                command = ["sudo", "-n", root.helper, ...queue.shift()];
                running = true;
            } else {
                status.running = true;
            }
        }
    }
}
