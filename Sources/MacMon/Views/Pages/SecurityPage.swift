import SwiftUI

/// 安全：开机启动项全量列表 + 预警 + 高风险进程
struct SecurityPage: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var notifier = StartupNotifier.shared

    private var items: [StartupItem] {
        model.startup.items.sorted {
            $0.risk.score == $1.risk.score
                ? $0.label.localizedCompare($1.label) == .orderedAscending
                : $0.risk.score > $1.risk.score
        }
    }

    private var riskyProcesses: [ProcessRow] {
        model.allProcesses
            .filter { $0.risk.level >= .medium }
            .sorted { $0.risk.score > $1.risk.score }
    }

    var body: some View {
        PageScaffold(page: .security) {
            HStack(spacing: 18) {
                HeaderCount(label: L.t("启动项"), value: model.startup.items.count, color: Theme.yellow)
                HeaderCount(label: L.t("系统级"), value: model.startup.privilegedCount, color: Theme.peach)
                HeaderCount(label: L.t("中高风险"), value: model.startup.riskyCount, color: Theme.red)
                HeaderCount(label: L.t("近期变更"), value: model.startupChanges.count, color: Theme.sapphire)
                HeaderCount(label: L.t("高风险进程"), value: riskyProcesses.count, color: Theme.purple)
            }
        } content: { size in
            let gap: CGFloat = 14
            let availH = max(size.height - 46 - gap, 320)
            let leftW = min(max(size.width * 0.6, 460), 940)
            // 构成卡内容固定 7 行，给它定高；高风险进程按条数伸缩，
            // 否则「未发现可疑进程」会撑成一大片空白。
            let statsH: CGFloat = 208
            let riskyH = riskyProcesses.isEmpty
                ? 108
                : min(max(CGFloat(riskyProcesses.count) * 40 + 58, 140), 260)

            HStack(spacing: gap) {
                startupCard
                    .frame(width: leftW)

                VStack(spacing: gap) {
                    AlertPanel(alerts: model.alerts, limit: 6)
                        .frame(maxHeight: .infinity)
                    StartupStatsCard(snapshot: model.startup)
                        .frame(height: statsH)
                    riskyProcessCard
                        .frame(height: riskyH)
                }
            }
            .frame(height: availH)
        }
    }

    // MARK: - 启动项

    private var startupCard: some View {
        Card(
            title: L.t("开机启动项"),
            subtitle: L.t("LaunchAgents / LaunchDaemons · 按风险排序"),
            accent: Theme.yellow
        ) {
            VStack(spacing: 0) {
                changeStrip

                if items.isEmpty {
                    Text(L.t("正在扫描…"))
                        .font(.system(size: TS.body))
                        .foregroundStyle(Theme.dim)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView(.vertical) {
                        LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                            Section {
                                ForEach(items) { item in
                                    StartupLine(item: item)
                                }
                            } header: {
                                startupHeader
                            }
                        }
                    }
                    .scrollIndicators(.automatic)
                }
            }
        }
    }

    // MARK: - 变更监控条

    private var changeStrip: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(L.t("最近变更"))
                    .font(.system(size: TS.caption, weight: .medium))
                    .foregroundStyle(Theme.text)
                if !model.startupChanges.isEmpty {
                    Text(L.f("%@ 条", model.startupChanges.count))
                        .font(.system(size: TS.micro, design: .monospaced))
                        .foregroundStyle(Theme.dim)
                }
                Spacer(minLength: 8)
                notifyToggle
            }
            .padding(.bottom, 7)

            if model.startupChanges.isEmpty {
                Text(L.t("监听中。新增、修改或删除 plist 会在这里实时出现。"))
                    .font(.system(size: TS.micro))
                    .foregroundStyle(Theme.dim)
                    .padding(.bottom, 2)
            } else {
                ForEach(model.startupChanges.prefix(3)) { change in
                    changeRow(change)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(Theme.surface2.opacity(0.35))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.line).frame(height: 1)
        }
    }

    private func changeRow(_ change: StartupChange) -> some View {
        HStack(spacing: 8) {
            Text(change.kind.label)
                .font(.system(size: TS.micro, weight: .medium))
                .foregroundStyle(kindColor(change.kind))
                .frame(width: 46, alignment: .leading)

            Text(change.label)
                .font(.system(size: TS.caption))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 6)

            // 新增 / 移除没有字段差异，这里就留空——
            // 填个「用户 LaunchAgent」只是把左边已说过的信息再念一遍
            Text(change.fields.first?.text ?? "")
                .font(.system(size: TS.micro))
                .foregroundStyle(Theme.dim)
                .lineLimit(1)

            Text(relativeTime(change.detectedAt))
                .font(.system(size: TS.micro, design: .monospaced))
                .foregroundStyle(Theme.dim.opacity(0.85))
                .frame(width: 54, alignment: .trailing)
        }
        .padding(.vertical, 2)
        .help("\(change.title)\n\(change.plistPath)")
    }

    private func kindColor(_ kind: StartupChangeKind) -> Color {
        switch kind {
        case .added:    return Theme.yellow
        case .removed:  return Theme.dim
        case .modified: return Theme.blue
        }
    }

    private func relativeTime(_ date: Date) -> String {
        let seconds = Date().timeIntervalSince(date)
        if seconds < 60 { return L.t("刚刚") }
        if seconds < 3600 { return L.f("%@ 分钟前", Int(seconds / 60)) }
        if seconds < 86_400 { return L.f("%@ 小时前", Int(seconds / 3600)) }
        return L.f("%@ 天前", Int(seconds / 86_400))
    }

    private var notifyToggle: some View {
        HStack(spacing: 5) {
            Text(notifyLabel)
                .font(.system(size: TS.micro))
                .foregroundStyle(notifier.status == .denied ? Theme.orange : Theme.dim)

            Toggle("", isOn: Binding(
                get: { notifier.isEnabled },
                set: { on in Task { await notifier.setEnabled(on) } }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
            .help(notifier.status == .denied
                  ? L.t("系统设置里已关闭本 App 的通知，点开关会跳到系统设置")
                  : L.t("启动项发生变化时弹系统通知（应用内告警始终开启）"))
        }
    }

    private var notifyLabel: String {
        switch notifier.status {
        case .unsupported:   return L.t("系统通知（需 .app 运行）")
        case .denied:        return L.t("系统通知·系统已关闭")
        case .notDetermined: return L.t("系统通知")
        case .granted:       return L.t("系统通知")
        }
    }

    private var startupHeader: some View {
        HStack(spacing: 10) {
            Text(L.t("风险")).frame(width: 30, alignment: .leading)
            Text(L.t("名称 / 类型")).frame(maxWidth: .infinity, alignment: .leading)
            Text(L.t("判定依据")).frame(width: 190, alignment: .trailing)
            Text(L.t("可执行文件")).frame(width: 150, alignment: .trailing)
        }
        .font(.system(size: TS.caption, weight: .medium))
        .foregroundStyle(Theme.dim)
        .padding(.vertical, 7)
        .padding(.horizontal, 8)
        .background(Theme.surface)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.line).frame(height: 1)
        }
    }

    // MARK: - 高风险进程

    private var riskyProcessCard: some View {
        Card(
            title: L.t("高风险进程"),
            subtitle: riskyProcesses.isEmpty ? L.t("无") : L.f("%@ 个", riskyProcesses.count),
            accent: Theme.purple
        ) {
            if riskyProcesses.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.green.opacity(0.75))
                    Text(L.t("未发现可疑进程"))
                        .font(.system(size: TS.caption))
                        .foregroundStyle(Theme.muted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        ForEach(riskyProcesses) { row in
                            HStack(spacing: 9) {
                                RiskBadge(risk: row.risk, compact: false)
                                    .frame(width: 66, alignment: .leading)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(row.name)
                                        .font(.system(size: TS.caption, weight: .medium))
                                        .foregroundStyle(Theme.text)
                                        .lineLimit(1)
                                    Text(row.risk.reasons.map(\.text).joined(separator: " · "))
                                        .font(.system(size: TS.micro))
                                        .foregroundStyle(Theme.dim)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 4)
                            .overlay(alignment: .bottom) {
                                Rectangle().fill(Theme.line.opacity(0.4)).frame(height: 0.5)
                            }
                        }
                    }
                }
                .scrollIndicators(.automatic)
            }
        }
    }
}

struct HeaderCount: View {
    var label: String
    var value: Int
    var color: Color

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(label)
                .font(.system(size: TS.micro))
                .foregroundStyle(Theme.dim)
            Text("\(value)")
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
        }
    }
}

/// 启动项构成：把 24 项按类型与行为拆开，比单纯的总数有用
struct StartupStatsCard: View {
    var snapshot: StartupSnapshot

    private var data: [(String, Int, Color)] {
        let items = snapshot.items
        return [
            (L.t("用户 Agent"), items.filter { $0.kind == .userAgent }.count, Theme.blue),
            (L.t("全局 Agent"), items.filter { $0.kind == .globalAgent }.count, Theme.sapphire),
            (L.t("系统 Daemon"), items.filter { $0.kind == .globalDaemon }.count, Theme.peach),
            (L.t("开机自启"), items.filter(\.runAtLoad).count, Theme.green),
            (L.t("保活重启"), items.filter(\.keepAlive).count, Theme.purple),
            (L.t("登录前加载"), items.filter(\.runsAtLoginWindow).count, Theme.yellow),
            (L.t("文件缺失"), items.filter { !$0.programExists }.count, Theme.red)
        ]
    }

    var body: some View {
        let rows = data
        let peak = max(rows.map { $0.1 }.max() ?? 1, 1)

        Card(
            title: L.t("构成"),
            subtitle: L.f("共 %@ 项", snapshot.items.count),
            accent: Theme.sapphire
        ) {
            VStack(spacing: 8) {
                ForEach(rows.indices, id: \.self) { index in
                    let row = rows[index]
                    HStack(spacing: 8) {
                        Text(row.0)
                            .font(.system(size: TS.micro))
                            .foregroundStyle(Theme.dim)
                            .lineLimit(1)
                            .frame(width: 96, alignment: .leading)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Theme.surface2)
                                Capsule()
                                    .fill(row.2.opacity(0.8))
                                    .frame(
                                        width: max(
                                            3,
                                            geo.size.width * CGFloat(row.1) / CGFloat(peak)
                                        )
                                    )
                            }
                        }
                        .frame(height: 5)
                        Text("\(row.1)")
                            .font(.system(size: TS.micro, weight: .medium, design: .monospaced))
                            .foregroundStyle(row.1 == 0 ? Theme.dim : row.2)
                            .frame(width: 22, alignment: .trailing)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}
