import Foundation
import SwiftUI

/// App 支持的界面语言。
enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case zh
    case en

    var id: String { rawValue }

    /// 切换器上显示的短标识
    var badge: String { self == .zh ? "中" : "EN" }

    var help: String { self == .zh ? "切换到中文" : "Switch to English" }
}

/// 语言状态：单独一个 ObservableObject，和 `NavigationModel` 一样不挂在
/// `AppModel` 上。`AppModel` 每秒发布一次采集结果，把语言挂在上面会让
/// 整个界面每秒重建一次。
@MainActor
final class LanguageStore: ObservableObject {
    static let shared = LanguageStore()

    private static let defaultsKey = "MacMon.language"

    /// 命令行强制指定语言时不落盘：截图脚本可以来回切，不会污染用户选择。
    private let isForced: Bool

    @Published var language: AppLanguage {
        didSet {
            guard oldValue != language else { return }
            L.current = language
            guard !isForced else { return }
            UserDefaults.standard.set(language.rawValue, forKey: Self.defaultsKey)
        }
    }

    init() {
        let forced = Self.forcedLanguage
        isForced = forced != nil
        let resolved = forced ?? Self.stored ?? Self.systemDefault
        language = resolved
        L.current = resolved
    }

    /// `--lang en` 或 `MACMON_LANG=en`，参数优先。
    private static var forcedLanguage: AppLanguage? {
        var raw = ProcessInfo.processInfo.environment["MACMON_LANG"]
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "--lang"), index + 1 < args.count {
            raw = args[index + 1]
        } else if let inline = args.first(where: { $0.hasPrefix("--lang=") }) {
            raw = String(inline.dropFirst("--lang=".count))
        }
        guard let value = raw?.lowercased(), !value.isEmpty else { return nil }
        return value.hasPrefix("zh") ? .zh : .en
    }

    private static var stored: AppLanguage? {
        UserDefaults.standard.string(forKey: Self.defaultsKey).flatMap(AppLanguage.init(rawValue:))
    }

    /// 首次启动跟随系统语言；之后只认用户的选择（包括手动选回中文）。
    private static var systemDefault: AppLanguage {
        let preferred = Locale.preferredLanguages.first ?? "en"
        return preferred.hasPrefix("zh") ? .zh : .en
    }
}

/// 文案查表。
///
/// 刻意不用 `.lproj` + `NSLocalizedString`：这是个 Swift Package，资源会被打进
/// `MacMon_MacMon.bundle`，而 SwiftUI 的 `Text("key")` 只查 `Bundle.main`，
/// 运行时切换语言拿不到正确的那张表。自己查表虽然土，但行为确定、切换即时。
///
/// 表以**中文原文**为键，找不到就原样返回中文——漏翻时界面退化成中文，
/// 而不是出现空白或 `key.not.found` 这种噪音。
enum L {
    /// 当前语言。采集线程也会读（风险原因、告警文案在后台生成），
    /// 所以不加 actor 隔离：枚举是字宽值，读写不会撕裂。
    static var current: AppLanguage = .zh

    /// 纯字符串查表。
    static func t(_ zh: String) -> String {
        guard current == .en else { return zh }
        return en[zh] ?? zh
    }

    /// 带插值的字符串。模板里用 `%@` 占位，参数按顺序替换。
    ///
    /// 用 `String(describing:)` 而不是 `String(format:)`：`%@` 传 `Int` 会崩，
    /// 而 `String(describing:)` 的语义和 Swift 字符串插值一致，
    /// 原来 `"共 \(count) 项"` 的输出一个字都不会变。
    static func f(_ zh: String, _ args: Any...) -> String {
        let template = current == .en ? (en[zh] ?? zh) : zh
        return fill(template, args)
    }

    private static func fill(_ template: String, _ args: [Any]) -> String {
        guard template.contains("%@") else { return template }
        var out = template
        for arg in args {
            guard let range = out.range(of: "%@") else { break }
            out.replaceSubrange(range, with: String(describing: arg))
        }
        return out
    }
}

/// 顶栏的语言切换器：中 / EN 两段胶囊。
struct LanguageSwitch: View {
    @EnvironmentObject private var store: LanguageStore

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppLanguage.allCases) { lang in
                let active = store.language == lang
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { store.language = lang }
                    // 切语言会让 SwiftUI 重建菜单，裁掉的空壳/注入项可能回来，再裁一次
                    MenuLayout.schedulePrune()
                } label: {
                    Text(lang.badge)
                        .font(.system(size: 10, weight: active ? .semibold : .regular))
                        .foregroundStyle(active ? Theme.text : Theme.dim)
                        .frame(width: 27, height: 17)
                        .background(
                            Capsule().fill(active ? Theme.blue.opacity(0.22) : Color.clear)
                        )
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(lang.help)
            }
        }
        .padding(2)
        .background(Capsule().fill(Theme.surface.opacity(0.75)))
        .overlay(Capsule().strokeBorder(Theme.line, lineWidth: 1))
    }
}
