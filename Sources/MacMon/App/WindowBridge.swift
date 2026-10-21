import AppKit
import Combine
import SwiftUI

/// 主窗口的唯一标识。`Window(_:id:)` 是单例 scene，
/// 与「常驻菜单栏 + 唯一主窗口」的语义一致。
enum WindowID {
    static let dashboard = "dashboard"
}

/// 主窗口的显示 / 隐藏。
///
/// 不用 `NSApp.hide(nil)`：它会把**正在被点击的菜单栏面板**一起藏掉，
/// 表现为「点一下就整块消失」，非常突兀。`orderOut` 只收主窗口。
@MainActor
enum DashboardWindow {

    /// 由 `DashboardView.onAppear` 注册。
    ///
    /// 红叉关窗后 `NSWindow` 会被销毁，此时只能靠 `openWindow(id:)` 重建；
    /// 而 `openWindow` 只能在有 `Environment` 的视图里拿到，所以提前存一份闭包。
    /// 环境动作本身是稳定的，窗口销毁不会让它失效。
    static var openAction: (() -> Void)?

    static func matches(_ window: NSWindow) -> Bool {
        // 只用「有标题栏 + 不是 NSPanel」两个条件。
        //
        // **不能加 `canBecomeMain`**：`orderOut` 之后窗口对象还在 `NSApp.windows` 里，
        // 但 `canBecomeMain` 会翻成 false（自检实测）。原来的「打开大屏」正是靠
        // `where window.canBecomeMain` 找窗口，窗口一被隐藏或红叉关掉就再也找不回来，
        // 循环体空转 —— 这就是「点了没反应」的根因。
        //
        // MenuBarExtra 的面板是 NSPanel、系统状态栏窗口没有 .titled，两个条件足够把它们排除。
        window.styleMask.contains(.titled) && !(window is NSPanel)
    }

    static func find() -> NSWindow? {
        NSApp.windows.first(where: matches)
    }

    static func show() {
        NSApp.activate(ignoringOtherApps: true)

        if let window = find() {
            window.deminiaturize(nil)        // 最小化时 isVisible 仍为 true，必须先还原
            window.makeKeyAndOrderFront(nil)
            return
        }

        // 窗口真被红叉关掉了，重建。新建的 NSWindow 要过一两个 runloop 才进 NSApp.windows，
        // 所以这里轮询几次而不是只等一拍。
        openAction?()
        reveal(retries: 5)
    }

    private static func reveal(retries: Int) {
        guard retries > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            if let window = find() {
                window.deminiaturize(nil)
                window.makeKeyAndOrderFront(nil)
            } else {
                reveal(retries: retries - 1)
            }
        }
    }

    static func hide() {
        find()?.orderOut(nil)
    }
}

/// 主窗口可见性的响应式包装。
///
/// 不做状态机、不自己维护布尔值：每次收到通知就**重新计算一遍**
/// `NSApp.windows` 的真实状态。窗口被销毁重建后 observer 依然有效（`object: nil`）。
@MainActor
final class DashboardWindowState: ObservableObject {

    @Published private(set) var isVisible = false

    private var observers: [NSObjectProtocol] = []

    /// 注意：AppKit **没有** `didOrderOnScreen` / `didOrderOffScreen` 这两个通知
    /// （SDK 头文件里查不到），所以「窗口被 orderOut」只能通过
    /// 「失去 key」+「遮挡状态变化」这两条侧面感知，
    /// 外加按钮自身在动作后主动 `refresh()` 兜底。
    private static let events: [Notification.Name] = [
        NSWindow.didBecomeKeyNotification,
        NSWindow.didResignKeyNotification,
        NSWindow.didBecomeMainNotification,
        NSWindow.didResignMainNotification,
        NSWindow.didMiniaturizeNotification,
        NSWindow.didDeminiaturizeNotification,
        NSWindow.didChangeOcclusionStateNotification,
        NSWindow.willCloseNotification,
        NSApplication.didHideNotification,
        NSApplication.didUnhideNotification
    ]

    init() {
        let center = NotificationCenter.default
        for name in Self.events {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
            observers.append(token)
        }
        refresh()
    }

    func refresh() {
        let visible = NSApp.windows.contains {
            // 最小化时 isVisible 仍为 true，必须叠加 !isMiniaturized，
            // 否则按钮会显示成「隐藏大屏」，点下去什么也不会发生
            DashboardWindow.matches($0) && $0.isVisible && !$0.isMiniaturized
        }
        if visible != isVisible {
            isVisible = visible
        }
    }
}

/// 系统通知点击后的跳转。
///
/// 通知回调在后台队列，且 `AppDelegate` 拿不到 SwiftUI 的 `EnvironmentObject`，
/// 所以由视图在 `onAppear` 时把 `NavigationModel` 注册进来。
@MainActor
enum NotificationRouter {
    static weak var navigation: NavigationModel?

    static func openSecurityPage() {
        DashboardWindow.show()
        navigation?.go(.security)
    }
}
