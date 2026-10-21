import SwiftUI

// MARK: - 性能页：处理器

struct PerfCpuCard: View {
    var cpu: CPUMetrics
    var history: [Double]

    var body: some View {
        Card(
            title: L.t("处理器"),
            subtitle: L.f("%@ · %@ 核", cpu.brand, cpu.cores),
            accent: Theme.blue
        ) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 24) {
                    RingGauge(
                        value: cpu.total,
                        color: Theme.blue,
                        lineWidth: 11,
                        caption: String(format: "%.1f%%", cpu.total),
                        subcaption: L.t("总占用")
                    )
                    .frame(width: 152, height: 152)

                    VStack(alignment: .leading, spacing: 11) {
                        HStack(spacing: 26) {
                            StatBlock(label: L.t("用户"), value: String(format: "%.1f%%", cpu.user), color: Theme.blue)
                            StatBlock(label: L.t("系统"), value: String(format: "%.1f%%", cpu.system), color: Theme.purple)
                        }
                        Divider().overlay(Theme.line.opacity(0.6))
                        HStack(spacing: 26) {
                            StatBlock(
                                label: L.t("负载"),
                                value: String(format: "%.2f  %.2f  %.2f", cpu.loadAvg.0, cpu.loadAvg.1, cpu.loadAvg.2),
                                color: Theme.muted
                            )
                            StatBlock(
                                label: L.t("核心"),
                                value: "P\(cpu.perfCores) / E\(cpu.effCores)",
                                color: Theme.teal
                            )
                        }
                    }

                    Spacer(minLength: 0)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(L.t("每核占用"))
                            .font(.system(size: TS.caption))
                            .foregroundStyle(Theme.dim)
                        Spacer()
                        HStack(spacing: 10) {
                            LegendDot(color: Theme.blue, label: L.t("性能核"))
                            LegendDot(color: Theme.green, label: L.t("能效核"))
                        }
                    }
                    CoreBars(cores: cpu.perCore)
                        .frame(height: 112)
                }

                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(L.t("负载走势"))
                            .font(.system(size: TS.caption))
                            .foregroundStyle(Theme.dim)
                        Spacer()
                        Text(String(format: L.t("峰值 %.1f%%"), history.max() ?? 0))
                            .font(.system(size: TS.caption, design: .monospaced))
                            .foregroundStyle(Theme.dim)
                    }
                    Sparkline(
                        values: history,
                        maxValue: max(history.max() ?? 0, 25),
                        color: Theme.blue
                    )
                    .frame(maxHeight: .infinity)
                }
            }
        }
    }
}

// MARK: - 性能页：温度

struct PerfTempCard: View {
    var temp: TempStatus
    var history: [Double]

    private var display: Double { temp.primaryC ?? 0 }
    private var color: Color {
        if display >= 90 { return Theme.red }
        if display >= 75 { return Theme.yellow }
        return Theme.teal
    }

    var body: some View {
        Card(title: L.t("温度"), subtitle: temp.source, accent: Theme.teal) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 26) {
                    RingGauge(
                        value: min(max(display / 110 * 100, 0), 100),
                        color: color,
                        lineWidth: 11,
                        caption: Fmt.temp(temp.primaryC),
                        subcaption: "CPU"
                    )
                    .frame(width: 118, height: 118)

                    VStack(alignment: .leading, spacing: 11) {
                        HStack(spacing: 34) {
                            StatBlock(label: "SoC", value: Fmt.temp(temp.socC), color: Theme.teal)
                            StatBlock(label: L.t("电池"), value: Fmt.temp(temp.batteryC), color: Theme.green)
                        }
                        Divider().overlay(Theme.line.opacity(0.6))
                        HStack(spacing: 34) {
                            StatBlock(label: L.t("风扇"), value: fanText, color: Theme.muted)
                            StatBlock(
                                label: L.t("传感器"),
                                value: temp.sensorCount > 0 ? L.f("%@ 路", temp.sensorCount) : "—",
                                color: Theme.muted
                            )
                        }
                    }

                    Spacer(minLength: 0)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(L.t("温度走势"))
                            .font(.system(size: TS.caption))
                            .foregroundStyle(Theme.dim)
                        Text(scaleLabel)
                            .font(.system(size: TS.micro, design: .monospaced))
                            .foregroundStyle(Theme.dim.opacity(0.75))
                        Spacer()
                        Text(String(format: L.t("峰值 %@"), Fmt.temp(history.max())))
                            .font(.system(size: TS.caption, design: .monospaced))
                            .foregroundStyle(Theme.dim)
                    }
                    Sparkline(
                        values: history,
                        maxValue: scale.upper,
                        minValue: scale.lower,
                        color: color
                    )
                    .frame(maxHeight: .infinity)
                }
                .frame(maxHeight: .infinity)
            }
        }
    }

    /// 自适应量程后必须把区间标出来，否则 2℃ 的正常波动看起来像剧烈起伏
    private var scale: (lower: Double, upper: Double) {
        TempScale.range(for: history, current: temp.primaryC)
    }

    private var scaleLabel: String {
        TempScale.label(scale)
    }

    private var fanText: String {
        if temp.fanRpm.isEmpty { return L.t("待机") }
        return temp.fanRpm.map { String(format: "%.0f", $0) }.joined(separator: " / ") + " RPM"
    }
}

// MARK: - 性能页：内存

struct PerfMemCard: View {
    var mem: MemMetrics
    var history: [Double]

    var body: some View {
        Card(title: L.t("内存"), subtitle: L.f("压力 %@", mem.pressure.label), accent: Theme.purple) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(String(format: "%.1f", Double(mem.usedBytes) / 1_073_741_824))
                        .font(.system(size: TS.metric, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.text)
                        .contentTransition(.numericText())
                    Text("/ \(String(format: "%.0f GB", Double(mem.totalBytes) / 1_073_741_824))")
                        .font(.system(size: TS.body, design: .monospaced))
                        .foregroundStyle(Theme.dim)
                    Spacer()
                    Text(String(format: "%.0f%%", mem.usedPercent))
                        .font(.system(size: 18, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.level(mem.usedPercent))
                }

                StackBar(segments: [
                    .init(label: L.t("App 内存"), value: Double(mem.appBytes), color: Theme.purple),
                    .init(label: L.t("固定"), value: Double(mem.wiredBytes), color: Theme.blue),
                    .init(label: L.t("压缩"), value: Double(mem.compressedBytes), color: Theme.peach),
                    .init(label: L.t("已缓存"), value: Double(mem.cachedBytes), color: Theme.surface2),
                    // 空闲必须用 freeBytes：availableBytes 是「总量 − 已用」，里面还含着缓存，
                    // 再画一段缓存就会重复计入，整条比例会失真
                    .init(label: L.t("空闲"), value: Double(mem.freeBytes), color: Theme.line)
                ], height: 10)

                // 两列排布：新增了「已缓存」但总行数仍为 3，
                // 避免在 680pt 最小窗口下把下方走势图挤没
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(minimum: 140), spacing: 26, alignment: .leading),
                        GridItem(.flexible(minimum: 140), spacing: 0, alignment: .leading)
                    ],
                    alignment: .leading,
                    spacing: 6
                ) {
                    MiniRow(
                        label: L.t("App 内存"),
                        value: Fmt.bytes(mem.appBytes),
                        color: Theme.purple,
                        hint: L.t("应用内存：所有进程实际占用的匿名页（栈、堆、对象），已扣掉可被系统随时回收的可清除内存。")
                    )
                    MiniRow(
                        label: L.t("已缓存"),
                        value: Fmt.bytes(mem.cachedBytes),
                        color: Theme.muted,
                        hint: L.t("文件缓存：从磁盘读过的文件内容留在内存里，随时可丢弃，紧张时会自动释放，不算真正占用。")
                    )
                    MiniRow(
                        label: L.t("固定"),
                        value: Fmt.bytes(mem.wiredBytes),
                        color: Theme.blue,
                        hint: L.t("固定内存（wired memory）就是活动监视器里的「联动内存」：已锁定在物理内存中，不可换出、不可压缩，主要由内核、驱动和 IO 缓冲占用。")
                    )
                    MiniRow(
                        label: L.t("压缩"),
                        value: Fmt.bytes(mem.compressedBytes),
                        color: Theme.peach,
                        hint: L.t("压缩内存：物理内存吃紧时，系统把不活跃的页压缩后存放，省出空间；解压要花一点 CPU。")
                    )
                    MiniRow(
                        label: L.t("交换"),
                        value: mem.swapUsedBytes > 0 ? Fmt.bytes(mem.swapUsedBytes) : L.t("未使用"),
                        color: mem.swapUsedBytes > 0 ? Theme.yellow : Theme.dim,
                        hint: L.t("交换空间：连压缩都放不下时写进磁盘的那部分。长期不为 0 说明物理内存已经不够用。")
                    )
                    Color.clear.frame(height: 12)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(L.t("占用走势"))
                            .font(.system(size: TS.caption))
                            .foregroundStyle(Theme.dim)
                        Spacer()
                        Text(String(format: L.t("峰值 %.0f%%"), history.max() ?? 0))
                            .font(.system(size: TS.caption, design: .monospaced))
                            .foregroundStyle(Theme.dim)
                    }
                    Sparkline(values: history, maxValue: 100, color: Theme.purple)
                        .frame(maxHeight: .infinity)
                }
                .frame(maxHeight: .infinity)
            }
        }
    }
}

// MARK: - 零件

struct StatBlock: View {
    var label: String
    var value: String
    var color: Color = Theme.muted

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: TS.caption))
                .foregroundStyle(Theme.dim)
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

struct MiniRow: View {
    var label: String
    var value: String
    var color: Color = Theme.muted
    var hint: String? = nil

    var body: some View {
        // hint 为空时不要挂 .help("")：AppKit 会留下一个空 tooltip 命中区，
        // 鼠标划过会闪一下空气泡
        if let hint {
            row.help(hint)
        } else {
            row
        }
    }

    private var row: some View {
        HStack {
            Text(label)
                .font(.system(size: TS.caption))
                .foregroundStyle(Theme.dim)
            Spacer()
            Text(value)
                .font(.system(size: TS.caption, weight: .medium, design: .monospaced))
                .foregroundStyle(color)
        }
        // 整行都可命中：不加时只有文字字形本身触发 tooltip，
        // 鼠标停在 label 与 value 之间的空白处不弹说明
        .contentShape(Rectangle())
    }
}

struct LegendDot: View {
    var color: Color
    var label: String

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(label)
                .font(.system(size: TS.micro))
                .foregroundStyle(Theme.dim)
        }
    }
}
