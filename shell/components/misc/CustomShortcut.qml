import QtQuick

// GlobalShortcut (Hyprland-specific) not available on Wayfire.
// Shortcuts are handled via wayfire.ini [command] bindings + qs-caelestia IPC.
Item {
    property string name
    property string description
    signal pressed
    signal released
}
