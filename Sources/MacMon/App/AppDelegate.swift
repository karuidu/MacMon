import AppKit
import UserNotifications

/// 只做三件事：接通知代理、前台也显示横幅、点通知跳转。
///
/// 用 `@NSApplicationDelegateAdaptor` 挂载，不改成手写 `main.swift`——
/// SwiftUI 的 `Window` / `MenuBarExtra` 场景生命周期仍由系统托管。
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 裸二进制（`MacMon --diagnose`、`swift run`）没有 bundle，
        // 访问 UNUserNotificationCenter.current() 会直接抛
        // `bundleProxyForCurrentProcess is nil` 并崩溃
        if Bundle.main.bundleIdentifier != nil {
            UNUserNotificationCenter.current().delegate = self
        }

        // 菜单裁一遍：去掉「服务」、空壳菜单和 AppKit 注入的输入辅助项（见 MenuLayout）
        MenuLayout.schedulePrune()

        if CommandLine.arguments.contains("--window-selftest") {
            Task { @MainActor in self.runWindowSelfTest() }
        }

        if CommandLine.arguments.contains("--menus") {
            Task { @MainActor in self.dumpMainMenu() }
        }
    }

    /// 打印完整菜单结构后退出（`--menus`）。
    ///
    /// 菜单没法用脚本「点开」看，但可以读 `NSApp.mainMenu`。这样「服务子菜单是不是
    /// 真的没了」「编辑菜单还剩几项」这类验收就能自动化，不用每次靠肉眼截图。
    @MainActor
    private func dumpMainMenu() {
        // 菜单要等 SwiftUI 把场景装配完才建好，而且 MenuLayout 在这之后还会再裁一遍，
        // 所以这里比首次裁剪的 1.2s 再晚一点读。
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            func walk(_ menu: NSMenu, depth: Int) {
                let pad = String(repeating: "  ", count: depth)
                for item in menu.items {
                    if item.isSeparatorItem {
                        print("\(pad)---")
                        continue
                    }
                    var note = item.isHidden ? "  [hidden]" : ""
                    if !item.keyEquivalent.isEmpty {
                        var mods = ""
                        let mask = item.keyEquivalentModifierMask
                        if mask.contains(.control) { mods += "^" }
                        if mask.contains(.option) { mods += "~" }
                        if mask.contains(.shift) { mods += "⇧" }
                        if mask.contains(.command) { mods += "⌘" }
                        note += "  \(mods)\(item.keyEquivalent)"
                    }
                    if item.submenu != nil {
                        print("\(pad)\(item.title) ▸\(note)")
                        walk(item.submenu!, depth: depth + 1)
                    } else {
                        print("\(pad)\(item.title)\(note)")
                    }
                }
            }

            guard let main = NSApp.mainMenu else {
                print("MENU 没有 mainMenu")
                exit(0)
            }
            for top in main.items {
                print("")
                print("=== \(top.title) ===")
                if let sub = top.submenu { walk(sub, depth: 1) }
            }
            print("")
            print("MENU done")
            exit(0)
        }
    }

    /// 窗口显示 / 隐藏 / 重建的脚本化验收（`--window-selftest`）。
    ///
    /// 没有辅助功能授权就没法真的去点菜单栏，只能把点击所触发的调用链
    /// 按同样的顺序跑一遍，把每一步的窗口状态打出来。
    @MainActor
    private func runWindowSelfTest() {
        func report(_ tag: String) {
            let windows = NSApp.windows.filter(DashboardWindow.matches)
            let detail = windows.map { window in
                "visible=\(window.isVisible) mini=\(window.isMiniaturized) "
                + "key=\(window.isKeyWindow) "
                + "frame=(\(Int(window.frame.origin.x)),\(Int(window.frame.origin.y))) "
                + "\(Int(window.frame.width))x\(Int(window.frame.height))"
            }
            print("WIN [\(tag)] 主窗口数=\(windows.count) \(detail.joined(separator: " || "))")
            let all = NSApp.windows.map { "\(type(of: $0))|vis=\($0.isVisible)|main=\($0.canBecomeMain)|panel=\($0 is NSPanel)|titled=\($0.styleMask.contains(.titled))" }
            print("WIN  全部窗口(\(all.count)): \(all.joined(separator: " ; "))")
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { report("启动后") }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            DashboardWindow.hide()
            report("hide 之后")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
            DashboardWindow.show()
            report("show 之后（立即）")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { report("show 之后（稳定）") }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.6) {
            DashboardWindow.find()?.close()
            report("模拟红叉关窗之后")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.4) { DashboardWindow.show() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.6) { report("重建后") }
        DispatchQueue.main.asyncAfter(deadline: .now() + 6.4) {
            print("WIN done")
            exit(0)
        }
    }

    /// 点 Dock 图标（`open -a MacMon`）时把大屏带出来，而不是什么都不发生
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            Task { @MainActor in DashboardWindow.show() }
        }
        return true
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// **不实现这个方法，App 在前台时收不到横幅**：
    /// 系统默认认为「用户已经在用这个 App 了」，静默塞进通知中心。
    /// 验收时最容易被误判成「通知功能没生效」。
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let target = response.notification.request.content.userInfo["target"] as? String
        if target == "security" {
            Task { @MainActor in NotificationRouter.openSecurityPage() }
        }
        completionHandler()
    }
}
