import Foundation

/// 无界面诊断：验证各原生采集器在真机上的实际输出。
enum Diagnostics {

    static func run() {
        let out = FileHandle.standardOutput

        func line(_ text: String) {
            out.write(Data((text + "\n").utf8))
        }

        line("=== MacMon 采集诊断 ===")

        // CPU（需要两次采样才有意义）
        let cpu = CPUCollector()
        _ = cpu.sample()
        Thread.sleep(forTimeInterval: 0.6)
        let cpuMetrics = cpu.sample()
        line(String(
            format: "CPU  : 总 %.1f%%  用户 %.1f%%  系统 %.1f%%  核数 %d (P%d/E%d)",
            cpuMetrics.total, cpuMetrics.user, cpuMetrics.system,
            cpuMetrics.cores, cpuMetrics.perfCores, cpuMetrics.effCores
        ))
        let perCore = cpuMetrics.perCore
            .map { String(format: "%@%d:%.0f", $0.cluster.rawValue, $0.index, $0.load) }
            .joined(separator: "  ")
        line("      \(perCore)")
        line(String(format: "      负载 %.2f %.2f %.2f  型号 %@",
                    cpuMetrics.loadAvg.0, cpuMetrics.loadAvg.1, cpuMetrics.loadAvg.2, cpuMetrics.brand))

        // 内存
        let mem = MemoryCollector().sample()
        line(String(
            format: "内存  : 已用 %.2f / %.1f GB (%.1f%%)  App %.2f 缓存 %.2f 固定 %.2f 压缩 %.2f 可清除 %.2f 空闲 %.2f  压力 %@",
            Double(mem.usedBytes) / 1_073_741_824,
            Double(mem.totalBytes) / 1_073_741_824,
            mem.usedPercent,
            Double(mem.appBytes) / 1_073_741_824,
            Double(mem.cachedBytes) / 1_073_741_824,
            Double(mem.wiredBytes) / 1_073_741_824,
            Double(mem.compressedBytes) / 1_073_741_824,
            Double(mem.purgeableBytes) / 1_073_741_824,
            Double(mem.freeBytes) / 1_073_741_824,
            mem.pressure.label
        ))
        // 自检：App + 可清除 + 缓存 + 固定 + 压缩 + 空闲 应当等于物理内存（容差 1%）
        let parts = mem.appBytes + mem.purgeableBytes + mem.cachedBytes
            + mem.wiredBytes + mem.compressedBytes + mem.freeBytes
        let drift = mem.totalBytes > 0
            ? (Double(parts) - Double(mem.totalBytes)) / Double(mem.totalBytes) * 100
            : 0
        line(String(
            format: "        自检: 各项合计 %.2f GB，与物理内存偏差 %+.1f%%",
            Double(parts) / 1_073_741_824,
            drift
        ))

        // 电池
        let battery = BatteryCollector().sample()
        if battery.present {
            line(String(
                format: "电池  : %.0f%%  健康 %@  循环 %d  %.1f°C  充电中 %@",
                battery.percent,
                battery.healthPercent.map { String(format: "%.1f%%", $0) } ?? "—",
                battery.cycleCount,
                battery.temperatureC ?? 0,
                battery.isCharging ? "是" : "否"
            ))
        } else {
            line("电池  : 未检测到")
        }

        // 温度（含全部传感器 dump）
        let temp = TemperatureCollector()
        let status = temp.sample(batteryFallback: battery.temperatureC)
        line("温度  : CPU \(Fmt.temp(status.cpuC))  SoC \(Fmt.temp(status.socC))  GPU \(Fmt.temp(status.gpuC))  电池 \(Fmt.temp(status.batteryC))")
        line("      来源 \(status.source)")
        let sensors = temp.dumpSensors()
        if sensors.isEmpty {
            line("      ⚠️ 未枚举到任何 HID 温度传感器")
        } else {
            for sensor in sensors.prefix(24) {
                line("      · \(sensor)")
            }
            if sensors.count > 24 { line("      … 共 \(sensors.count) 路") }
        }

        // 磁盘
        let disk1 = DiskCollector()
        _ = disk1.sample()
        Thread.sleep(forTimeInterval: 0.5)
        let disk = disk1.sample()
        line(String(
            format: "磁盘  : %@  %.1f%% (%.1f/%.1f GB)  读 %@  写 %@",
            disk.volumeName, disk.usedPercent,
            Double(disk.usedBytes) / 1_073_741_824,
            Double(disk.totalBytes) / 1_073_741_824,
            Fmt.rate(disk.readSec), Fmt.rate(disk.writeSec)
        ))

        // 网络
        let net1 = NetworkCollector()
        _ = net1.sample()
        Thread.sleep(forTimeInterval: 0.5)
        let net = net1.sample()
        line("网络  : \(net.iface)  下行 \(Fmt.rate(net.rxSec))  上行 \(Fmt.rate(net.txSec))")

        // 进程
        let proc = ProcessCollector()
        _ = proc.sample()
        Thread.sleep(forTimeInterval: 0.6)
        let rows = proc.sample()
        let totalCpu = rows.reduce(0) { $0 + $1.cpu }
        line("进程  : \(rows.count) 个  合计 CPU \(String(format: "%.1f", totalCpu))%")
        let top = rows.sorted { $0.cpu > $1.cpu }.prefix(6)
        for item in top {
            line(String(
                format: "      %6d  %5.1f%%  %7@  %@",
                item.pid, item.cpu, Fmt.bytes(item.memRssBytes), item.name
            ))
        }
        let withPath = rows.filter { !$0.path.isEmpty }.count
        line("      有可执行路径的进程：\(withPath) / \(rows.count)")

        // 探针：确认 root 进程（如 WindowServer）的三种读取途径是否可用
        line("--- 系统进程可读性探针 ---")
        for probeName in ["WindowServer", "launchd", "kernel_task"] {
            guard let target = rows.first(where: { $0.name == probeName }) else {
                line("      \(probeName)：未在列表中找到")
                continue
            }
            let taskOK = ProcessProbe.taskInfo(pid: target.pid)
            let rusageOK = ProcessProbe.rusage(pid: target.pid)
            let pct = ProcessProbe.pctCpu(pid: target.pid)
            line("      \(probeName) pid=\(target.pid) uid=\(target.user)  "
                 + "taskinfo=\(taskOK ? "可读" : "拒绝")  rusage=\(rusageOK ? "可读" : "拒绝")  p_pctcpu=\(pct)")
        }

        line("=== 完 ===")
    }
}
