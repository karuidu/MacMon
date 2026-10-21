import SwiftUI

/// 尺寸只在进程内强制一次（见 `place()`）
nonisolated(unsafe) private var didForceWindowSize = false

@main
struct MacMonApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()
    @StateObject private var nav = NavigationModel()
    @StateObject private var language = LanguageStore()
    @StateObject private var windowState = DashboardWindowState()

    init() {
        // 诊断入口：`MacMon --diagnose` 打印各采集器实机输出后退出，
        // 用于在没有界面的环境下验证采集链路。
        if CommandLine.arguments.contains("--diagnose") {
            Diagnostics.run()
            exit(0)
        }
    }

    var body: some Scene {
        // 用 `Window` 而不是 `WindowGroup`：后者是「开一个新的同类窗口」的语义，
        // 菜单栏点十次就会多出十个大屏。`Window` 是单例 scene，配合
        // `openWindow(id:)` 只会在窗口被关掉后重建同一个。
        Window("MacMon", id: WindowID.dashboard) {
            DashboardView()
                .environmentObject(model)
                .environmentObject(nav)
                .environmentObject(language)
                .frame(minWidth: 1000, minHeight: 680)
                .onAppear { fitWindowToScreen() }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1480, height: 900)
        .commands {
            // 单窗口工具，没有「新建」语义
            CommandGroup(replacing: .newItem) {}

            // 「服务」整块去掉。这里显示的每一条都来自**别的** App：装了 Xcode 就会看到
            // Instruments 的四个模板（Activity Monitor / Allocations & Leaks /
            // File Activity / System Trace），它们由 macOS 的服务注册表全局注入，
            // 出现在每个 App 的菜单里。MacMon 自己的 Info.plist 没有 NSServices，
            // 一条服务都不注册，留着就是个通往别人 App 的入口。
            CommandGroup(replacing: .systemServices) {}

            // 没有帮助手册，默认那一项点开是空的
            CommandGroup(replacing: .help) {}

            // 没有工具栏、没有侧边栏，这两组都是空动作
            CommandGroup(replacing: .toolbar) {}
            CommandGroup(replacing: .sidebar) {}
        }
        // 拆成两块是必须的：`CommandsBuilder` 最多只接受 10 个子项，
        // 把下面这些和上面那些塞进同一个闭包会报 `extra argument in call`。
        .commands {
            // 编辑菜单只留剪贴板五项。默认还会塞「查找与替换」「拼写与语法」
            // 「听写」「表情与符号」——整个 App 只有一个搜索框，这些全是噪音。
            // 撤销/重做也去掉：可编辑文本只有那一个过滤框。
            CommandGroup(replacing: .textEditing) {}
            CommandGroup(replacing: .textFormatting) {}
            CommandGroup(replacing: .undoRedo) {}

            // 窗口菜单：单窗口应用不需要「移动/平铺窗口」和窗口列表
            CommandGroup(replacing: .windowArrangement) {}
            CommandGroup(replacing: .windowList) {}

            CommandMenu(L.t("页面")) {
                ForEach(DashboardPage.allCases) { page in
                    Button(page.localizedTitle) { nav.go(page) }
                        .keyboardShortcut(
                            KeyEquivalent(Character("\(page.rawValue + 1)")),
                            modifiers: .command
                        )
                }
                Divider()
                Button(L.t("下一页")) { nav.step(1) }
                    .keyboardShortcut("]", modifiers: .command)
                Button(L.t("上一页")) { nav.step(-1) }
                    .keyboardShortcut("[", modifiers: .command)
            }
        }

        MenuBarExtra {
            MenuBarPanel()
                .environmentObject(model)
                .environmentObject(language)
                .environmentObject(windowState)
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "waveform.path.ecg")
                Text(menuTitle)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
            }
        }
        .menuBarExtraStyle(.window)
    }

    /// 让窗口贴合当前屏幕的可用区域，避免小屏上超出边界被截断。
    /// `MACMON_WINDOW=940x680` 可强制指定尺寸（验收用）。
    ///
    /// 系统会按上次关闭时的位置做窗口恢复，换过显示器或拔掉外接屏之后，
    /// 恢复出来的原点可能在可见区域之外（实测出现过 y = −122，窗口只露出半截）。
    /// 这里在窗口落位后夹一次边界，并在 1 秒后再夹一次——恢复动作可能晚于首次布局。
    private func fitWindowToScreen() {
        place()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { self.place() }
    }

    private func place() {
        // 用 DashboardWindow.find() 而不是 `canBecomeMain`：窗口被隐藏时
        // canBecomeMain 会变 false，条件式会直接漏掉它
        guard let window = DashboardWindow.find(),
              let screen = window.screen ?? NSScreen.main else { return }

        // 尺寸只在进程内第一次落位时强制，之后只夹边界。
        // 否则红叉关窗再打开（窗口重建会重跑 onAppear）会把用户拖过的尺寸
        // 和位置一起重置回默认值。
        if didForceWindowSize {
            clamp(window, to: screen.visibleFrame)
            return
        }
        didForceWindowSize = true

        if let forced = ProcessInfo.processInfo.environment["MACMON_WINDOW"] {
            let parts = forced.split(separator: "x").compactMap { Double($0) }
            if parts.count == 2 {
                window.setContentSize(NSSize(width: parts[0], height: parts[1]))
                window.center()
                clamp(window, to: screen.visibleFrame)
                return
            }
        }

        let visible = screen.visibleFrame
        let width = min(1560, visible.width - 32)
        let height = min(940, visible.height - 32)
        window.setContentSize(NSSize(width: width, height: height))
        window.center()
        clamp(window, to: visible)
    }

    /// 把窗口整体推回可见区域
    private func clamp(_ window: NSWindow, to visible: NSRect) {
        var frame = window.frame
        frame.origin.x = min(max(frame.origin.x, visible.minX), max(visible.maxX - frame.width, visible.minX))
        frame.origin.y = min(max(frame.origin.y, visible.minY), max(visible.maxY - frame.height, visible.minY))
        if frame != window.frame {
            window.setFrame(frame, display: true)
        }
    }

    private var menuTitle: String {
        let cpu = model.snapshot.cpu.total
        if let temp = model.snapshot.temp.primaryC {
            return String(format: "%.0f%% %.0f°", cpu, temp)
        }
        return String(format: "%.0f%%", cpu)
    }
}
