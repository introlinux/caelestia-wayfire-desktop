pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Caelestia
import Caelestia.Config
import Caelestia.Internal

Singleton {
    id: root

    // ── Toplevels ─────────────────────────────────────────────────────────────
    readonly property var toplevels: ToplevelManager.toplevels
    readonly property var activeToplevel: ToplevelManager.activeToplevel
    property var hoveredToplevel: null

    // ── Workspaces ────────────────────────────────────────────────────────────
    // ObjectModel-compatible wrapper so .values works throughout the codebase
    readonly property QtObject workspaces: QtObject {
        property var values: root._wsData
    }
    readonly property var focusedWorkspace: _wsData[_activeWsId - 1] ?? _wsData[0]
    readonly property int activeWsId: _activeWsId

    // ── Monitors ──────────────────────────────────────────────────────────────
    readonly property QtObject monitors: QtObject {
        property var values: [root.focusedMonitor]
    }
    readonly property QtObject focusedMonitor: QtObject {
        property string name: "default"
        property bool focused: true
        property var activeWorkspace: root.focusedWorkspace
        property var lastIpcObject: QtObject {
            property var specialWorkspace: QtObject { property string name: "" }
        }
    }

    // ── Keyboard state ────────────────────────────────────────────────────────
    property bool capsLock: false
    property bool numLock: false
    property string kbLayout: "??"
    property string kbLayoutFull: "Unknown"
    property string defaultKbLayout: "??"

    // ── Stubs para features exclusivos de Hyprland ────────────────────────────
    // GameMode y Colours.qml llaman extras.applyOptions / batchMessage
    readonly property QtObject extras: QtObject {
        id: extrasStub
        function applyOptions(opts): void { /* TODO: Wayfire IPC v2 */ }
        function batchMessage(msgs): void { }
        function message(msg: string): void { }
        function refreshDevices(): void { }
        property var devices: QtObject { property var keyboards: [] }
        property var options: null
    }
    readonly property var options: extras.options
    readonly property var devices: extras.devices

    signal configReloaded

    // ── dispatch() ────────────────────────────────────────────────────────────
    function dispatch(request: string): void {
        const space = request.indexOf(" ");
        const cmd   = space === -1 ? request : request.slice(0, space);
        const arg   = space === -1 ? ""      : request.slice(space + 1);

        switch (cmd) {
        case "workspace":
            if (arg.startsWith("r+"))
                _switchWs(_activeWsId + parseInt(arg.slice(2)));
            else if (arg.startsWith("r-"))
                _switchWs(_activeWsId - parseInt(arg.slice(2)));
            else
                _switchWs(parseInt(arg));
            break;
        case "killactive":
            activeToplevel?.close();
            break;
        case "fullscreen":
            if (activeToplevel) activeToplevel.maximized = !activeToplevel.maximized;
            break;
        default:
            break;
        }
    }

    function monitorFor(screen: ShellScreen): var {
        return focusedMonitor;
    }

    function monitorNames(): list<string> {
        return ["default"];
    }

    // ── Internal workspace model ──────────────────────────────────────────────

    property int _activeWsId: 1
    property var _wsData: _buildWsData()

    function _buildWsData(): var {
        const tops = ToplevelManager.toplevels.values ?? [];
        const visible = tops.filter(t => !t.minimized);
        const arr = [];
        for (let i = 1; i <= 10; i++) {
            const wins = (i === root._activeWsId) ? visible.length : 0;
            arr.push({
                id:   i,
                name: i.toString(),
                lastIpcObject: {
                    windows: wins,
                    specialWorkspace: { name: "" }
                },
                toplevels: { values: i === root._activeWsId ? visible : [] }
            });
        }
        return arr;
    }

    onActiveWsIdChanged: _wsData = _buildWsData()
    Connections {
        target: ToplevelManager
        function onActiveToplevelChanged(): void { root._wsData = root._buildWsData(); }
    }

    function _switchWs(id: int): void {
        const n = Math.max(1, Math.min(id, 10));
        _activeWsId = n;
        wsProc.command = ["wayfire-ws-switch", n.toString()];
        wsProc.running = true;
    }

    Process {
        id: wsProc
        running: false
        onExited: running = false
    }

    // ── Wayfire IPC ───────────────────────────────────────────────────────────

    property string _socket: Quickshell.env("WAYFIRE_SOCKET") ?? ""

    function _ipcSend(method: string, data: var): void {
        if (!_socket) return;
        const payload = data !== undefined
            ? JSON.stringify({ method, data })
            : JSON.stringify({ method });
        ipcSendProc.command = [
            "python3", "-c",
            `import socket,json,struct
s=socket.socket(socket.AF_UNIX)
s.connect(${JSON.stringify(_socket)})
msg=${JSON.stringify(payload)}.encode()
s.send(struct.pack('<I',len(msg))+msg)
s.close()`
        ];
        ipcSendProc.running = true;
    }

    Process {
        id: ipcSendProc
        running: false
        onExited: running = false
    }

    // ── Keyboard state (leer desde /sys y setxkbmap) ──────────────────────────

    FileView {
        id: capsLockReader
        path: root._capsLockPath
        onLoaded: root.capsLock = text().trim() === "1"
        onLoadFailed: root.capsLock = false
    }

    FileView {
        id: numLockReader
        path: root._numLockPath
        onLoaded: root.numLock = text().trim() === "1"
        onLoadFailed: root.numLock = false
    }

    Process {
        id: kbLayoutProc
        running: false
        command: ["bash", "-c", "setxkbmap -query 2>/dev/null | awk '/^layout/{print $2}'"]
        stdout: SplitParser {
            onRead: data => {
                const layout = data.trim();
                if (layout) {
                    root.kbLayout        = layout;
                    root.kbLayoutFull    = layout;
                    root.defaultKbLayout = layout;
                }
            }
        }
        onExited: running = false
    }

    property string _capsLockPath: "/sys/class/leds/input1::capslock/brightness"
    property string _numLockPath:  "/sys/class/leds/input1::numlock/brightness"

    Timer {
        interval: 3000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            capsLockReader.reload();
            numLockReader.reload();
            kbLayoutProc.running = true;
        }
    }

    // ── IpcHandler (Quickshell IPC, independiente del compositor) ─────────────
    IpcHandler {
        function setActiveWs(id: string): void { root._activeWsId = parseInt(id) }
        function refreshDevices(): void { }
        function cycleSpecialWorkspace(direction: string): void { }
        function listSpecialWorkspaces(): string { return ""; }
        target: "hypr"
    }
}
