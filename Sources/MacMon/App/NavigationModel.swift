import SwiftUI

/// 一屏一主题的五个页面。
///
/// 导航状态单独放在 `NavigationModel` 里，不挂在 `AppModel` 上：
/// `AppModel` 每秒都会发布采集结果，如果菜单命令闭包捕获它，
/// 菜单会每秒重建一次，快捷键偶发丢响应。
enum DashboardPage: Int, CaseIterable, Identifiable, Hashable {
    case overview
    case performance
    case processes
    case security
    case storage

    /// 让 `ForEach` 的 id 就是枚举自身，`scrollPosition(id:)` 才能直接用 `DashboardPage?` 绑定
    var id: DashboardPage { self }

    var title: String {
        switch self {
        case .overview:    return "概览"
        case .performance: return "性能"
        case .processes:   return "进程"
        case .security:    return "安全"
        case .storage:     return "存储网络"
        }
    }

    /// `title` 保留中文原文：命令行 `--page 概览` 要靠它匹配，而且它也是翻译表的键。
    /// 界面上一律用 `localizedTitle`。
    var localizedTitle: String { L.t(title) }

    /// 命令行/环境变量里用的英文标识
    var slug: String {
        switch self {
        case .overview:    return "overview"
        case .performance: return "performance"
        case .processes:   return "processes"
        case .security:    return "security"
        case .storage:     return "storage"
        }
    }

    var icon: String {
        switch self {
        case .overview:    return "square.grid.2x2"
        case .performance: return "gauge.with.dots.needle.67percent"
        case .processes:   return "list.bullet.rectangle"
        case .security:    return "lock.shield"
        case .storage:     return "internaldrive"
        }
    }
    var accent: Color {
        switch self {
        case .overview:    return Theme.blue
        case .performance: return Theme.mauve
        case .processes:   return Theme.orange
        case .security:    return Theme.yellow
        case .storage:     return Theme.green
        }
    }

    var subtitle: String {
        switch self {
        case .overview:    return L.t("所有关键指标一眼看完")
        case .performance: return L.t("处理器、温度与内存的实时细节")
        case .processes:   return L.t("全量进程，按占用排序，可结束")
        case .security:    return L.t("开机启动项与风险扫描")
        case .storage:     return L.t("网络吞吐、磁盘容量与电池健康")
        }
    }
}

@MainActor
final class NavigationModel: ObservableObject {
    @Published var page: DashboardPage

    init() {
        // 截图验收用：`MACMON_PAGE=process` 或 `--page process` 可直接启动到指定页
        let args = ProcessInfo.processInfo.arguments
        var raw = ProcessInfo.processInfo.environment["MACMON_PAGE"] ?? ""
        if let index = args.firstIndex(of: "--page"), index + 1 < args.count {
            raw = args[index + 1]
        } else if let inline = args.first(where: { $0.hasPrefix("--page=") }) {
            raw = String(inline.dropFirst("--page=".count))
        }
        let index = Int(raw) ?? Self.index(of: raw)
        page = DashboardPage(rawValue: index ?? 0) ?? .overview
    }

    private static func index(of name: String) -> Int? {
        DashboardPage.allCases.first {
            $0.title == name || $0.slug == name || "\($0)" == name
        }?.rawValue
    }

    func go(_ target: DashboardPage) {
        guard target != page else { return }
        page = target
    }

    func step(_ delta: Int) {
        let last = DashboardPage.allCases.count - 1
        let next = min(max(page.rawValue + delta, 0), last)
        page = DashboardPage(rawValue: next) ?? page
    }
}
