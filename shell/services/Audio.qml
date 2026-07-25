pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import Caelestia
import Caelestia.Config
import Caelestia.Services

Singleton {
    id: root

    property string previousSinkName: ""
    property string previousSourceName: ""

    property list<PwNode> sinks: []
    property list<PwNode> sources: []
    property list<PwNode> streams: []

    // Dispositivos (tarjetas) con sus puertos, via caelestia-audio-devices.
    // PipeWire solo crea un nodo por cada salida del perfil ACTIVO de la
    // tarjeta, asi que `sinks` nunca contiene a la vez los altavoces y el HDMI:
    // hay que listar puertos y cambiar de perfil para pasar de uno a otro.
    property var devices: []

    // Listas que consume la UI: un elemento por salida/entrada seleccionable,
    // exista ya como nodo o haya que activarle el perfil.
    readonly property var outputs: root.buildRoutes("Output", root.sinks)
    readonly property var inputs: root.buildRoutes("Input", root.sources)

    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property PwNode source: Pipewire.defaultAudioSource

    readonly property bool muted: !!sink?.audio?.muted
    readonly property real volume: sink?.audio?.volume ?? 0

    readonly property bool sourceMuted: !!source?.audio?.muted
    readonly property real sourceVolume: source?.audio?.volume ?? 0

    readonly property alias cava: cava
    readonly property alias beatTracker: beatTracker

    function setVolume(newVolume: real): void {
        if (sink?.ready && sink?.audio) {
            sink.audio.muted = false;
            sink.audio.volume = Math.max(0, Math.min(GlobalConfig.services.maxVolume, newVolume));
        }
    }

    function incrementVolume(amount: real): void {
        setVolume(volume + (amount || GlobalConfig.services.audioIncrement));
    }

    function decrementVolume(amount: real): void {
        setVolume(volume - (amount || GlobalConfig.services.audioIncrement));
    }

    function setSourceVolume(newVolume: real): void {
        if (source?.ready && source?.audio) {
            source.audio.muted = false;
            source.audio.volume = Math.max(0, Math.min(GlobalConfig.services.maxVolume, newVolume));
        }
    }

    function incrementSourceVolume(amount: real): void {
        setSourceVolume(sourceVolume + (amount || GlobalConfig.services.audioIncrement));
    }

    function decrementSourceVolume(amount: real): void {
        setSourceVolume(sourceVolume - (amount || GlobalConfig.services.audioIncrement));
    }

    function setAudioSink(newSink: PwNode): void {
        Pipewire.preferredDefaultAudioSink = newSink;
    }

    function setAudioSource(newSource: PwNode): void {
        Pipewire.preferredDefaultAudioSource = newSource;
    }

    // Casa un nodo de PipeWire con el puerto (route) por el que esta sonando:
    // el nodo lleva el id de su tarjeta y el indice de device dentro de ella,
    // que es justo lo que enumera cada route.
    function nodeMatchesRoute(node: PwNode, deviceId: int, routeDevices: var): bool {
        const props = node?.properties;
        if (!props)
            return false;
        if (parseInt(props["device.id"]) !== deviceId)
            return false;
        return routeDevices.indexOf(parseInt(props["card.profile.device"])) !== -1;
    }

    function buildRoutes(direction: string, nodes: var): var {
        const entries = [];
        const claimed = [];

        for (const dev of root.devices) {
            for (const route of dev.routes ?? []) {
                if (route.direction !== direction)
                    continue;

                // Solo el puerto activo tiene nodo; los demas hay que activarlos.
                let node = null;
                if (route.active) {
                    node = nodes.find(n => root.nodeMatchesRoute(n, dev.id, route.devices ?? [])) ?? null;
                    if (node)
                        claimed.push(node.id);
                }

                // El nombre del aparato conectado ("LG TV") identifica mejor un
                // HDMI que el puerto; en ese caso el puerto baja al subtitulo.
                const label = route.product || route.description || qsTr("Unknown");
                const parts = [];
                if (route.product && route.description)
                    parts.push(route.description);
                if (dev.description)
                    parts.push(dev.description);

                entries.push({
                    key: `${dev.id}:${route.index}`,
                    name: label,
                    detail: parts.join(" · "),
                    type: route.type ?? "",
                    node,
                    routeActive: route.active,
                    deviceId: dev.id,
                    routeIndex: route.index,
                    profileIndex: route.profile
                });
            }
        }

        // Sinks/sources que no cuelgan de ninguna tarjeta (nulos, combinados,
        // efectos...): no tienen puertos, se listan tal cual.
        for (const node of nodes) {
            if (claimed.indexOf(node.id) !== -1)
                continue;
            entries.push({
                key: `node:${node.id}`,
                name: node.description || node.name || qsTr("Unknown"),
                detail: "",
                type: "",
                node,
                routeActive: true,
                deviceId: -1,
                routeIndex: -1,
                profileIndex: -1
            });
        }

        return entries;
    }

    // Un puerto puede tener nodo y aun asi no ser el activo: altavoces y
    // auriculares comparten perfil (y por tanto nodo), los distingue `routeActive`.
    function isActiveOutput(entry: var): bool {
        return !!entry?.node && entry.routeActive && entry.node.id === root.sink?.id;
    }

    function isActiveInput(entry: var): bool {
        return !!entry?.node && entry.routeActive && entry.node.id === root.source?.id;
    }

    function iconForEntry(entry: var, fallback: string): string {
        switch (entry?.type) {
        case "speaker":
            return "speaker";
        case "headphones":
            return "headphones";
        case "headset":
            return "headset_mic";
        case "hdmi":
            return "tv";
        case "mic":
            return "mic";
        case "bluetooth":
            return "bluetooth";
        default:
            return fallback;
        }
    }

    // Activa una salida/entrada. Si ya existe como nodo basta con marcarla por
    // defecto; si no, hay que cambiar el perfil de la tarjeta (lo hace el
    // helper, que ademas distingue cambio de perfil de cambio de ruta).
    function selectOutput(entry: var): void {
        if (root.isActiveOutput(entry))
            return;
        if (entry?.node && entry.routeActive)
            root.setAudioSink(entry.node);
        else if (entry?.deviceId >= 0)
            root.selectRoute(entry);
    }

    function selectInput(entry: var): void {
        if (root.isActiveInput(entry))
            return;
        if (entry?.node && entry.routeActive)
            root.setAudioSource(entry.node);
        else if (entry?.deviceId >= 0)
            root.selectRoute(entry);
    }

    function selectRoute(entry: var): void {
        selectProc.command = ["caelestia-audio-devices", "--select", `${entry.deviceId}`, `${entry.routeIndex}`, `${entry.profileIndex}`];
        selectProc.running = true;
    }

    function cycleNextAudioOutput(): void {
        const outs = root.outputs;
        if (outs.length === 0)
            return;

        const currentIndex = outs.findIndex(o => root.isActiveOutput(o));
        const nextIndex = (currentIndex + 1) % outs.length;
        root.selectOutput(outs[nextIndex]);
    }

    function setStreamVolume(stream: PwNode, newVolume: real): void {
        if (stream?.ready && stream?.audio) {
            stream.audio.muted = false;
            stream.audio.volume = Math.max(0, Math.min(GlobalConfig.services.maxVolume, newVolume));
        }
    }

    function setStreamMuted(stream: PwNode, muted: bool): void {
        if (stream?.ready && stream?.audio) {
            stream.audio.muted = muted;
        }
    }

    function getStreamVolume(stream: PwNode): real {
        return stream?.audio?.volume ?? 0;
    }

    function getStreamMuted(stream: PwNode): bool {
        return !!stream?.audio?.muted;
    }

    function getStreamName(stream: PwNode): string {
        if (!stream)
            return qsTr("Unknown");
        // Try application name first, then description, then name
        return stream.properties["application.name"] || stream.description || stream.name || qsTr("Unknown Application");
    }

    onSinkChanged: {
        if (!sink?.ready)
            return;

        const newSinkName = sink.description || sink.name || qsTr("Unknown Device");

        if (previousSinkName && previousSinkName !== newSinkName && GlobalConfig.utilities.toasts.audioOutputChanged)
            Toaster.toast(qsTr("Audio output changed"), qsTr("Now using: %1").arg(newSinkName), "volume_up");

        previousSinkName = newSinkName;
    }

    onSourceChanged: {
        if (!source?.ready)
            return;

        const newSourceName = source.description || source.name || qsTr("Unknown Device");

        if (previousSourceName && previousSourceName !== newSourceName && GlobalConfig.utilities.toasts.audioInputChanged)
            Toaster.toast(qsTr("Audio input changed"), qsTr("Now using: %1").arg(newSourceName), "mic");

        previousSourceName = newSourceName;
    }

    Component.onCompleted: {
        previousSinkName = sink?.description || sink?.name || qsTr("Unknown Device");
        previousSourceName = source?.description || source?.name || qsTr("Unknown Device");
    }

    Connections {
        function onValuesChanged(): void {
            const newSinks = [];
            const newSources = [];
            const newStreams = [];

            for (const node of Pipewire.nodes.values) {
                if (!node.isStream) {
                    if (node.isSink)
                        newSinks.push(node);
                    else if (node.audio)
                        newSources.push(node);
                } else if (node.audio) {
                    newStreams.push(node);
                }
            }

            root.sinks = newSinks;
            root.sources = newSources;
            root.streams = newStreams;
        }

        target: Pipewire.nodes
    }

    PwObjectTracker {
        objects: [...root.sinks, ...root.sources, ...root.streams]
    }

    // Emite una linea JSON con todos los dispositivos y sus puertos cada vez
    // que algo cambia (perfil, enchufar/desenchufar HDMI o auriculares...).
    Process {
        id: devicesProc

        running: true
        command: ["caelestia-audio-devices"]
        stdout: SplitParser {
            onRead: data => {
                try {
                    root.devices = JSON.parse(data).devices ?? [];
                } catch (e) {
                    console.warn("Audio: respuesta ilegible de caelestia-audio-devices:", e);
                }
            }
        }
        onExited: devicesRestart.restart()
    }

    Timer {
        id: devicesRestart

        interval: 2000
        onTriggered: devicesProc.running = true
    }

    Process {
        id: selectProc

        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim())
                    console.warn("Audio: fallo al cambiar de salida:", text.trim());
            }
        }
    }

    CavaProvider {
        id: cava

        bars: GlobalConfig.services.visualiserBars
    }

    BeatTracker {
        id: beatTracker
    }

    IpcHandler {
        function cycleOutput(): void {
            root.cycleNextAudioOutput();
        }

        function incVolume(): void {
            root.incrementVolume();
        }

        function decVolume(): void {
            root.decrementVolume();
        }

        function toggleMute(): void {
            if (root.sink?.ready && root.sink?.audio)
                root.sink.audio.muted = !root.sink.audio.muted;
        }

        function incMicVolume(): void {
            root.incrementSourceVolume();
        }

        function decMicVolume(): void {
            root.decrementSourceVolume();
        }

        function toggleMicMute(): void {
            if (root.source?.ready && root.source?.audio)
                root.source.audio.muted = !root.source.audio.muted;
        }

        target: "audio"
    }
}
