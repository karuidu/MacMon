import AppKit
import Foundation
import UserNotifications

/// 启动项变更的系统通知。
///
/// 三条硬约束：
/// 1. **首次授权必须由用户主动打开开关时触发**。`requestAuthorization` 每个 bundle id
///    只能弹一次，弹早了被用户顺手拒掉就永久废掉（系统不会再弹）。
/// 2. **必须以 `.app` 运行**。裸二进制没有 bundle，`UNUserNotificationCenter.current()`
///    直接抛 `bundleProxyForCurrentProcess is nil`，所以每一处访问前都要判 `Bundle.main.bundleIdentifier`。
/// 3. 前台也要能看见横幅 → 需要 `UNUserNotificationCenterDelegate.willPresent`
///    返回 `[.banner, .list, .sound]`（在 `AppDelegate` 里实现）。
@MainActor
final class StartupNotifier: ObservableObject {

    static let shared = StartupNotifier()

    enum Status: String {
        case unsupported      // 非 .app 运行
        case notDetermined
        case granted
        case denied
    }

    private let enabledKey = "macmon.startupNotifyEnabled"

    /// 用户是否打开了通知开关（App 内设置，与系统授权是两件事）
    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: enabledKey) }
    }

    @Published private(set) var status: Status = .unsupported

    private var center: UNUserNotificationCenter? {
        // 必须先判 bundle id，否则 current() 自己就崩了
        guard Bundle.main.bundleIdentifier != nil else { return nil }
        return UNUserNotificationCenter.current()
    }

    private init() {
        isEnabled = UserDefaults.standard.bool(forKey: enabledKey)
        refreshStatus()
    }

    // MARK: - 授权状态

    func refreshStatus() {
        guard let center else {
            status = .unsupported
            return
        }
        Task { [weak self] in
            let settings = await center.notificationSettings()
            self?.apply(settings)
        }
    }

    private func apply(_ settings: UNNotificationSettings) {
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: status = .granted
        case .denied:                               status = .denied
        case .notDetermined:                        status = .notDetermined
        @unknown default:                           status = .notDetermined
        }
        // 系统里被关掉时，App 内的开关也同步关掉，
        // 避免出现「开关是开的、却一条通知都没有」的悬空状态
        if status == .denied, isEnabled {
            isEnabled = false
        }
    }

    /// 打开通知开关。
    ///
    /// 只在 `notDetermined` 阶段真正弹授权框——`requestAuthorization` 每个 bundle id
    /// 只有一次机会，被用户顺手拒掉之后系统再也不会弹，
    /// 此时唯一出路是去系统设置里手动打开，所以直接把人送过去。
    func setEnabled(_ on: Bool) async {
        guard on else {
            isEnabled = false
            return
        }
        guard let center else {
            status = .unsupported
            isEnabled = false
            return
        }

        var settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            settings = await center.notificationSettings()
        }
        apply(settings)
        isEnabled = (status == .granted)
        if !isEnabled {
            openSystemSettings()
        }
    }

    func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - 投递

    /// 一批变更只发**一条**通知：一次 `cp` 拷进来 10 个 plist 就弹 10 个横幅是灾难。
    /// 返回 true 表示已投递（调用方据此把 `notified` 落盘，跨启动不重弹）。
    @discardableResult
    func post(_ changes: [StartupChange]) -> Bool {
        guard isEnabled, status == .granted, !changes.isEmpty, let center else { return false }

        let content = UNMutableNotificationContent()
        if changes.count == 1, let only = changes.first {
            content.title = only.title
            content.body = only.detail
        } else {
            content.title = L.f("发现 %@ 个启动项变更", changes.count)
            let names = changes.prefix(3).map(\.label).joined(separator: "、")
            content.body = changes.count > 3 ? L.f("%@ 等", names) : names
        }
        content.sound = .default
        // 点通知后跳「安全」页
        content.userInfo = ["target": "security"]

        let request = UNNotificationRequest(
            identifier: changes[0].id.uuidString,
            content: content,
            trigger: nil
        )
        center.add(request)
        return true
    }
}
