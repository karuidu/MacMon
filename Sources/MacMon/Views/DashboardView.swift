import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var nav: NavigationModel
    @EnvironmentObject private var language: LanguageStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Rectangle()
                .fill(Theme.line.opacity(0.7))
                .frame(height: 1)
            PagePager()
            pageIndicator
        }
        .background(Theme.pageBackground)
        .preferredColorScheme(.dark)
        // 语言一变就换 id，让整棵子树重建。
        //
        // `L.t()` 是普通函数调用，不会给子视图建立对语言状态的依赖，
        // 所以光靠 `@EnvironmentObject` 只会重建 DashboardView 自己，
        // 里面那些 `Text(L.t(...))` 不会重新求值——必须换 id。
        //
        // 注意：这个 `.id` 只能放在**视图内部**。放在 `Window` scene 的根上
        // 会让整个窗口都不再出现（实测：进程活着，一条 CGWindow 都查不到）。
        .id(language.language)
        .onAppear {
            // 红叉关窗后 NSWindow 会被销毁，菜单栏面板只能靠 openWindow(id:) 重建；
            // 而 openWindow 只有带 Environment 的视图拿得到，这里先登记一份。
            DashboardWindow.openAction = { openWindow(id: WindowID.dashboard) }
            NotificationRouter.navigation = nav
            model.start()
        }
    }

    // MARK: - 顶栏

    private var topBar: some View {
        HStack(spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.blue)
                Text("MacMon")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.text)
            }
            // hiddenTitleBar 下要让开左上角红绿灯
            .padding(.leading, 78)

            tabs

            Spacer(minLength: 10)

            HStack(spacing: 16) {
                HeaderStat(label: L.t("主机"), value: model.meta.hostname)
                HeaderStat(label: L.t("已运行"), value: model.uptimeText)
                HeaderStat(
                    label: L.t("更新"),
                    value: model.lastUpdate.formatted(date: .omitted, time: .standard)
                )
            }

            LanguageSwitch()

            HStack(spacing: 6) {
                StatusDot(color: model.isWarming ? Theme.yellow : Theme.green)
                Text(model.isWarming ? L.t("预热中") : L.t("实时"))
                    .font(.system(size: TS.micro, weight: .medium))
                    .foregroundStyle(model.isWarming ? Theme.yellow : Theme.green)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                Capsule().fill((model.isWarming ? Theme.yellow : Theme.green).opacity(0.12))
            )
        }
        .padding(.trailing, 20)
        .frame(height: 54)
    }

    private var tabs: some View {
        HStack(spacing: 2) {
            ForEach(DashboardPage.allCases) { page in
                let active = nav.page == page
                Button {
                    withAnimation(.easeInOut(duration: 0.22)) { nav.go(page) }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: page.icon)
                            .font(.system(size: 10, weight: .medium))
                        Text(page.localizedTitle)
                            .font(.system(size: 11.5, weight: active ? .semibold : .regular))
                    }
                    .foregroundStyle(active ? Theme.text : Theme.dim)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 5)
                    .background(
                        Capsule().fill(active ? page.accent.opacity(0.18) : Color.clear)
                    )
                    .overlay(
                        Capsule().strokeBorder(
                            active ? page.accent.opacity(0.45) : Color.clear,
                            lineWidth: 1
                        )
                    )
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(Theme.surface.opacity(0.75)))
        .overlay(Capsule().strokeBorder(Theme.line, lineWidth: 1))
    }

    // MARK: - 页码指示

    private var pageIndicator: some View {
        HStack(spacing: 6) {
            ForEach(DashboardPage.allCases) { page in
                let active = nav.page == page
                Capsule()
                    .fill(active ? page.accent : Theme.line)
                    .frame(width: active ? 18 : 5, height: 5)
                    .contentShape(Rectangle())
                    .onTapGesture { nav.go(page) }
            }
            Text("\(nav.page.rawValue + 1) / \(DashboardPage.allCases.count)")
                .font(.system(size: TS.micro, design: .monospaced))
                .foregroundStyle(Theme.dim.opacity(0.8))
                .padding(.leading, 6)
        }
        .frame(height: 26)
        .frame(maxWidth: .infinity)
        .padding(.bottom, 2)
        .animation(.easeInOut(duration: 0.22), value: nav.page)
    }
}

private struct HeaderStat: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .font(.system(size: 8.5))
                .foregroundStyle(Theme.dim)
            Text(value)
                .font(.system(size: TS.caption, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
        }
    }
}
