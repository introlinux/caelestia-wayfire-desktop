import Quickshell
import qs.services

PersistentProperties {
    property bool bar
    property bool osd
    property bool session
    property bool launcher
    property bool dashboard
    property bool utilities
    property bool sidebar
    property bool windowControls
    property bool miniapps
    property bool appgrid

    // Sliding panels get a swoosh on open and close. The big, full-width ones
    // use the heavier sample; everything else the softer one.
    //
    // `bar` is deliberately silent: it is always on screen, not a sliding panel.
    onDashboardChanged: Sounds.slide(true)
    onLauncherChanged: Sounds.slide(true)
    onAppgridChanged: Sounds.slide(true)
    onOsdChanged: Sounds.slide(false)
    onSessionChanged: Sounds.slide(false)
    onUtilitiesChanged: Sounds.slide(false)
    onSidebarChanged: Sounds.slide(false)
    onWindowControlsChanged: Sounds.slide(false)
    onMiniappsChanged: Sounds.slide(false)
}
