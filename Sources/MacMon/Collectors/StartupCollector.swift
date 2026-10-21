import Foundation

/// 启动项扫描：三个 macOS 持久化目录。
///
/// 这三个目录覆盖了绝大多数「开机自启」实现，且**全部可读、无需提权**。
/// 系统设置里的「登录项」列表看不到它们，这正是这类审计的价值所在。
final class StartupCollector {

    struct Location {
        let path: String
        let kind: StartupKind
    }

    /// 需要监听的目录。`StartupWatcher` 直接复用这份清单，
    /// 避免「扫描看三处、监听只看两处」这种静默漏判。
    static let watchPaths: [String] = {
        let home = NSHomeDirectory()
        return [
            "\(home)/Library/LaunchAgents",
            "/Library/LaunchAgents",
            "/Library/LaunchDaemons"
        ]
    }()

    private let locations: [Location] = [
        Location(path: watchPaths[0], kind: .userAgent),
        Location(path: watchPaths[1], kind: .globalAgent),
        Location(path: watchPaths[2], kind: .globalDaemon)
    ]

    func scan() -> StartupSnapshot {
        var items: [StartupItem] = []
        var unavailable: Set<StartupKind> = []

        for location in locations {
            guard let entries = try? FileManager.default.contentsOfDirectory(atPath: location.path) else {
                // 记下失败类别：diff 会据此跳过该类的「移除」判定，
                // 否则一次瞬时读取失败就会报十几条「启动项被移除」
                unavailable.insert(location.kind)
                continue
            }
            for entry in entries where entry.hasSuffix(".plist") {
                let fullPath = (location.path as NSString).appendingPathComponent(entry)
                if let item = parse(plistPath: fullPath, kind: location.kind) {
                    items.append(item)
                }
            }
        }

        // 风险项排在前面，其次按名称
        items.sort { lhs, rhs in
            if lhs.risk.level != rhs.risk.level {
                return lhs.risk.level > rhs.risk.level
            }
            return lhs.label.localizedCompare(rhs.label) == .orderedAscending
        }

        var snapshot = StartupSnapshot()
        snapshot.items = items
        snapshot.scannedAt = Date()
        snapshot.privilegedCount = items.filter { $0.kind.isPrivileged }.count
        snapshot.riskyCount = items.filter { $0.risk.level >= .medium }.count
        snapshot.unavailableKinds = unavailable
        return snapshot
    }

    // MARK: - 单个 plist 解析

    private func parse(plistPath: String, kind: StartupKind) -> StartupItem? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: plistPath)),
              let raw = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dict = raw as? [String: Any] else {
            return nil
        }

        let label = dict["Label"] as? String
            ?? (plistPath as NSString).lastPathComponent.replacingOccurrences(of: ".plist", with: "")

        var programPath = dict["Program"] as? String
        if programPath == nil,
           let args = dict["ProgramArguments"] as? [String],
           let first = args.first {
            programPath = first
        }

        var item = StartupItem(
            label: label,
            kind: kind,
            plistPath: plistPath,
            programPath: programPath
        )

        item.runAtLoad = (dict["RunAtLoad"] as? Bool) ?? false
        item.keepAlive = Self.isKeepAlive(dict["KeepAlive"])
        item.throttleInterval = (dict["ThrottleInterval"] as? Int)
        item.associatedBundleId = (dict["AssociatedBundleIdentifiers"] as? [String])?.first

        if let session = dict["LimitLoadToSessionType"] as? String {
            item.runsAtLoginWindow = session == "LoginWindow"
        } else if let sessions = dict["LimitLoadToSessionType"] as? [String] {
            item.runsAtLoginWindow = sessions.contains("LoginWindow")
        }

        if let attributes = try? FileManager.default.attributesOfItem(atPath: plistPath) {
            item.fileModified = attributes[.modificationDate] as? Date
        }

        if let programPath {
            item.programExists = FileManager.default.fileExists(atPath: programPath)
            item.signing = SecurityAudit.signingInfo(path: programPath)
        }

        item.risk = Self.assess(item)
        return item
    }

    private static func isKeepAlive(_ value: Any?) -> Bool {
        if let flag = value as? Bool { return flag }
        if value is [String: Any] { return true }  // 条件式 KeepAlive 同样会拉起进程
        return false
    }

    // MARK: - 风险评分

    static func assess(_ item: StartupItem) -> RiskAssessment {
        var reasons: [RiskReason] = []

        if let programPath = item.programPath {
            if !item.programExists {
                reasons.append(RiskReason(text: L.t("指向的可执行文件不存在（卸载残留）"), weight: 25))
            }
            if Self.isSuspiciousPath(programPath) {
                reasons.append(RiskReason(text: L.f("可执行文件位于可疑目录：%@", programPath), weight: 40))
            }
            if item.programExists, item.signing.kind == .adhoc {
                reasons.append(RiskReason(text: L.t("仅临时签名（ad-hoc），未通过开发者验证"), weight: 35))
            } else if item.programExists, item.signing.kind == .unsigned {
                reasons.append(RiskReason(text: L.t("未签名或签名已失效"), weight: 40))
            }
        } else {
            reasons.append(RiskReason(text: L.t("未声明 Program / ProgramArguments"), weight: 15))
        }

        if item.runAtLoad && item.keepAlive {
            let inApplications = item.programPath?.hasPrefix("/Applications/") ?? false
            let inLibrary = item.programPath?.hasPrefix("/Library/") ?? false
            if !inApplications && !inLibrary {
                reasons.append(RiskReason(text: L.t("开机自启且被结束后自动重启，路径不在标准安装位置"), weight: 20))
            }
        }

        if item.runsAtLoginWindow {
            reasons.append(RiskReason(text: L.t("在登录窗口（尚未登录时）即加载"), weight: 15))
        }

        if item.kind.isPrivileged {
            reasons.append(RiskReason(text: L.t("以 root 权限常驻的系统级守护进程"), weight: 8))
        }

        return RiskAssessment.from(reasons: reasons)
    }

    private static func isSuspiciousPath(_ path: String) -> Bool {
        let suspicious = ["/tmp/", "/var/tmp/", "/private/tmp/", "/var/folders/"]
        if suspicious.contains(where: { path.hasPrefix($0) }) { return true }
        if path.contains("/Downloads/") { return true }
        if path.contains("/Library/Caches/") { return true }
        return false
    }
}
