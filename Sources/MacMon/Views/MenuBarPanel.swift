import SwiftUI

/// 菜单栏常驻面板：纯 SwiftUI 绘制，不经过任何 WebView。
struct MenuBarPanel: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var language: LanguageStore
    @EnvironmentObject private var windowState: DashboardWindowState

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(model.meta.hostname)
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                StatusDot(color: model.isWarming ? Theme.yellow : Theme.green, size: 5)
            }

            Divider().overlay(Theme.line)

            row("CPU", String(format: "%.1f%%", model.snapshot.cpu.total), Theme.blue)
            row(L.t("内存"), String(format: "%.1f / %.0f GB", Double(model.snapshot.mem.usedBytes) / 1_073_741_824, Double(model.snapshot.mem.totalBytes) / 1_073_741_824), Theme.purple)
            row(L.t("温度"), Fmt.temp(model.snapshot.temp.primaryC), Theme.teal)
            row(L.t("电池"), String(format: "%.0f%%", model.snapshot.battery.percent), Theme.green)
            row(L.t("进程"), L.f("%@ 个", model.processTotal), Theme.muted)

            if !model.alerts.isEmpty {
                Divider().overlay(Theme.line)
                ForEach(model.alerts.prefix(2)) { alert in
                    HStack(spacing: 5) {
                        StatusDot(color: alert.level.color, size: 4)
                        Text(alert.title)
                            .font(.system(size: 9.5))
                            .foregroundStyle(Theme.muted)
                    }
                }
            }

            Divider().overlay(Theme.line)

            HStack {
                Button(windowState.isVisible ? L.t("隐藏大屏") : L.t("打开大屏")) {
                    if windowState.isVisible {
                        DashboardWindow.hide()
                    } else {
                        DashboardWindow.show()
                    }
                    // 面板此刻已经被收起，状态改动要等下一拍再读才准
                    DispatchQueue.main.async { windowState.refresh() }
                }
                .buttonStyle(.link)
                .font(.system(size: 10))
                .help(windowState.isVisible ? L.t("隐藏主窗口，采集继续在后台跑") : L.t("把主窗口带到最前面"))

                Spacer()

                Button(L.t("退出")) {
                    NSApp.terminate(nil)
                }
                .buttonStyle(.link)
                .font(.system(size: 10))
            }
        }
        .padding(11)
        .frame(width: 252)
        // 同 DashboardView：`.id` 必须加在视图内部，加在 scene 根上会让面板/窗口不出现
        .id(language.language)
        .onAppear {
            // 面板每次展开都重算一次：窗口可能在面板收起期间被红叉关掉或最小化
            windowState.refresh()
        }
    }

    private func row(_ label: String, _ value: String, _ color: Color) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 9.5))
                .foregroundStyle(Theme.dim)
            Spacer()
            Text(value)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(color)
        }
    }
}
