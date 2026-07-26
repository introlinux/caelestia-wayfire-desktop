pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia.Config
import Caelestia.Models
import qs.services
import qs.utils

Searcher {
    id: root

    readonly property string currentNamePath: `${Paths.state}/wallpaper/path.txt`
    readonly property list<string> smartArg: GlobalConfig.services.smartScheme ? [] : ["--no-smart"]

    property bool showPreview: false
    readonly property string current: showPreview ? previewPath : actualCurrent
    property string previewPath
    property string actualCurrent
    property bool previewColourLock
    property bool isCovered: false

    Process {
        id: windowWatchProc
        running: true
        command: ["caelestia-window-watch"]
        stdout: SplitParser {
            onRead: data => {
                const text = data.trim();
                if (text.startsWith("COVERED:")) {
                    root.isCovered = text.slice(8).trim() === "1";
                }
            }
        }
        onExited: windowWatchRestart.restart()
    }

    Timer {
        id: windowWatchRestart
        interval: 2000
        onTriggered: windowWatchProc.running = true
    }

    function setWallpaper(path: string): void {
        actualCurrent = path;
        Quickshell.execDetached(["caelestia", "wallpaper", "-f", path, ...smartArg]);
    }

    function preview(path: string): void {
        previewPath = path;
        showPreview = true;

        if (Colours.scheme === "dynamic")
            getPreviewColoursProc.running = true;
    }

    function stopPreview(): void {
        showPreview = false;
        if (!previewColourLock)
            Colours.showPreview = false;
    }

    list: wallpapers.entries
    key: "relativePath"
    useFuzzy: GlobalConfig.launcher.useFuzzy.wallpapers
    extraOpts: useFuzzy ? ({}) : ({
            forward: false
        })

    IpcHandler {
        function get(): string {
            return root.actualCurrent;
        }

        function set(path: string): void {
            root.setWallpaper(path);
        }

        function list(): string {
            return root.list.map(w => w.path).join("\n");
        }

        target: "wallpaper"
    }

    FileView {
        path: root.currentNamePath
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            root.actualCurrent = text().trim();
            root.previewColourLock = false;
        }
    }

    function isVideo(path: string): bool {
        if (!path) return false;
        const lower = path.toLowerCase();
        return lower.endsWith(".mp4") || lower.endsWith(".webm") || lower.endsWith(".mkv") || lower.endsWith(".mov") || lower.endsWith(".avi");
    }

    // Preview frames for video wallpapers, resolved once per path. Resolving
    // this inside the delegates re-spawned a ~165ms process every time an item
    // scrolled back into the launcher carousel, which destroys and recreates
    // its delegates on every step: scroll faster than that and the thumbnail
    // never arrived. Requests are queued so a wide grid does not fork a pile of
    // interpreters at once.
    property var videoThumbs: ({})
    readonly property var thumbQueue: []

    function requestVideoThumb(path: string): void {
        if (!path || !isVideo(path) || videoThumbs[path] !== undefined)
            return;

        videoThumbs = Object.assign({}, videoThumbs, {
            [path]: ""
        }); // marca en curso
        thumbQueue.push(path);
        thumbProc.startNext();
    }

    Process {
        id: thumbProc

        property string current

        function startNext(): void {
            if (running || root.thumbQueue.length === 0)
                return;

            current = root.thumbQueue.shift();
            command = ["caelestia", "wallpaper", "-T", current];
            running = true;
        }

        stdout: SplitParser {
            onRead: data => {
                const resolved = data.trim();
                if (resolved)
                    root.videoThumbs = Object.assign({}, root.videoThumbs, {
                        [thumbProc.current]: resolved
                    });
            }
        }

        onExited: code => {
            // qmllint disable signal-handler-parameters
            if (code !== 0)
                console.warn(`Wallpapers: 'caelestia wallpaper -T' falló (${code}) para ${thumbProc.current} — ¿CLI sin el parche de fondos animados?`);
            Qt.callLater(() => thumbProc.startNext());
        }
    }

    FileSystemModel {
        id: wallpapers

        recursive: true
        path: Paths.wallsdir
        filter: FileSystemModel.Files
        nameFilters: ["*.png", "*.jpg", "*.jpeg", "*.webp", "*.gif", "*.PNG", "*.JPG", "*.JPEG", "*.WEBP", "*.GIF", "*.mp4", "*.webm", "*.mkv", "*.mov", "*.avi", "*.MP4", "*.WEBM", "*.MKV", "*.MOV", "*.AVI"]
    }

    Process {
        id: getPreviewColoursProc

        command: ["caelestia", "wallpaper", "-p", root.previewPath, ...root.smartArg]
        stdout: StdioCollector {
            onStreamFinished: {
                Colours.load(text, true);
                Colours.showPreview = true;
            }
        }
    }
}
