import Foundation

/// 两次启动项快照的差异计算。
///
/// 纯函数，不碰文件系统、不碰全局状态，方便单独验证。
enum StartupDiff {

    /// diff 的比对键。
    ///
    /// **必须用 `plistPath`，不能用 `StartupItem.id`**：后者是 `kind|label`，
    /// 两个 Label 相同但分处不同目录的 plist 会互相覆盖；改一下 Label
    /// 会被判成「删了一条 + 加了一条」，而实际只是改了个名字。
    private static func key(_ item: StartupItem) -> String {
        item.plistPath
    }

    /// 参与比较的字段：只挑**行为语义**，不挑噪音。
    ///
    /// 明确排除：
    /// - `fileModified`：`touch`、重存、备份还原都会变，跟行为无关
    /// - `pid` / `loaded`：当前根本没人赋值，永远是同一个值
    /// - `signing.authority`：已经由 `risk.level` 汇总体现
    static func compare(
        old: StartupSnapshot,
        new: StartupSnapshot,
        now: Date = Date()
    ) -> [StartupChange] {
        let oldMap = Dictionary(old.items.map { (key($0), $0) }, uniquingKeysWith: { a, _ in a })
        let newMap = Dictionary(new.items.map { (key($0), $0) }, uniquingKeysWith: { a, _ in a })

        var changes: [StartupChange] = []

        // 新增：旧一轮有目录读失败的话，该类的「新增」大概率是假警报
        // （之前根本看不见，不是真的刚被创建）
        for (path, item) in newMap where oldMap[path] == nil {
            if old.unavailableKinds.contains(item.kind) { continue }
            changes.append(makeChange(kind: .added, item: item, fields: [], at: now))
        }

        // 移除：同样跳过本轮读失败的类别
        for (path, item) in oldMap where newMap[path] == nil {
            if new.unavailableKinds.contains(item.kind) { continue }
            changes.append(makeChange(kind: .removed, item: item, fields: [], at: now))
        }

        // 修改
        for (path, newItem) in newMap {
            guard let oldItem = oldMap[path] else { continue }
            let fields = fieldChanges(old: oldItem, new: newItem)
            if !fields.isEmpty {
                changes.append(makeChange(kind: .modified, item: newItem, fields: fields, at: now))
            }
        }

        // 高风险排前面，同分按名称，保证每次顺序稳定（否则告警列表会每秒抖动）
        changes.sort { lhs, rhs in
            if lhs.riskScore != rhs.riskScore { return lhs.riskScore > rhs.riskScore }
            return lhs.label.localizedCompare(rhs.label) == .orderedAscending
        }
        return changes
    }

    private static func makeChange(
        kind: StartupChangeKind,
        item: StartupItem,
        fields: [FieldChange],
        at now: Date
    ) -> StartupChange {
        StartupChange(
            kind: kind,
            label: item.label,
            kindName: item.kind.rawValue,
            plistPath: item.plistPath,
            programPath: item.programPath,
            detectedAt: now,
            riskLevel: item.risk.level.rawValue,
            riskScore: item.risk.score,
            fields: fields
        )
    }

    private static func fieldChanges(old: StartupItem, new: StartupItem) -> [FieldChange] {
        var result: [FieldChange] = []

        func diff(_ name: String, _ lhs: String?, _ rhs: String?) {
            if lhs != rhs {
                result.append(FieldChange(field: name, old: lhs, new: rhs))
            }
        }
        func diffBool(_ name: String, _ lhs: Bool, _ rhs: Bool) {
            if lhs != rhs {
                result.append(FieldChange(field: name, old: lhs ? "true" : "false", new: rhs ? "true" : "false"))
            }
        }

        diff("Label", old.label, new.label)
        diff("Program", old.programPath, new.programPath)
        diffBool("RunAtLoad", old.runAtLoad, new.runAtLoad)
        diffBool("KeepAlive", old.keepAlive, new.keepAlive)
        diffBool("LoginWindow", old.runsAtLoginWindow, new.runsAtLoginWindow)
        diff("BundleId", old.associatedBundleId, new.associatedBundleId)
        diff(
            "ThrottleInterval",
            old.throttleInterval.map(String.init),
            new.throttleInterval.map(String.init)
        )
        diffBool("可执行文件存在", old.programExists, new.programExists)

        if old.risk.level != new.risk.level {
            result.append(FieldChange(
                field: "风险等级",
                old: old.risk.level.rawValue,
                new: new.risk.level.rawValue
            ))
        }

        return result
    }
}
