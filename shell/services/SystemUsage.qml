pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia.Config

Singleton {
    id: root

    // CPU properties
    property string cpuName: ""
    property real cpuPerc
    property real cpuTemp

    // GPU properties: listas paralelas alimentadas por caelestia-gpu-stats.
    // gpus (name/vendor) solo se reasigna si cambia la topología, para que los
    // Repeater de la UI no recreen sus delegados en cada refresco; gpuData
    // ({usage: 0-1 | null, temp: °C | null}) se reasigna en cada muestra.
    // GlobalConfig.services.gpuType filtra por vendor (nvidia/amd/intel; "none" oculta).
    property var gpus: []
    property var gpuData: []

    // Memory properties
    property real memUsed
    property real memTotal
    readonly property real memPerc: memTotal > 0 ? memUsed / memTotal : 0

    // Storage properties (aggregated)
    readonly property real storagePerc: {
        let totalUsed = 0;
        let totalSize = 0;
        for (const disk of disks) {
            totalUsed += disk.used;
            totalSize += disk.total;
        }
        return totalSize > 0 ? totalUsed / totalSize : 0;
    }

    // Individual disks: Array of { mount, used, total, free, perc }
    property var disks: []

    property real lastCpuIdle
    property real lastCpuTotal

    property int refCount

    function cleanCpuName(name: string): string {
        return name.replace(/\(R\)|\(TM\)|CPU|\d+(?:th|nd|rd|st) Gen |Core |Processor/gi, "").replace(/\s+/g, " ").trim();
    }

    function formatKib(kib: real): var {
        const mib = 1024;
        const gib = 1024 ** 2;
        const tib = 1024 ** 3;

        if (kib >= tib)
            return {
                value: kib / tib,
                unit: "TiB"
            };
        if (kib >= gib)
            return {
                value: kib / gib,
                unit: "GiB"
            };
        if (kib >= mib)
            return {
                value: kib / mib,
                unit: "MiB"
            };
        return {
            value: kib,
            unit: "KiB"
        };
    }

    Timer {
        running: root.refCount > 0
        interval: GlobalConfig.dashboard.resourceUpdateInterval
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            stat.reload();
            meminfo.reload();
            storage.running = true;
            gpuStats.running = true;
            sensors.running = true;
        }
    }

    // One-time CPU info detection (name)
    FileView {
        id: cpuinfoInit

        path: "/proc/cpuinfo"
        onLoaded: {
            const nameMatch = text().match(/model name\s*:\s*(.+)/);
            if (nameMatch)
                root.cpuName = root.cleanCpuName(nameMatch[1]);
        }
    }

    FileView {
        id: stat

        path: "/proc/stat"
        onLoaded: {
            const data = text().match(/^cpu\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)/);
            if (data) {
                const stats = data.slice(1).map(n => parseInt(n, 10));
                const total = stats.reduce((a, b) => a + b, 0);
                const idle = stats[3] + (stats[4] ?? 0);

                const totalDiff = total - root.lastCpuTotal;
                const idleDiff = idle - root.lastCpuIdle;
                root.cpuPerc = totalDiff > 0 ? (1 - idleDiff / totalDiff) : 0;

                root.lastCpuTotal = total;
                root.lastCpuIdle = idle;
            }
        }
    }

    FileView {
        id: meminfo

        path: "/proc/meminfo"
        onLoaded: {
            const data = text();
            root.memTotal = parseInt(data.match(/MemTotal: *(\d+)/)[1], 10) || 1;
            root.memUsed = (root.memTotal - parseInt(data.match(/MemAvailable: *(\d+)/)[1], 10)) || 0;
        }
    }

    Process {
        id: storage

        // Get physical disks with aggregated usage from their partitions
        // -J triggers JSON output. -b triggers bytes.
        command: ["lsblk", "-J", "-b", "-o", "NAME,SIZE,TYPE,FSUSED,FSSIZE,MOUNTPOINT"]

        stdout: StdioCollector {
            onStreamFinished: {
                const data = JSON.parse(text);
                const diskList = [];
                const seenDevices = new Set();

                // Helper to recursively sum usage from children (partitions, crypt, lvm)
                const aggregateUsage = dev => {
                    let used = 0;
                    let size = 0;
                    let isRoot = dev.mountpoint === "/" || (dev.mountpoints && dev.mountpoints.includes("/"));

                    if (!seenDevices.has(dev.name)) {
                        // lsblk returns null for empty/unformatted partitions, which parses to 0 here
                        used = parseInt(dev.fsused) || 0;
                        size = parseInt(dev.fssize) || 0;
                        seenDevices.add(dev.name);
                    }

                    if (dev.children) {
                        for (const child of dev.children) {
                            const stats = aggregateUsage(child);
                            used += stats.used;
                            size += stats.size;
                            if (stats.isRoot)
                                isRoot = true;
                        }
                    }
                    return {
                        used,
                        size,
                        isRoot
                    };
                };

                for (const dev of data.blockdevices) {
                    // Only process physical disks at the top level
                    if (dev.type === "disk" && !dev.name.startsWith("zram")) {
                        const stats = aggregateUsage(dev);

                        if (stats.size === 0) {
                            continue;
                        }

                        const total = stats.size;
                        const used = stats.used;

                        diskList.push({
                            mount: dev.name,
                            used: used / 1024      // KiB
                            ,
                            total: total / 1024    // KiB
                            ,
                            free: (total - used) / 1024,
                            perc: total > 0 ? used / total : 0,
                            hasRoot: stats.isRoot
                        });
                    }
                }

                // Sort by putting the disk with root first, then sort the rest alphabetically
                root.disks = diskList.sort((a, b) => {
                    if (a.hasRoot && !b.hasRoot)
                        return -1;
                    if (!a.hasRoot && b.hasRoot)
                        return 1;
                    return a.mount.localeCompare(b.mount);
                });
            }
        }
    }

    Process {
        id: gpuStats

        command: ["caelestia-gpu-stats"]
        stdout: StdioCollector {
            onStreamFinished: {
                let list;
                try {
                    list = JSON.parse(text);
                } catch (e) {
                    return;
                }

                const filter = (GlobalConfig.services.gpuType || "").toLowerCase();
                if (filter === "none")
                    list = [];
                else if (["nvidia", "amd", "intel"].includes(filter))
                    list = list.filter(g => g.vendor === filter);

                root.gpuData = list.map(g => ({
                    usage: g.usage !== null ? g.usage / 100 : null,
                    temp: g.temp
                }));

                const names = list.map(g => ({
                    name: g.name,
                    vendor: g.vendor
                }));
                if (JSON.stringify(names) !== JSON.stringify(root.gpus))
                    root.gpus = names;
            }
        }
    }

    Process {
        id: sensors

        command: ["sensors"]
        environment: ({
                LANG: "C.UTF-8",
                LC_ALL: "C.UTF-8"
            })
        stdout: StdioCollector {
            onStreamFinished: {
                let cpuTemp = text.match(/(?:Package id [0-9]+|Tdie):\s+((\+|-)[0-9.]+)(°| )C/);
                if (!cpuTemp)
                    // If AMD Tdie pattern failed, try fallback on Tctl
                    cpuTemp = text.match(/Tctl:\s+((\+|-)[0-9.]+)(°| )C/);

                if (cpuTemp)
                    root.cpuTemp = parseFloat(cpuTemp[1]);
            }
        }
    }
}
