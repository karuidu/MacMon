import Foundation

/// 把进程的可执行路径回溯到所属的 `.app` bundle，并读取 Info.plist。
///
/// 这是「进程关联应用」的核心：Chrome 会同时跑 5 个 helper，
/// 它们路径各不相同，但都能回溯到同一个 `Google Chrome.app`。
enum AppResolver {

    struct AppInfo {
        let name: String
        let bundleId: String?
        let appPath: String
    }

    private static var cache: [String: AppInfo?] = [:]
    private static let lock = NSLock()

    /// 从可执行路径回溯到 `.app` 祖先
    static func resolve(executablePath: String) -> AppInfo? {
        guard !executablePath.isEmpty, executablePath.hasPrefix("/") else { return nil }

        var url = URL(fileURLWithPath: executablePath)

        // 最多向上回溯 8 层，避免异常路径导致长循环
        for _ in 0..<10 {
            if url.pathExtension == "app" {
                // Electron 的 helper 本身也是 .app，但嵌在
                // `Xxx.app/Contents/Frameworks/Xxx Helper.app` 下。
                // 这类要继续向上，归属到主应用而不是 helper 自己。
                if url.path.contains("/Contents/Frameworks/") {
                    let parent = url.deletingLastPathComponent()
                    if parent.path != url.path, parent.path != "/" {
                        url = parent
                        continue
                    }
                }
                return info(forAppAt: url.path)
            }
            let parent = url.deletingLastPathComponent()
            if parent.path == url.path || parent.path == "/" { break }
            url = parent
        }
        return nil
    }

    private static func info(forAppAt appPath: String) -> AppInfo {
        lock.lock()
        if let hit = cache[appPath] {
            lock.unlock()
            return hit ?? fallback(appPath: appPath)
        }
        lock.unlock()

        let plistPath = (appPath as NSString)
            .appendingPathComponent("Contents/Info.plist")

        var parsed: AppInfo?
        if let dict = NSDictionary(contentsOfFile: plistPath) as? [String: Any] {
            let display = dict["CFBundleDisplayName"] as? String
            let bundleName = dict["CFBundleName"] as? String
            let bundleId = dict["CFBundleIdentifier"] as? String
            let fallbackName = (appPath as NSString).lastPathComponent
                .replacingOccurrences(of: ".app", with: "")
            parsed = AppInfo(
                name: display ?? bundleName ?? fallbackName,
                bundleId: bundleId,
                appPath: appPath
            )
        }

        lock.lock()
        cache[appPath] = parsed
        lock.unlock()

        return parsed ?? fallback(appPath: appPath)
    }

    private static func fallback(appPath: String) -> AppInfo {
        AppInfo(
            name: (appPath as NSString).lastPathComponent
                .replacingOccurrences(of: ".app", with: ""),
            bundleId: nil,
            appPath: appPath
        )
    }
}
