pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Simple polled resource usage service with RAM, Swap, and CPU usage.
 */
Singleton {
    id: root
	property real memoryTotal: 1
	property real memoryFree: 0
	property real memoryUsed: memoryTotal - memoryFree
    property real memoryUsedPercentage: memoryUsed / memoryTotal
    property real swapTotal: 1
	property real swapFree: 0
	property real swapUsed: swapTotal - swapFree
    property real swapUsedPercentage: swapTotal > 0 ? (swapUsed / swapTotal) : 0
    property real cpuUsage: 0
    property var previousCpuStats
    // CPU package temperature in °C (0 = no sensor discovered yet / unsupported).
    // cpuTempPath is the sysfs file (millidegrees) found once by findTempProc below.
    property real cpuTemperature: 0
    property string cpuTempPath: ""

    property string maxAvailableMemoryString: kbToGbString(ResourceUsage.memoryTotal)
    property string maxAvailableSwapString: kbToGbString(ResourceUsage.swapTotal)
    property string maxAvailableCpuString: "--"

    readonly property int historyLength: Config?.options.resources.historyLength ?? 60
    property list<real> cpuUsageHistory: []
    property list<real> memoryUsageHistory: []
    property list<real> swapUsageHistory: []

    function kbToGbString(kb) {
        return (kb / (1024 * 1024)).toFixed(1) + " GB";
    }

    // Adaptive size string: shows MB below 1 GB, GB above. Fixes "frozen" readouts
    // for zram/zswap swap, where usage lives in the low-MB range and GB@1-decimal
    // always rounds to "0.0 GB" even as the real value moves.
    function kbToSizeString(kb) {
        const mb = kb / 1024;
        if (mb < 1024) return mb.toFixed(mb < 100 ? 1 : 0) + " MB";
        return (mb / 1024).toFixed(1) + " GB";
    }

    function updateMemoryUsageHistory() {
        memoryUsageHistory = [...memoryUsageHistory, memoryUsedPercentage]
        if (memoryUsageHistory.length > historyLength) {
            memoryUsageHistory.shift()
        }
    }
    function updateSwapUsageHistory() {
        swapUsageHistory = [...swapUsageHistory, swapUsedPercentage]
        if (swapUsageHistory.length > historyLength) {
            swapUsageHistory.shift()
        }
    }
    function updateCpuUsageHistory() {
        cpuUsageHistory = [...cpuUsageHistory, cpuUsage]
        if (cpuUsageHistory.length > historyLength) {
            cpuUsageHistory.shift()
        }
    }
    function updateHistories() {
        updateMemoryUsageHistory()
        updateSwapUsageHistory()
        updateCpuUsageHistory()
    }

	Timer {
		interval: 1
        running: true 
        repeat: true
		onTriggered: {
            // Reload files
            fileMeminfo.reload()
            fileStat.reload()

            // Parse memory and swap usage
            const textMeminfo = fileMeminfo.text()
            memoryTotal = Number(textMeminfo.match(/MemTotal: *(\d+)/)?.[1] ?? 1)
            memoryFree = Number(textMeminfo.match(/MemAvailable: *(\d+)/)?.[1] ?? 0)
            swapTotal = Number(textMeminfo.match(/SwapTotal: *(\d+)/)?.[1] ?? 1)
            swapFree = Number(textMeminfo.match(/SwapFree: *(\d+)/)?.[1] ?? 0)

            // Parse CPU usage
            const textStat = fileStat.text()
            const cpuLine = textStat.match(/^cpu\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)/)
            if (cpuLine) {
                const stats = cpuLine.slice(1).map(Number)
                const total = stats.reduce((a, b) => a + b, 0)
                const idle = stats[3]

                if (previousCpuStats) {
                    const totalDiff = total - previousCpuStats.total
                    const idleDiff = idle - previousCpuStats.idle
                    cpuUsage = totalDiff > 0 ? (1 - idleDiff / totalDiff) : 0
                }

                previousCpuStats = { total, idle }
            }

            // Parse CPU temperature (sysfs reports millidegrees → °C).
            if (root.cpuTempPath.length > 0) {
                fileTemp.reload()
                const milli = Number(fileTemp.text())
                if (milli > 0) cpuTemperature = milli / 1000
            }

            root.updateHistories()
            interval = Config.options?.resources?.updateInterval ?? 3000
        }
	}

	FileView { id: fileMeminfo; path: "/proc/meminfo" }
    FileView { id: fileStat; path: "/proc/stat" }
    FileView { id: fileTemp; path: root.cpuTempPath }

    // Discover the best CPU-temperature sysfs file ONCE at startup, then read it
    // cheaply via fileTemp each tick (no per-tick process spawn). Prefers the CPU
    // package sensor across Intel (coretemp "Package id 0"), AMD (k10temp/zenpower
    // Tctl/Tdie) and ARM (cpu_thermal); falls back to the x86_pkg_temp / acpitz
    // thermal zone so it degrades gracefully on unknown hardware.
    Process {
        id: findTempProc
        environment: ({ LANG: "C", LC_ALL: "C" })
        command: ["bash", "-c", `
            for d in /sys/class/hwmon/hwmon*; do
              [ -r "$d/name" ] || continue
              case "$(cat "$d/name")" in
                coretemp|k10temp|k8temp|zenpower|cpu_thermal)
                  for lbl in "$d"/temp*_label; do
                    [ -e "$lbl" ] || continue
                    case "$(cat "$lbl")" in
                      "Package id 0"|Tctl|Tdie|Tccd1)
                        inp="\${lbl%_label}_input"
                        [ -r "$inp" ] && { echo "$inp"; exit 0; } ;;
                    esac
                  done
                  [ -r "$d/temp1_input" ] && { echo "$d/temp1_input"; exit 0; } ;;
              esac
            done
            for z in /sys/class/thermal/thermal_zone*; do
              [ -r "$z/type" ] || continue
              case "$(cat "$z/type")" in
                x86_pkg_temp|cpu-thermal|cpu_thermal|TCPU)
                  echo "$z/temp"; exit 0 ;;
              esac
            done
            [ -r /sys/class/thermal/thermal_zone0/temp ] && echo /sys/class/thermal/thermal_zone0/temp
        `]
        running: true
        stdout: StdioCollector {
            id: tempCollector
            onStreamFinished: {
                const p = tempCollector.text.trim()
                if (p.length > 0) root.cpuTempPath = p
            }
        }
    }

    Process {
        id: findCpuMaxFreqProc
        environment: ({
            LANG: "C",
            LC_ALL: "C"
        })
        command: ["bash", "-c", "lscpu | grep 'CPU max MHz' | awk '{print $4}'"]
        running: true
        stdout: StdioCollector {
            id: outputCollector
            onStreamFinished: {
                root.maxAvailableCpuString = (parseFloat(outputCollector.text) / 1000).toFixed(0) + " GHz"
            }
        }
    }
}
