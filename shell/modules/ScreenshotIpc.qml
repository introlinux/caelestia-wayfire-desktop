import Quickshell
import Quickshell.Io
import qs.services

// Screenshot service over IPC, e.g. for Wayfire keybindings:
//   qs -c caelestia ipc call screenshot take
// Referencing the Screenshot singleton here also instantiates it at
// startup, so its IPC surface is always available.
Scope {
    IpcHandler {
        target: "screenshot"

        function take(): void {
            Screenshot.take();
        }

        function region(): void {
            Screenshot.takeRegion();
        }

        function regionCopy(): void {
            Screenshot.takeRegionCopy();
        }
    }
}
