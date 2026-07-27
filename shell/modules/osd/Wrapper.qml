pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Caelestia.Config
import qs.components
import qs.services

Item {
    id: root

    required property ShellScreen screen
    required property DrawerVisibilities visibilities
    required property bool sidebarOrSessionVisible

    property bool hovered
    readonly property Brightness.Monitor monitor: Brightness.getMonitorForScreen(root.screen)
    readonly property bool shouldBeActive: visibilities.osd && Config.osd.enabled && !(visibilities.utilities && Config.utilities.enabled)
    property real offsetScale: shouldBeActive ? 0 : 1
    property real sidebarOffset: sidebarOrSessionVisible ? 12 : 0

    property real volume
    property bool muted
    property real sourceVolume
    property bool sourceMuted
    property real brightness

    // El OSD solo debe salir ante cambios provocados por el usuario, pero al
    // arrancar los valores llegan solos y disparaban el panel dos veces: primero
    // el audio (PipeWire enlaza el nodo por defecto y luego su objeto de audio,
    // así que el volumen salta 0 -> real) y segundos después el brillo (leerlo
    // por DDC cuesta un `ddcutil detect` + `getvcp`). Aquí se filtra el audio;
    // el brillo lo marca el propio servicio con Monitor.initializing.
    //
    // Nada de audio cuenta hasta que el nodo por defecto lleva un momento
    // enlazado: `ready` sube al enlazarlo y sus valores llegan justo después.
    readonly property bool sinkReady: Audio.sink?.ready ?? false
    readonly property bool sourceReady: Audio.source?.ready ?? false
    property bool audioSettled: false

    onSinkReadyChanged: settleTimer.restart()
    onSourceReadyChanged: settleTimer.restart()

    function show(): void {
        visibilities.osd = true;
        timer.restart();
    }

    function showForAudio(): void {
        if (audioSettled)
            show();
    }

    Timer {
        id: settleTimer

        interval: 1000
        onTriggered: root.audioSettled = true
        onRunningChanged: {
            if (running)
                root.audioSettled = false;
        }
    }

    Component.onCompleted: {
        volume = Audio.volume;
        muted = Audio.muted;
        sourceVolume = Audio.sourceVolume;
        sourceMuted = Audio.sourceMuted;
        brightness = root.monitor?.brightness ?? 0;

        // Si el nodo ya estaba enlazado al crear el panel (p.ej. al recargar el
        // shell) no habrá cambio de `ready` que arranque el temporizador.
        if (sinkReady || sourceReady)
            settleTimer.restart();
    }

    visible: offsetScale < 1
    anchors.rightMargin: (-implicitWidth - 5 - sidebarOffset) * offsetScale
    implicitWidth: content.implicitWidth
    implicitHeight: content.implicitHeight
    opacity: 1 - offsetScale

    Behavior on offsetScale {
        Anim {
            type: Anim.DefaultSpatial
        }
    }

    Connections {
        function onMutedChanged(): void {
            root.showForAudio();
            root.muted = Audio.muted;
        }

        function onVolumeChanged(): void {
            root.showForAudio();
            root.volume = Audio.volume;
        }

        function onSourceMutedChanged(): void {
            root.showForAudio();
            root.sourceMuted = Audio.sourceMuted;
        }

        function onSourceVolumeChanged(): void {
            root.showForAudio();
            root.sourceVolume = Audio.sourceVolume;
        }

        target: Audio
    }

    Connections {
        function onBrightnessChanged(): void {
            // Las lecturas iniciales (y las relecturas tras detectar DDC) no son
            // cambios del usuario: sincroniza el valor sin desplegar el panel.
            if (!root.monitor?.initializing)
                root.show();
            root.brightness = root.monitor?.brightness ?? 0;
        }

        target: root.monitor
    }

    Timer {
        id: timer

        interval: root.Config.osd.hideDelay
        onTriggered: {
            if (!root.hovered)
                root.visibilities.osd = false;
        }
    }

    Loader {
        id: content

        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left

        asynchronous: true
        active: root.shouldBeActive || root.visible

        sourceComponent: Content {
            monitor: root.monitor
            visibilities: root.visibilities
            volume: root.volume
            muted: root.muted
            sourceVolume: root.sourceVolume
            sourceMuted: root.sourceMuted
            brightness: root.brightness
        }
    }
}
