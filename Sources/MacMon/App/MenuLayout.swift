import AppKit

/// 菜单精简：把 SwiftUI 默认给的菜单裁到只剩这个 App 真有的功能。
///
/// 为什么 `.commands` 里清不干净，非要在构建完再裁一遍：
///
/// - `CommandGroup(replacing:)` 只能清空**组内条目**。组所在的顶层菜单会留下一个
///   空壳——实测会剩下空白的「格式」「显示」「帮助」菜单。
/// - macOS 还会绕过 SwiftUI 的构建器，往「编辑」里塞「自动填充」「开始听写…」
///   「表情与符号」，往「窗口」里塞窗口列表。这些只能用 AppKit 侧的接口删。
///
/// 结果可以跑 `--menus` 直接看到，不用靠肉眼截图菜单。
@MainActor
enum MenuLayout {

    /// 整块删掉的顶层菜单。逻辑上都对应这个单窗口工具 App 不存在的能力：
    /// 「格式」没有任何富文本，「窗口」的整理/平铺对一个大屏没意义，
    /// 「帮助」没有帮助手册。
    private static let dropTitles: Set<String> = [
        "格式", "Format",
        "窗口", "Window",
        "帮助", "Help",
    ]

    /// AppKit 注入到「编辑」菜单里的系统输入辅助项。
    /// 整个 App 只有一个搜索框，这些只会在菜单里刷存在感。
    private static let injected: [String] = [
        "自动填充", "AutoFill",
        "开始听写", "Dictation",
        "表情与符号", "Emoji",
    ]

    /// 按 action 定位并改名的菜单项。
    ///
    /// 系统菜单（关于/隐藏/退出/剪切…）的标题由**系统语言**决定，App 内切到英文时
    /// 它们仍是中文。这里统一改成 `L.t` 的结果，让整条菜单栏跟界面语言一致。
    /// 键用 selector 而不是标题——selector 不随语言变，按标题匹配换个系统语言就失效。
    private static let localizedTitles: [String: String] = [
        "orderFrontStandardAboutPanel:": "关于 MacMon",
        "hide:": "隐藏 MacMon",
        "hideOtherApplications:": "隐藏其他",
        "unhideAllApplications:": "全部显示",
        "terminate:": "退出 MacMon",
        "cut:": "剪切",
        "copy:": "拷贝",
        "paste:": "粘贴",
        "delete:": "删除",
        "selectAll:": "全选",
    ]

    /// 启动后连做几次：SwiftUI 装配菜单的时机不完全确定，
    /// 单次裁剪可能赶在它之前，也可能被后续重建覆盖。
    static func schedulePrune() {
        for delay in [0.5, 1.2, 2.6] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { prune() }
        }
    }

    static func prune() {
        guard let main = NSApp.mainMenu else { return }

        // ① 删掉整块顶层菜单
        for item in main.items where dropTitles.contains(item.title) {
            main.removeItem(item)
        }
        // 指针跟着置空，免得 AppKit 后续往已摘掉的菜单里塞窗口列表
        NSApp.windowsMenu = nil
        NSApp.helpMenu = nil

        // ② 「编辑」：删掉注入的系统输入项
        if let sub = menu(main, titledAnyOf: ["编辑", "Edit"])?.submenu {
            for item in sub.items where isInjected(item) {
                sub.removeItem(item)
            }
            collapse(sub)
        }

        // ③ 「显示」：只留全屏。`toolbar` / `sidebar` 两组清空后这里只剩分隔线，
        //    但全屏是这类大屏真会用到的，补一条回去。
        if let view = viewMenu(main) {
            let fullScreen = #selector(NSWindow.toggleFullScreen(_:))
            if let existing = view.submenu?.items.first(where: { $0.action == fullScreen }) {
                // 语言切换后刷新标题
                existing.title = L.t("进入全屏")
            } else if let sub = view.submenu, sub.items.allSatisfy({ $0.isSeparatorItem }) {
                let item = NSMenuItem(title: L.t("进入全屏"), action: fullScreen, keyEquivalent: "f")
                item.keyEquivalentModifierMask = [.control, .command]
                item.target = nil   // 走响应链，落到当前窗口
                sub.addItem(item)
            }
        }

        // ④ 标题全部跟随 App 内语言（系统菜单只跟系统语言，不跟这个）
        localize(main)

        // ⑤ 收尾：合并连续分隔线、去掉首尾分隔线
        for item in main.items {
            if let sub = item.submenu { collapse(sub) }
        }
    }

    // MARK: - 细节

    private static func viewMenu(_ main: NSMenu) -> NSMenuItem? {
        let fullScreen = #selector(NSWindow.toggleFullScreen(_:))
        if let byAction = main.items.first(where: { $0.submenu?.items.contains { $0.action == fullScreen } == true }) {
            return byAction
        }
        return menu(main, titledAnyOf: ["显示", "View"])
    }

    /// 把顶层菜单名和标准菜单项改成当前语言。
    ///
    /// 顶层菜单按**内容**识别（「编辑」有 cut:/copy:，「显示」有 toggleFullScreen:），
    /// 因为它们的标题本身就会随系统语言变；标准项按 selector 识别，理由同上。
    private static func localize(_ main: NSMenu) {
        for top in main.items {
            guard let sub = top.submenu else { continue }
            let actions = Set(sub.items.compactMap { $0.action.map(NSStringFromSelector) })
            if !actions.isDisjoint(with: ["cut:", "copy:", "paste:", "selectAll:"]) {
                top.title = L.t("编辑")
            } else if actions.contains("toggleFullScreen:") {
                top.title = L.t("显示")
            } else if ["页面", "Page", "Pages"].contains(top.title) {
                top.title = L.t("页面")
            }
        }

        for top in main.items {
            guard let sub = top.submenu else { continue }
            for item in sub.items {
                guard let action = item.action else { continue }
                let name = NSStringFromSelector(action)
                // 关于面板有两个 selector（带不带 options）
                if name.hasPrefix("orderFrontStandardAboutPanel"),
                   let zh = localizedTitles["orderFrontStandardAboutPanel:"] {
                    item.title = L.t(zh)
                } else if let zh = localizedTitles[name] {
                    item.title = L.t(zh)
                }
            }
        }
    }

    private static func menu(_ main: NSMenu, titledAnyOf titles: [String]) -> NSMenuItem? {
        main.items.first { titles.contains($0.title) }
    }

    private static func isInjected(_ item: NSMenuItem) -> Bool {
        guard !item.isSeparatorItem else { return false }
        return injected.contains { item.title.contains($0) }
    }

    /// 删掉连续与首尾的分隔线。`menu.items` 是快照数组，边遍历边删是安全的。
    private static func collapse(_ menu: NSMenu) {
        var previousWasSeparator = true     // 开头不留分隔线
        for item in menu.items {
            if item.isSeparatorItem {
                if previousWasSeparator { menu.removeItem(item) }
                previousWasSeparator = true
            } else {
                previousWasSeparator = false
            }
        }
        while let last = menu.items.last, last.isSeparatorItem {
            menu.removeItem(last)
        }
    }
}
