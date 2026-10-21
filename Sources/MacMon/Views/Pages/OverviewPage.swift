import SwiftUI

/// 概览：4 张 hero 卡 + Top 进程 / 启动项 + 预警 / 设备信息
struct OverviewPage: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        PageScaffold(page: .overview) { size in
            let gap: CGFloat = 14
            let availH = max(size.height - 46 - gap, 340)

            // 高度按比例分配：hero 定高，其余留给下面两行，
            // 避免「上面挤成一团、下面一大片空白」。
            let heroH = min(max(availH * 0.34, 200), 260)
            let rest = max(availH - heroH - gap, 220)
            let stripH = min(max(rest * 0.34, 100), 152)
            let rowH = max(rest - stripH - gap, 140)

            let startupW = min(max(size.width * 0.36, 340), 540)
            let deviceW = min(max(size.width * 0.32, 320), 500)

            VStack(spacing: gap) {
                HStack(spacing: gap) {
                    cpuHero
                    tempHero
                    memHero
                    diskHero
                }
                .frame(height: heroH)

                HStack(spacing: gap) {
                    topProcessPanel
                    startupPanel
                        .frame(width: startupW)
                }
                .frame(height: rowH)

                HStack(spacing: gap) {
                    AlertStrip(alerts: model.alerts)
                    DevicePanel(
                        meta: model.meta,
                        uptime: model.uptimeText,
                        updatedAt: model.lastUpdate
                    )
                    .frame(width: deviceW)
                }
                .frame(height: stripH)
            }
        }
    }

    // MARK: - Hero

    private var cpuHero: some View {
        let cpu = model.snapshot.cpu
        return HeroMetric(
            label: L.t("处理器"),
            value: String(format: "%.1f", cpu.total),
            color: Theme.blue,
            caption: String(format: L.t("用户 %.1f%% · 系统 %.1f%%"), cpu.user, cpu.system),
            tag: "P\(cpu.perfCores)/E\(cpu.effCores)",
            progress: cpu.total,
            history: model.cpuHistory
        )
    }

    private var tempHero: some View {
        let temp = model.snapshot.temp
        let value = temp.primaryC
        // 折线用自适应量程，圆环仍用 0–110 的绝对刻度（环是仪表、折线是趋势）
        let scale = TempScale.range(for: model.tempHistory, current: value)
        let color: Color = {
            guard let value else { return Theme.dim }
            if value >= 90 { return Theme.red }
            if value >= 75 { return Theme.yellow }
            return Theme.teal
        }()
        return HeroMetric(
            label: L.t("温度"),
            value: value.map { String(format: "%.1f", $0) } ?? "—",
            unit: value == nil ? "" : "°C",
            color: color,
            caption: L.f("SoC %@ · 电池 %@", Fmt.temp(temp.socC), Fmt.temp(temp.batteryC)),
            tag: temp.sensorCount > 0 ? L.f("%@ 路", temp.sensorCount) : nil,
            progress: nil,
            history: model.tempHistory,
            maxHistory: scale.upper,
            historyMin: scale.lower,
            ring: value.map { min(max($0 / 110 * 100, 0), 100) }
        )
    }

    private var memHero: some View {
        let mem = model.snapshot.mem
        return HeroMetric(
            label: L.t("内存"),
            value: String(format: "%.1f", Double(mem.usedBytes) / 1_073_741_824),
            unit: "GB",
            color: Theme.purple,
            caption: L.f(
                "共 %@ · 缓存 %@ · 压力 %@",
                String(format: "%.0f GB", Double(mem.totalBytes) / 1_073_741_824),
                Fmt.bytes(mem.cachedBytes),
                mem.pressure.label
            ),
            progress: mem.usedPercent,
            history: model.memHistory
        )
    }

    private var diskHero: some View {
        let disk = model.snapshot.disk
        return HeroMetric(
            label: L.t("磁盘"),
            value: String(format: "%.1f", disk.usedPercent),
            color: Theme.peach,
            caption: "\(Fmt.bytes(disk.usedBytes)) / \(Fmt.bytes(disk.totalBytes))",
            progress: disk.usedPercent,
            history: model.diskHistory
        )
    }

    // MARK: - Top 进程

    private var topProcessPanel: some View {
        Card(title: L.t("Top 进程"), subtitle: L.t("按 CPU 排序"), accent: Theme.orange) {
            VStack(spacing: 0) {
                ProcessTableHeader(compact: true)
                ForEach(model.topProcesses) { row in
                    ProcessLine(row: row, compact: true, allowKill: false) {}
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - 启动项

    private var startupPanel: some View {
        let startup = model.startup

        return Card(
            title: L.t("启动项"),
            subtitle: L.f("%@ 项 · 风险 %@", startup.items.count, startup.riskyCount),
            accent: Theme.yellow
        ) {
            VStack(alignment: .leading, spacing: 0) {
                if startup.items.isEmpty {
                    Text(L.t("正在扫描…"))
                        .font(.system(size: TS.caption))
                        .foregroundStyle(Theme.dim)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView(.vertical) {
                        LazyVStack(spacing: 0) {
                            ForEach(startup.items) { item in
                                startupRow(item)
                            }
                        }
                    }
                    .scrollIndicators(.never)
                }

                Divider()
                    .overlay(Theme.line.opacity(0.6))
                    .padding(.top, 6)

                HStack(spacing: 14) {
                    CountChip(
                        label: L.t("用户级"),
                        value: startup.items.filter { $0.kind == .userAgent }.count,
                        color: Theme.blue
                    )
                    CountChip(
                        label: L.t("系统级"),
                        value: startup.privilegedCount,
                        color: Theme.peach
                    )
                    CountChip(
                        label: L.t("登录窗"),
                        value: startup.items.filter(\.runsAtLoginWindow).count,
                        color: Theme.yellow
                    )
                    Spacer(minLength: 0)
                }
                .padding(.top, 7)
            }
        }
    }

    private func startupRow(_ item: StartupItem) -> some View {
        HStack(spacing: 8) {
            RiskBadge(risk: item.risk, compact: true)
                // 24pt 只够中文单字（中/低/高），英文 Medium 会被截成 "Medi…"
                .frame(width: 46, alignment: .leading)

            Text(item.label)
                .font(.system(size: TS.caption))
                .foregroundStyle(item.risk.level >= .medium ? Theme.text : Theme.muted)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            if item.runsAtLoginWindow {
                TagChip(text: L.t("登录窗"), color: Theme.yellow)
            } else if item.keepAlive {
                TagChip(text: L.t("保活"), color: Theme.purple)
            } else if item.runAtLoad {
                TagChip(text: L.t("开机"), color: Theme.blue)
            }
            if item.kind.isPrivileged {
                TagChip(text: "root", color: Theme.peach)
            }
        }
        .padding(.vertical, 5)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.line.opacity(0.35)).frame(height: 0.5)
        }
    }
}

struct CountChip: View {
    var label: String
    var value: Int
    var color: Color

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: TS.micro))
                .foregroundStyle(Theme.dim)
            Text("\(value)")
                .font(.system(size: TS.caption, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
        }
    }
}
