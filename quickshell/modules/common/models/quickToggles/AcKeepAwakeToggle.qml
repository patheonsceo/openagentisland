import QtQuick
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

QuickToggleModel {
    name: Translation.tr("Awake on AC")

    toggled: Idle.keepAwakeWhenPluggedIn
    available: Idle.hasBattery
    icon: "power"
    statusText: !Idle.hasBattery ? Translation.tr("No battery") : (Idle.keepAwakeWhenPluggedIn ? (Idle.onAc ? Translation.tr("Active") : Translation.tr("On, unplugged")) : Translation.tr("Off"))
    mainAction: () => {
        Idle.toggleKeepAwakeWhenPluggedIn()
    }
    tooltipText: Translation.tr("Never lock, blank or suspend while plugged in")
}
