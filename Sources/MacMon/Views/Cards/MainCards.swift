import SwiftUI

// MARK: - 进程表

/// 列宽集中定义，表头与数据行共用。
/// 除最后一列外全部是固定宽度——柔性列会让每行各自计算宽度，导致列与列错位。
enum ProcessColumns {
    static let pid: CGFloat = 66
    static let name: CGFloat = 320
    static let app: CGFloat = 160
    static let user: CGFloat = 90
    static let cpu: CGFloat = 70
    static let mem: CGFloat = 84
    static let risk: CGFloat = 56
    static let spacing: CGFloat = 10
}

struct ProcessTableHeader: View {
    var compact: Bool = false

    var body: some View {
        HStack(spacing: ProcessColumns.spacing) {
            Text("PID").frame(width: ProcessColumns.pid, alignment: .leading)
            Text(L.t("进程"))
                .frame(
                    width: compact ? nil : ProcessColumns.name,
                    alignment: .leading
                )
                .frame(maxWidth: compact ? .infinity : nil, alignment: .leading)
            if !compact {
                Text(L.t("应用")).frame(width: ProcessColumns.app, alignment: .leading)
                Text(L.t("属主")).frame(width: ProcessColumns.user, alignment: .leading)
            }
            Text("CPU").frame(width: ProcessColumns.cpu, alignment: .trailing)
            Text(L.t("内存")).frame(width: ProcessColumns.mem, alignment: .trailing)
            Text(L.t("风险")).frame(width: ProcessColumns.risk, alignment: .trailing)
            if !compact {
                Text(L.t("可执行文件")).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .font(.system(size: TS.caption, weight: .medium))
        .foregroundStyle(Theme.dim)
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .background(Theme.surface)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.line).frame(height: 1)
        }
    }
}

struct ProcessLine: View {
    let row: ProcessRow
    var compact: Bool = false
    var allowKill: Bool = true
    let onKill: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: ProcessColumns.spacing) {
            Text(String(row.pid))
                .font(.system(size: TS.caption, design: .monospaced))
                .foregroundStyle(Theme.dim)
                .frame(width: ProcessColumns.pid, alignment: .leading)

            HStack(spacing: 5) {
                Text(row.name)
                    .font(.system(size: compact ? TS.caption : TS.body))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if !row.killable {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 7.5))
                        .foregroundStyle(Theme.dim)
                        .help(row.killBlockedReason ?? "")
                }
            }
            .frame(width: compact ? nil : ProcessColumns.name, alignment: .leading)
            .frame(maxWidth: compact ? .infinity : nil, alignment: .leading)

            if !compact {
                Text(row.appName ?? "—")
                    .font(.system(size: TS.caption))
                    .foregroundStyle(row.appName == nil ? Theme.dim : Theme.teal)
                    .lineLimit(1)
                    .frame(width: ProcessColumns.app, alignment: .leading)

                Text(row.user)
                    .font(.system(size: TS.caption))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(1)
                    .frame(width: ProcessColumns.user, alignment: .leading)
            }

            Text(String(format: "%.1f%%", row.cpu))
                .font(.system(size: TS.caption, weight: .medium, design: .monospaced))
                .foregroundStyle(row.cpu > 20 ? Theme.peach : Theme.muted)
                .frame(width: ProcessColumns.cpu, alignment: .trailing)

            Text(row.memRssBytes > 0 ? Fmt.bytes(row.memRssBytes) : "—")
                .font(.system(size: TS.caption, design: .monospaced))
                .foregroundStyle(Theme.dim)
                .frame(width: ProcessColumns.mem, alignment: .trailing)

            RiskBadge(risk: row.risk, compact: true)
                .frame(width: ProcessColumns.risk, alignment: .trailing)

            if !compact {
                Text(row.path.isEmpty ? "—" : row.path)
                    .font(.system(size: TS.micro, design: .monospaced))
                    .foregroundStyle(Theme.dim.opacity(0.9))
                    .lineLimit(1)
                    .truncationMode(.head)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, compact ? 4 : 7)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .frame(height: compact ? 26 : 32)
        .background(
            Rectangle().fill(hovering ? Theme.surface2.opacity(0.7) : .clear)
        )
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.line.opacity(0.4)).frame(height: 0.5)
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu {
            if !allowKill {
                EmptyView()
            } else if row.killable {
                Button(L.t("结束进程（SIGTERM）"), role: .destructive, action: onKill)
            } else {
                Text(row.killBlockedReason ?? L.t("不可结束"))
            }
        }
    }
}

// MARK: - 启动项

struct StartupLine: View {
    let item: StartupItem
    var showPath: Bool = true

    var body: some View {
        HStack(spacing: 10) {
            RiskBadge(risk: item.risk, compact: true)
                .frame(width: 44, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.label)
                    .font(.system(size: TS.body, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 6) {
                    Text(item.kind.label)
                        .font(.system(size: TS.micro))
                        .foregroundStyle(item.kind.isPrivileged ? Theme.peach : Theme.dim)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        // 和右侧 chip 同优先级，否则英文长标签会被 chip 挤成 0 宽而消失
                        .layoutPriority(1)
                    if item.runAtLoad { TagChip(text: L.t("开机"), color: Theme.blue).layoutPriority(1) }
                    if item.keepAlive { TagChip(text: L.t("保活"), color: Theme.purple).layoutPriority(1) }
                    if item.runsAtLoginWindow { TagChip(text: L.t("登录窗"), color: Theme.yellow).layoutPriority(1) }
                }
            }

            Spacer(minLength: 8)

            // 即使没有判定依据也要占位，否则这一列会消失、右侧路径整体左移
            Text(item.risk.level == .none ? "" : (item.risk.reasons.first?.text ?? ""))
                .font(.system(size: TS.micro))
                .foregroundStyle(Theme.riskColor(item.risk.level).opacity(0.85))
                .lineLimit(1)
                .frame(width: 166, alignment: .trailing)

            if showPath {
                Text(shortPath)
                    .font(.system(size: TS.micro, design: .monospaced))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .frame(width: 136, alignment: .trailing)
                    .help(item.programPath ?? item.plistPath)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.line.opacity(0.4)).frame(height: 0.5)
        }
    }

    private var shortPath: String {
        guard let path = item.programPath else { return L.t("无 Program") }
        if !item.programExists { return L.t("⚠ 文件不存在") }
        let parts = path.split(separator: "/")
        if parts.count <= 2 { return path }
        return "/" + parts.suffix(2).joined(separator: "/")
    }
}

struct TagChip: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 8.5, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 3).fill(color.opacity(0.13))
            )
            .fixedSize()
    }
}

// MARK: - 存储网络页

struct NetPanel: View {
    var net: NetMetrics
    var rxHistory: [Double]
    var txHistory: [Double]

    private var peak: Double {
        max(max(rxHistory.max() ?? 0, txHistory.max() ?? 0), 1024)
    }

    var body: some View {
        Card(title: L.t("网络"), subtitle: net.iface, accent: Theme.green) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 36) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L.t("↓ 下行"))
                            .font(.system(size: TS.caption))
                            .foregroundStyle(Theme.dim)
                        Text(Fmt.rate(net.rxSec))
                            .font(.system(size: 28, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.green)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L.t("↑ 上行"))
                            .font(.system(size: TS.caption))
                            .foregroundStyle(Theme.dim)
                        Text(Fmt.rate(net.txSec))
                            .font(.system(size: 28, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.blue)
                    }
                    Spacer()
                    HStack(spacing: 12) {
                        LegendDot(color: Theme.green, label: L.t("下行"))
                        LegendDot(color: Theme.blue, label: L.t("上行"))
                    }
                }

                ZStack {
                    Sparkline(values: txHistory, maxValue: peak, color: Theme.blue)
                    Sparkline(values: rxHistory, maxValue: peak, color: Theme.green)
                }
                .frame(maxHeight: .infinity)

                HStack {
                    Text(L.f("累计 ↓ %@", Fmt.bytes(net.rxTotal)))
                        .foregroundStyle(Theme.green.opacity(0.8))
                    Text("↑ \(Fmt.bytes(net.txTotal))")
                        .foregroundStyle(Theme.blue.opacity(0.8))
                    Spacer()
                    Text(String(format: L.t("峰值 %@/s"), Fmt.rate(peak)))
                        .foregroundStyle(Theme.dim)
                }
                .font(.system(size: TS.caption, design: .monospaced))
            }
        }
    }
}

struct DiskPanel: View {
    var disk: DiskMetrics

    private var barColor: Color {
        Theme.level(disk.usedPercent, warn: 80, danger: 92)
    }

    var body: some View {
        Card(title: L.t("磁盘"), subtitle: disk.volumeName, accent: Theme.peach) {
            VStack(spacing: 14) {
                Spacer(minLength: 0)

                HStack(alignment: .center, spacing: 26) {
                    RingGauge(
                        value: disk.usedPercent,
                        color: barColor,
                        lineWidth: 10,
                        caption: String(format: "%.1f%%", disk.usedPercent),
                        subcaption: L.t("已用")
                    )
                    .frame(width: 128, height: 128)

                    VStack(alignment: .leading, spacing: 11) {
                        StatBlock(
                            label: L.t("容量"),
                            value: Fmt.bytes(disk.usedBytes),
                            color: Theme.muted
                        )
                        Divider().overlay(Theme.line.opacity(0.6))
                        HStack(spacing: 30) {
                            StatBlock(label: L.t("读取"), value: Fmt.rate(disk.readSec), color: Theme.blue)
                            StatBlock(label: L.t("写入"), value: Fmt.rate(disk.writeSec), color: Theme.peach)
                        }
                    }

                    Spacer(minLength: 0)
                }

                StackBar(segments: [
                    .init(label: L.t("已用"), value: Double(disk.usedBytes), color: barColor),
                    .init(
                        label: L.t("可用"),
                        value: Double(max(disk.totalBytes - disk.usedBytes, 0)),
                        color: Theme.line
                    )
                ], height: 8)

                HStack {
                    Text(L.f("已用 %@", Fmt.bytes(disk.usedBytes)))
                        .foregroundStyle(barColor.opacity(0.85))
                    Spacer()
                    Text(L.f("总计 %@", Fmt.bytes(disk.totalBytes)))
                        .foregroundStyle(Theme.dim)
                }
                .font(.system(size: TS.caption, design: .monospaced))

                Spacer(minLength: 0)
            }
        }
    }
}

struct BatteryPanel: View {
    var battery: BatteryMetrics

    private var color: Color {
        if battery.percent <= 15 { return Theme.red }
        if battery.percent <= 30 { return Theme.yellow }
        return Theme.green
    }

    private var stateText: String {
        if battery.isCharging { return L.t("充电中") }
        if battery.acConnected { return L.t("已接电源") }
        return L.t("放电中")
    }

    var body: some View {
        Card(
            title: L.t("电池"),
            subtitle: stateText,
            accent: Theme.green
        ) {
            if battery.present {
                VStack(spacing: 14) {
                    Spacer(minLength: 0)

                    HStack(alignment: .center, spacing: 26) {
                        RingGauge(
                            value: battery.percent,
                            color: color,
                            lineWidth: 10,
                            caption: String(format: "%.0f%%", battery.percent),
                            subcaption: battery.acConnected ? L.t("已接电源") : L.t("使用电池")
                        )
                        .frame(width: 128, height: 128)

                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 30) {
                                StatBlock(
                                    label: L.t("健康度"),
                                    value: battery.healthPercent.map { String(format: "%.1f%%", $0) } ?? "—",
                                    color: Theme.green
                                )
                                StatBlock(
                                    label: L.t("循环"),
                                    value: L.f("%@ 次", battery.cycleCount),
                                    color: Theme.muted
                                )
                            }
                            Divider().overlay(Theme.line.opacity(0.6))
                            HStack(spacing: 30) {
                                StatBlock(label: L.t("温度"), value: Fmt.temp(battery.temperatureC), color: Theme.teal)
                                StatBlock(
                                    label: L.t("状态"),
                                    value: battery.condition ?? (battery.acConnected ? L.t("外接电源") : L.t("电池供电")),
                                    color: Theme.dim
                                )
                            }
                        }

                        Spacer(minLength: 0)
                    }

                    Spacer(minLength: 0)
                }
            } else {
                Text(L.t("未检测到电池"))
                    .font(.system(size: TS.body))
                    .foregroundStyle(Theme.dim)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

// MARK: - 预警（横向条）

struct AlertStrip: View {
    var alerts: [Alert]

    var body: some View {
        Card(
            title: L.t("预警"),
            subtitle: alerts.isEmpty ? L.t("无异常") : L.f("%@ 条", alerts.count),
            accent: Theme.red
        ) {
            if alerts.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Theme.green.opacity(0.75))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L.t("未触发预警"))
                            .font(.system(size: TS.caption, weight: .medium))
                            .foregroundStyle(Theme.text)
                        Text(L.t("温度、内存、磁盘均在阈值内"))
                            .font(.system(size: TS.micro))
                            .foregroundStyle(Theme.dim)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxHeight: .infinity, alignment: .center)
            } else {
                HStack(spacing: 0) {
                    ForEach(Array(alerts.prefix(3).enumerated()), id: \.element.id) { index, alert in
                        if index > 0 {
                            Rectangle()
                                .fill(Theme.line)
                                .frame(width: 1)
                                .padding(.vertical, 2)
                                .padding(.horizontal, 14)
                        }
                        HStack(alignment: .top, spacing: 7) {
                            StatusDot(
                                color: alert.level.color,
                                size: 5
                            )
                            .padding(.top, 5)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(alert.title)
                                    .font(.system(size: TS.caption, weight: .medium))
                                    .foregroundStyle(Theme.text)
                                    .lineLimit(1)
                                Text(alert.detail)
                                    .font(.system(size: TS.micro))
                                    .foregroundStyle(Theme.dim)
                                    .lineLimit(2)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxHeight: .infinity, alignment: .center)
            }
        }
    }
}

// MARK: - 设备信息

struct DevicePanel: View {
    var meta: SystemMeta
    var uptime: String
    var updatedAt: Date

    var body: some View {
        Card(title: L.t("设备"), accent: Theme.sapphire) {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(minimum: 130), alignment: .leading),
                    GridItem(.flexible(minimum: 120), alignment: .leading)
                ],
                alignment: .leading,
                spacing: 9
            ) {
                kv(L.t("主机"), meta.hostname)
                kv(L.t("型号"), meta.modelId)
                kv(L.t("芯片"), meta.chip)
                kv(L.t("核心"), L.f("%@ 核 · P%@/E%@", meta.cores, meta.perfCores, meta.effCores))
                kv(L.t("系统"), meta.osVersion)
                kv(L.t("内存"), String(format: "%.0f GB", Double(meta.memTotalBytes) / 1_073_741_824))
                kv(L.t("已运行"), uptime)
                kv(L.t("更新"), updatedAt.formatted(date: .omitted, time: .standard))
            }
        }
    }

    private func kv(_ label: String, _ value: String) -> some View {
        HStack(spacing: 7) {
            Text(label)
                .font(.system(size: TS.micro))
                .foregroundStyle(Theme.dim)
                // 英文标签（Memory / System / Uptime）比中文长，36pt 会被截成 "Memo…"
                .frame(width: 52, alignment: .leading)
                .lineLimit(1)
            Text(value)
                .font(.system(size: TS.caption, design: .monospaced))
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

// MARK: - 预警（纵向）

struct AlertPanel: View {
    var alerts: [Alert]
    var limit: Int = 4

    var body: some View {
        Card(
            title: L.t("预警"),
            subtitle: alerts.isEmpty ? L.t("无异常") : L.f("%@ 条", alerts.count),
            accent: Theme.red
        ) {
            if alerts.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(Theme.green.opacity(0.7))
                    Text(L.t("未触发预警"))
                        .font(.system(size: TS.body))
                        .foregroundStyle(Theme.muted)
                    Text(L.t("温度、内存、磁盘均在阈值内"))
                        .font(.system(size: TS.micro))
                        .foregroundStyle(Theme.dim)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(alerts.prefix(limit)) { alert in
                        HStack(alignment: .top, spacing: 8) {
                            StatusDot(
                                color: alert.level.color,
                                size: 5
                            )
                            .padding(.top, 5)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(alert.title)
                                    .font(.system(size: TS.caption, weight: .medium))
                                    .foregroundStyle(Theme.text)
                                Text(alert.detail)
                                    .font(.system(size: TS.micro))
                                    .foregroundStyle(Theme.dim)
                                    .lineLimit(2)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }
}
