//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic

// Standalone entry for the "Agent Island" project launcher. Run it with:
//   qs --path ~/Projects/openagentisland/quickshell/agentIsland.qml
// It lives inside the config root so it reuses the shell's theme/widgets, but is
// a separate window app independent of the island shell.
import QtQuick
import Quickshell
import "modules/ii/agentIsland"

ShellRoot {
    AgentIslandWindow {}
}
