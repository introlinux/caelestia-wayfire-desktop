pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.services

Variants {
    model: Screens.screens

    Scope {
        id: scope

        required property ShellScreen modelData

        Exclusions {
            screen: scope.modelData
            bar: content.bar
        }

        // Created before ContentWindow so it stacks below it within the Overlay layer.
        // Captures clicks on the desktop area when a drawer (launcher, session, sidebar) is open.
        DismissOverlay {
            screen: scope.modelData
            visibilities: content.visibilities
        }

        ContentWindow {
            id: content

            screen: scope.modelData
        }
    }
}
