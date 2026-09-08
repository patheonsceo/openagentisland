import qs.modules.common.widgets
import qs.modules.common
import qs.services

QuickToggleButton {
    id: root
    toggled: Idle.keepAwakeWhenPluggedIn
    buttonIcon: "power"
    onClicked: {
        Idle.toggleKeepAwakeWhenPluggedIn()
    }
    StyledToolTip {
        text: Translation.tr("Never lock, blank or suspend while plugged in")
    }
}
