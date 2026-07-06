pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string rootPath: `${Quickshell.env("HOME")}/MiniApps`

    // Árbol completo: { rutaRelativa: [entradas] }, "" = categorías raíz.
    // Ver scripts/miniapps-scan.py para el formato de cada entrada.
    property var dirs: ({})
    readonly property var categories: dirs[""] ?? []

    function entries(rel: string): var {
        return dirs[rel] ?? [];
    }

    function refresh(): void {
        scanProc.running = true;
    }

    // Lanza una entrada con las rutas soltadas como argumentos.
    // - AppDirs ROX: vía bash con la ruta del AppRun como $0 (los scripts
    //   usan `dirname "$0"` para localizar sus recursos).
    // - Lanzadores .desktop: vía `gio launch`, que interpreta Exec con sus
    //   códigos %f/%F/%u/%U, Terminal=true, etc. según el estándar.
    function run(entry: var, paths: var): void {
        if (entry.type === "desktop")
            Quickshell.execDetached(["gio", "launch", entry.path, ...(paths ?? [])]);
        else
            Quickshell.execDetached(["bash", `${entry.path}/AppRun`, ...(paths ?? [])]);
    }

    Process {
        id: scanProc

        running: true
        command: ["python3", `${Quickshell.shellDir}/scripts/miniapps-scan.py`, root.rootPath]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.dirs = JSON.parse(text);
                } catch (e) {
                    console.warn("MiniApps: fallo al parsear el escaneo:", e);
                }
            }
        }
    }
}
