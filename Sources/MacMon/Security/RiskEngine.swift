import Foundation

/// 进程风险评分与「按应用聚合」。
///
/// 设计取舍：**不逐个验签**。700+ 个进程各跑一次 Security.framework 会拖垮采集循环，
/// 因此只对「路径不在系统签名区」且 CPU 排名靠前的进程验签，其余仅做路径规则判断。
enum ProcessRiskEngine {

    /// 系统签名区：这些路径下的二进制由 Apple 或系统安装器提供，无需验签
    private static let trustedPrefixes = [
        "/System/",
        "/usr/lib/",
        "/usr/libexec/",
        "/usr/sbin/",
        "/usr/bin/",
        "/bin/",
        "/sbin/",
        "/Library/Apple/",
        "/Applications/Utilities/"
    ]

    private static let suspiciousPrefixes = [
        "/tmp/",
        "/private/tmp/",
        "/var/tmp/",
        "/var/folders/",
        "/Library/Caches/"
    ]

    /// 就地写入 appName / bundleId / signing / risk
    static func enrich(rows: inout [ProcessRow], verifyBudget: Int = 50) {
        var verified = 0

        for index in rows.indices {
            var row = rows[index]

            // 1. 应用归属
            if !row.path.isEmpty, let app = AppResolver.resolve(executablePath: row.path) {
                row.appName = app.name
                row.bundleId = app.bundleId
                row.appPath = app.appPath
            }

            // 2. 风险规则
            var reasons: [RiskReason] = []

            if !row.path.isEmpty {
                if suspiciousPrefixes.contains(where: { row.path.hasPrefix($0) }) {
                    reasons.append(RiskReason(text: L.t("可执行文件位于可疑目录"), weight: 40))
                }

                if isMasquerading(row) {
                    reasons.append(RiskReason(text: L.t("进程名伪装成系统组件，但不在系统目录"), weight: 35))
                }

                // 3. 签名校验（有预算上限）
                if !isTrustedPath(row.path), verified < verifyBudget {
                    let signing = SecurityAudit.signingInfo(path: row.path)
                    row.signing = signing
                    verified += 1

                    switch signing.kind {
                    case .adhoc:
                        reasons.append(RiskReason(text: L.t("仅临时签名（ad-hoc）"), weight: 30))
                    case .unsigned:
                        reasons.append(RiskReason(text: L.t("未签名或签名失效"), weight: 35))
                    default:
                        break
                    }
                }
            }

            row.risk = RiskAssessment.from(reasons: reasons)
            rows[index] = row
        }
    }

    /// 按应用聚合：把同一 bundle 的多个进程合并成一行
    static func groupByApp(_ rows: [ProcessRow]) -> [AppGroup] {
        var buckets: [String: (name: String, bundleId: String?, appPath: String?,
                               count: Int, cpu: Double, mem: UInt64, risk: RiskAssessment)] = [:]

        for row in rows {
            // 没有归属应用的进程按自身名字单独成组，避免全部挤进「其他」
            let key = row.bundleId ?? row.appName ?? "pid:\(row.pid)"
            let name = row.appName ?? row.name

            if var existing = buckets[key] {
                existing.count += 1
                existing.cpu += row.cpu
                existing.mem += row.memRssBytes
                if row.risk.level > existing.risk.level { existing.risk = row.risk }
                buckets[key] = existing
            } else {
                buckets[key] = (
                    name: name,
                    bundleId: row.bundleId,
                    appPath: row.appPath,
                    count: 1,
                    cpu: row.cpu,
                    mem: row.memRssBytes,
                    risk: row.risk
                )
            }
        }

        return buckets.map { key, value in
            AppGroup(
                id: key,
                appName: value.name,
                bundleId: value.bundleId,
                appPath: value.appPath,
                processCount: value.count,
                cpu: (value.cpu * 10).rounded() / 10,
                memBytes: value.mem,
                risk: value.risk
            )
        }
        .sorted { $0.cpu > $1.cpu }
    }

    // MARK: - 可结束性

    /// 系统关键进程黑名单：结束它们会导致注销、掉声卡或 Spotlight 重建
    private static let denyNames: Set<String> = [
        "kernel_task", "launchd", "windowserver", "loginwindow", "logind",
        "opendirectoryd", "powerd", "configd", "coreaudiod", "watchdogd",
        "runningboardd", "syslogd", "diskarbitrationd", "securityd",
        "notifyd", "distnoted", "cfprefsd"
    ]

    private static let denyPrefixes = ["mds", "mdworker"]

    /// 预计算「能否结束」，让界面直接禁用按钮，而不是点下去才被拒
    static func attachKillability(to rows: inout [ProcessRow]) {
        let selfPid = ProcessInfo.processInfo.processIdentifier
        let selfUser = UserNames.name(for: getuid())

        for index in rows.indices {
            var row = rows[index]
            row.killable = true
            row.killBlockedReason = nil

            let name = row.name.lowercased()

            if row.pid <= 1 {
                row.killable = false
                row.killBlockedReason = L.t("系统保留进程")
            } else if row.pid == selfPid {
                row.killable = false
                row.killBlockedReason = L.t("不能结束监控自身")
            } else if denyNames.contains(name) || denyPrefixes.contains(where: { name.hasPrefix($0) }) {
                row.killable = false
                row.killBlockedReason = L.t("系统关键进程")
            } else if row.user != selfUser {
                // 非本用户进程普通权限下无法结束（ps 之所以能读是因为 setuid root）
                row.killable = false
                row.killBlockedReason = L.f("属于用户「%@」，无权限", row.user)
            } else if row.path.isEmpty {
                row.killable = false
                row.killBlockedReason = L.t("内核线程，不可结束")
            }

            rows[index] = row
        }
    }

    // MARK: - 辅助

    private static func isTrustedPath(_ path: String) -> Bool {
        trustedPrefixes.contains { path.hasPrefix($0) }
    }

    /// 名字看起来像系统组件，但二进制不在系统目录
    private static func isMasquerading(_ row: ProcessRow) -> Bool {
        guard !isTrustedPath(row.path) else { return false }
        let name = row.name.lowercased()
        if name.hasPrefix("com.apple.") || name.hasPrefix("apple") { return true }
        if name.hasPrefix("kernel_") || name == "launchd" || name == "windowserver" { return true }
        return false
    }
}
