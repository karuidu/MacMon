import Foundation

// MARK: - CPU

struct CoreLoad: Identifiable, Sendable {
    let id: Int
    let index: Int
    let load: Double          // 0...100
    let cluster: CoreCluster
}

enum CoreCluster: String, Sendable {
    case performance = "P"
    case efficiency  = "E"
}

struct CPUMetrics: Sendable {
    var total: Double = 0
    var user: Double = 0
    var system: Double = 0
    var idle: Double = 100
    var perCore: [CoreLoad] = []
    var loadAvg: (Double, Double, Double) = (0, 0, 0)
    var cores: Int = 0
    var perfCores: Int = 0
    var effCores: Int = 0
    var brand: String = ""
}

// MARK: - 内存

enum MemoryPressure: String, Sendable {
    case normal, warning, critical

    var label: String {
        switch self {
        case .normal:   return L.t("正常")
        case .warning:  return L.t("偏高")
        case .critical: return L.t("紧张")
        }
    }
}

struct MemMetrics: Sendable {
    var totalBytes: UInt64 = 0
    /// 已使用内存 = internal + wired + compressed（与活动监视器一致）
    var usedBytes: UInt64 = 0
    var availableBytes: UInt64 = 0
    /// App 内存 = internal − purgeable
    var appBytes: UInt64 = 0
    /// vm_stat 的 active_count，队列口径（含文件缓存），仅供诊断
    var activeBytes: UInt64 = 0
    var wiredBytes: UInt64 = 0
    var compressedBytes: UInt64 = 0
    /// 已缓存文件 = external
    var cachedBytes: UInt64 = 0
    /// 可清除页
    var purgeableBytes: UInt64 = 0
    var freeBytes: UInt64 = 0
    var swapTotalBytes: UInt64 = 0
    var swapUsedBytes: UInt64 = 0
    var pressure: MemoryPressure = .normal

    var usedPercent: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(usedBytes) / Double(totalBytes) * 100
    }
}

// MARK: - 温度

struct TempStatus: Sendable {
    var cpuC: Double?
    var socC: Double?
    var gpuC: Double?
    var batteryC: Double?
    var fanRpm: [Double] = []
    /// 数据来源的人话描述，例如「SMC」「HID 传感器」
    var source: String = "—"
    var sensorCount: Int = 0

    var primaryC: Double? { cpuC ?? socC ?? batteryC }
    var hasAny: Bool { primaryC != nil }
}

// MARK: - 网络 / 磁盘

struct NetMetrics: Sendable {
    var iface: String = "—"
    var rxSec: Double = 0
    var txSec: Double = 0
    var rxTotal: UInt64 = 0
    var txTotal: UInt64 = 0
}

struct DiskMetrics: Sendable {
    var readSec: Double = 0
    var writeSec: Double = 0
    var volumeName: String = "Macintosh HD"
    var totalBytes: UInt64 = 0
    var usedBytes: UInt64 = 0

    var usedPercent: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(usedBytes) / Double(totalBytes) * 100
    }
}

// MARK: - 电池

struct BatteryMetrics: Sendable {
    var present: Bool = false
    var percent: Double = 0
    var isCharging: Bool = false
    var acConnected: Bool = false
    var cycleCount: Int = 0
    var healthPercent: Double?
    var temperatureC: Double?
    var timeRemainingMin: Int?
    var condition: String?
}

// MARK: - 进程

struct ProcessRow: Identifiable, Sendable, Equatable {
    let pid: Int32
    var id: Int32 { pid }

    var ppid: Int32 = 0
    var name: String = ""
    var path: String = ""
    var user: String = ""
    var cpu: Double = 0
    var memPercent: Double = 0
    var memRssBytes: UInt64 = 0
    var state: String = ""
    var threadCount: Int = 0

    /// 归属应用（.app bundle 解析结果）
    var appName: String?
    var bundleId: String?
    var appPath: String?

    /// 安全审计
    var signing: SigningInfo = .unknown
    var risk: RiskAssessment = .none

    /// 可结束性（预计算，前端直接禁用按钮）
    var killable: Bool = true
    var killBlockedReason: String?
}

/// 进程归属的应用聚合视图
struct AppGroup: Identifiable, Sendable, Equatable {
    /// 聚合键：优先 bundleId，无归属的进程退回 "pid:xxx"
    var id: String
    var appName: String
    var bundleId: String?
    var appPath: String?
    var processCount: Int
    var cpu: Double
    var memBytes: UInt64
    var risk: RiskAssessment
}

// MARK: - 签名

/// 签名类型。`rawValue` 是稳定标识，**不再兼作显示文案**——
/// 界面语言可切换，而 rawValue 一旦兼作展示就没法跟着变。
enum SigningKind: String, Sendable, Codable {
    case apple, developerId, adhoc, unsigned, unknown

    var label: String {
        switch self {
        case .apple:       return L.t("Apple 签名")
        case .developerId: return "Developer ID"
        case .adhoc:       return L.t("临时签名")
        case .unsigned:    return L.t("未签名")
        case .unknown:     return L.t("未知")
        }
    }

    var isTrustworthy: Bool {
        self == .apple || self == .developerId
    }
}

struct SigningInfo: Sendable, Equatable {
    var kind: SigningKind = .unknown
    var teamId: String?
    var authority: String?

    static let unknown = SigningInfo()
}

// MARK: - 风险

/// 风险等级。`rawValue` 是稳定标识，显示走 `label`。
enum RiskLevel: String, Sendable, Comparable, Codable {
    case none, low, medium, high, critical

    var order: Int {
        switch self {
        case .none: return 0
        case .low: return 1
        case .medium: return 2
        case .high: return 3
        case .critical: return 4
        }
    }

    var label: String {
        switch self {
        case .none:     return L.t("无")
        case .low:      return L.t("低")
        case .medium:   return L.t("中")
        case .high:     return L.t("高")
        case .critical: return L.t("严重")
        }
    }

    /// 兼容旧版落盘的 JSON：那时 `riskLevel` 字段存的是中文原文。
    static func fromStored(_ raw: String) -> RiskLevel? {
        if let level = RiskLevel(rawValue: raw) { return level }
        switch raw {
        case "无":   return RiskLevel.none
        case "低":   return .low
        case "中":   return .medium
        case "高":   return .high
        case "严重": return .critical
        default:     return nil
        }
    }

    static func < (lhs: RiskLevel, rhs: RiskLevel) -> Bool { lhs.order < rhs.order }
}

struct RiskReason: Identifiable, Sendable, Equatable {
    let id = UUID()
    var text: String
    var weight: Int

    /// 相等性忽略 UUID，否则每次重建都被判为「不同」，`.equatable()` 会失效
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.text == rhs.text && lhs.weight == rhs.weight
    }
}

struct RiskAssessment: Sendable, Equatable {
    var score: Int = 0
    var level: RiskLevel = .none
    var reasons: [RiskReason] = []

    static let none = RiskAssessment()

    static func from(reasons: [RiskReason]) -> RiskAssessment {
        let score = min(100, reasons.reduce(0) { $0 + $1.weight })
        let level: RiskLevel
        switch score {
        case 0..<20:   level = .none
        case 20..<40:  level = .low
        case 40..<65:  level = .medium
        case 65..<85:  level = .high
        default:       level = .critical
        }
        return RiskAssessment(score: score, level: level, reasons: reasons)
    }
}

// MARK: - 启动项

/// 启动项所处位置。`rawValue` 是稳定标识，显示走 `label`。
enum StartupKind: String, Sendable, Codable {
    case userAgent, globalAgent, globalDaemon

    var label: String {
        switch self {
        case .userAgent:    return L.t("用户 LaunchAgent")
        case .globalAgent:  return L.t("全局 LaunchAgent")
        case .globalDaemon: return L.t("系统 LaunchDaemon")
        }
    }

    var isPrivileged: Bool { self == .globalDaemon }

    /// 兼容旧版落盘的 JSON：那时 `kindName` 字段存的是中文原文。
    static func fromStored(_ raw: String) -> StartupKind? {
        if let kind = StartupKind(rawValue: raw) { return kind }
        switch raw {
        case "用户 LaunchAgent":  return .userAgent
        case "全局 LaunchAgent":  return .globalAgent
        case "系统 LaunchDaemon": return .globalDaemon
        default:                  return nil
        }
    }
}

struct StartupItem: Identifiable, Sendable {
    var id: String { "\(kind.rawValue)|\(label)" }

    var label: String
    var kind: StartupKind
    var plistPath: String
    var programPath: String?
    var programExists: Bool = true
    var runAtLoad: Bool = false
    var keepAlive: Bool = false
    var runsAtLoginWindow: Bool = false
    var throttleInterval: Int?
    var associatedBundleId: String?
    var fileModified: Date?

    var signing: SigningInfo = .unknown
    var risk: RiskAssessment = .none

    /// launchctl 当前是否已加载
    var loaded: Bool = false
    var pid: Int32?
}

// MARK: - 告警

enum AlertLevel: String, Sendable {
    case info, warning, critical
}

struct Alert: Identifiable, Sendable {
    let id: UUID
    var level: AlertLevel
    var title: String
    var detail: String
    var createdAt: Date
    var source: String
}

// MARK: - 系统元信息

struct SystemMeta: Sendable {
    var hostname: String = ""
    var model: String = ""
    var modelId: String = ""
    var chip: String = ""
    var osVersion: String = ""
    var kernel: String = ""
    var memTotalBytes: UInt64 = 0
    var bootTime: Date = Date()
    var cores: Int = 0
    var perfCores: Int = 0
    var effCores: Int = 0
}

// MARK: - 快照

struct MetricsSnapshot: Sendable {
    var cpu = CPUMetrics()
    var mem = MemMetrics()
    var temp = TempStatus()
    var net = NetMetrics()
    var disk = DiskMetrics()
    var battery = BatteryMetrics()
    var processes: [ProcessSnapshotGroup] = []
    var startup: StartupSnapshot = .init()
    var alerts: [Alert] = []
    var updatedAt: Date = Date()

    var uptimeSec: TimeInterval { Date().timeIntervalSince(Date().addingTimeInterval(-ProcessInfo.processInfo.systemUptime)) }
}

struct ProcessSnapshotGroup: Sendable {
    var total: Int = 0
    var top: [ProcessRow] = []
    var appGroups: [AppGroup] = []
}

struct StartupSnapshot: Sendable {
    var items: [StartupItem] = []
    var scannedAt: Date = Date()
    var privilegedCount: Int = 0
    var riskyCount: Int = 0

    /// 本轮读目录失败的类别。
    ///
    /// `scan()` 用 `try? contentsOfDirectory` 时，「没有权限」和「目录为空」返回结果一模一样。
    /// 不记录失败类别的话，一次瞬时读取失败会被 diff 判成「这十几个启动项全被移除了」，
    /// 于是每弹一次都是十几条假警报。
    var unavailableKinds: Set<StartupKind> = []
}

// MARK: - 启动项变更

enum StartupChangeKind: String, Codable, Sendable {
    case added, removed, modified

    var label: String {
        switch self {
        case .added:    return L.t("新增")
        case .removed:  return L.t("移除")
        case .modified: return L.t("修改")
        }
    }
}

/// 单个字段的前后差异。`old` / `new` 用字符串存，纯粹为了落盘与展示方便。
struct FieldChange: Codable, Sendable, Equatable {
    var field: String
    var old: String?
    var new: String?

    /// `field` 大多是 plist 的原始键名（`RunAtLoad` 这种），不需要翻译；
    /// 少数合成字段（`可执行文件存在`、`风险等级`）在表里有对应英文，
    /// 查不到就原样显示，所以历史记录不必回写。
    var text: String {
        "\(L.t(field)): \(old ?? "—") → \(new ?? "—")"
    }
}

struct StartupChange: Identifiable, Codable, Sendable, Equatable {
    /// 落盘不变。同时用作 `Alert.id` 与系统通知的 identifier，
    /// 因此每秒重建告警列表也不会重复插入或闪烁。
    var id: UUID = UUID()
    var kind: StartupChangeKind
    var label: String
    /// `StartupKind.rawValue`（枚举本身没做 Codable）
    var kindName: String
    var plistPath: String
    var programPath: String?
    var detectedAt: Date = Date()
    var riskLevel: String
    var riskScore: Int
    var fields: [FieldChange] = []
    /// 已投递过系统通知，跨启动不重弹
    var notified: Bool = false

    /// `kindName` / `riskLevel` 落盘存的是稳定标识，旧版 JSON 里是中文原文，
    /// 显示时统一走 `fromStored` 兜底，所以历史记录切换语言也跟着变。
    var kindLabel: String {
        StartupKind.fromStored(kindName)?.label ?? kindName
    }

    var riskLabel: String {
        RiskLevel.fromStored(riskLevel)?.label ?? riskLevel
    }

    var title: String {
        switch kind {
        case .added:    return L.f("新增启动项 %@", label)
        case .removed:  return L.f("移除启动项 %@", label)
        case .modified: return L.f("修改启动项 %@", label)
        }
    }

    var detail: String {
        if !fields.isEmpty {
            return fields.prefix(2).map(\.text).joined(separator: " · ")
        }
        if let programPath {
            return "\(kindLabel) · \(programPath)"
        }
        return kindLabel
    }
}
