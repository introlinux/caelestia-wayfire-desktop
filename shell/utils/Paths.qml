pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia
import Caelestia.Config

Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME")
    property string pictures: Quickshell.env("XDG_PICTURES_DIR") || `${home}/Pictures`
    property string videos: Quickshell.env("XDG_VIDEOS_DIR") || `${home}/Videos`

    // XDG user dirs are defined in ~/.config/user-dirs.dirs, not in the environment.
    Process {
        running: true
        command: ["bash", "-c", "source ~/.config/user-dirs.dirs && printf '%s\\n%s\\n' \"$XDG_VIDEOS_DIR\" \"$XDG_PICTURES_DIR\""]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split('\n');
                if (lines[0]) root.videos = lines[0];
                if (lines[1]) root.pictures = lines[1];
            }
        }
    }

    readonly property string data: `${Quickshell.env("XDG_DATA_HOME") || `${home}/.local/share`}/caelestia`
    readonly property string state: `${Quickshell.env("XDG_STATE_HOME") || `${home}/.local/state`}/caelestia`
    readonly property string cache: `${Quickshell.env("XDG_CACHE_HOME") || `${home}/.cache`}/caelestia`
    readonly property string config: `${Quickshell.env("XDG_CONFIG_HOME") || `${home}/.config`}/caelestia`

    readonly property string imagecache: `${cache}/imagecache`
    readonly property string notifimagecache: `${imagecache}/notifs`
    readonly property string wallsdir: Quickshell.env("CAELESTIA_WALLPAPERS_DIR") || absolutePath(GlobalConfig.paths.wallpaperDir)
    readonly property string recsdir: Quickshell.env("CAELESTIA_RECORDINGS_DIR") || `${videos}/Recordings`
    readonly property string screenshotsdir: Quickshell.env("CAELESTIA_SCREENSHOTS_DIR") || `${pictures}/Screenshots`
    readonly property string libdir: Quickshell.env("CAELESTIA_LIB_DIR") || "/usr/lib/caelestia"

    function toLocalFile(path: url): string {
        path = Qt.resolvedUrl(path);
        return path.toString() ? CUtils.toLocalFile(path) : "";
    }

    function absolutePath(path: string): string {
        return toLocalFile(path.replace(/~|(\$({?)HOME(}?))+/, home));
    }

    function shortenHome(path: string): string {
        return path.replace(home, "~");
    }
}
