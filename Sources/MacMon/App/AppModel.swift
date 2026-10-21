import AppKit
import Combine
import Foundation

/// 界面状态与采集调度。
///
/// 采集全部在一条串行后台队列上跑，结果回到主线程发布；
/// 主线程只做渲染，不会被 `proc_pidinfo` 之类的系统调用卡住。
@MainActor
final class AppModel: ObservableObject {

    // MARK: 发布状态

    @Published private(set) var snapshot = MetricsSnapshot()
    @Published private(set) var meta = SystemMeta()
    @Published private(set) var appGroups: [AppGroup] = []
    @Published private(set) var startup = StartupSnapshot()
    @Published private(set) var alerts: [Alert] = []

    /// 启动项变更历史，最新的在前，最多 20 条（与落盘文件保持一致）
    @Published private(set) var startupChanges: [StartupChange] = []

    /// 全量进程（已按 CPU 降序），进程页直接消费。
    /// 与 `snapshot` 分开：snapshot 每秒重建，塞 700 行进去会白白复制大数组。
    @Published private(set) var allProcesses: [ProcessRow] = []
    @Published private(set) var processTotal = 0

    @Published private(set) var cpuHistory: [Double] = []
    @Published private(set) var tempHistory: [Double] = []
    @Published private(set) var netHistory: [Double] = []
    @Published private(set) var netRxHistory: [Double] = []
    @Published private(set) var netTxHistory: [Double] = []
    @Published private(set) var memHistory: [Double] = []
    @Published private(set) var diskHistory: [Double] = []

    @Published private(set) var lastUpdate = Date()
    @Published private(set) var isWarming = true

    // MARK: 私有

    private let hub = CollectorHub()
    private let queue = DispatchQueue(label: "com.macmon.collect", qos: .utility)
    private var timer: Timer?
    private var tick = 0
    private var inFlight = false
    private let historyLimit = 150

    // 启动项监控
    private let changeStore = StartupChangeStore()
    private lazy var watcher = StartupWatcher(paths: StartupCollector.watchPaths) { [weak self] in
        // 回调在监听队列上，这里必须切回主线程再碰 @Published 状态
        Task { @MainActor in self?.requestStartupRescan() }
    }
    private var hasStartupBaseline = false
    private var startupScanInFlight = false
    private var startupRescanPending = false

    // MARK: - 生命周期

    func start() {
        // 幂等：窗口被红叉关掉再打开会重跑 onAppear，
        // 不挡就会起第二个 Timer，采集量直接翻倍
        guard timer == nil else { return }

        loadMeta()
        startupChanges = changeStore.load()

        // 首帧分三段发布：先指标（0.4s 内上屏），再进程，最后启动项。
        // 三段串行但互不阻塞——否则进程扫描 + 24 个启动项验签要好几秒，
        // 用户看到的是整屏「预热中」和一片 0。
        queue.async { [hub] in
            hub.warmup()
            let first = hub.fastSnapshot()

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.apply(fast: first)
                self.isWarming = false
                self.rebuildAlerts()
            }

            let rows = hub.processRows()
            DispatchQueue.main.async { [weak self] in
                self?.applyProcesses(rows)
                self?.rebuildAlerts()
            }
        }

        // 启动项首扫走和后续重扫同一个闸门，避免和 FSEvents 触发的扫描并发
        startupScanInFlight = true
        queue.async { [hub] in
            let snapshot = hub.startupSnapshot()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.startupScanInFlight = false
                self.applyStartup(snapshot)
                if self.startupRescanPending {
                    self.startupRescanPending = false
                    self.requestStartupRescan()
                }
            }
        }

        watcher.start()

        let timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.loop() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        watcher.stop()
    }

    private func loop() {
        guard !inFlight else { return }
        inFlight = true
        tick += 1
        let collectProcesses = tick % 3 == 0
        // 60s 兜底重扫：FSEvents 在队列积压、睡眠唤醒、流创建时路径不存在等
        // 情况下会漏事件，轮询是最后一道保险
        let fallbackRescan = tick % 60 == 0

        queue.async { [weak self, hub] in
            let fast = hub.fastSnapshot()
            let rows: [ProcessRow]? = collectProcesses ? hub.processRows() : nil

            DispatchQueue.main.async {
                guard let self else { return }
                self.apply(fast: fast)
                if let rows { self.applyProcesses(rows) }
                self.inFlight = false
                self.rebuildAlerts()
            }
        }

        if fallbackRescan {
            requestStartupRescan()
        }
    }

    // MARK: - 应用采集结果

    private func apply(fast: MetricsSnapshot) {
        // 进程数据 3s 才更新一次，而快照 1s 一次；
        // 这里必须沿用上一轮的进程结果，否则会被空数组覆盖成「0 个进程」。
        var next = fast
        next.processes = snapshot.processes
        snapshot = next
        lastUpdate = Date()

        append(&cpuHistory, fast.cpu.total)
        append(&memHistory, fast.mem.usedPercent)
        // 温度读不到时不要写 0 占位——会把自适应量程的下界永远拉到 20，
        // 还会让「峰值」在预热阶段显示 0℃
        if let celsius = fast.temp.primaryC {
            append(&tempHistory, celsius)
        }
        append(&netHistory, fast.net.rxSec + fast.net.txSec)
        append(&netRxHistory, fast.net.rxSec)
        append(&netTxHistory, fast.net.txSec)
        // 磁盘记录的是「占用率」而不是读写速率：概览卡的大数字就是占用率，
        // 折线必须跟它同量纲，否则量程会是几百 MB/s，曲线被压成贴底的一条线。
        append(&diskHistory, fast.disk.usedPercent)
    }

    // MARK: - 启动项扫描与变更

    /// 启动项重扫的**唯一入口**。
    ///
    /// 用两个布尔标志做闸门，不用信号量：FSEvents 回调线程上等锁会把事件流堵死。
    /// 扫描正在跑时再来的请求只置一个 pending，等当前这轮结束后合并跑一次。
    func requestStartupRescan() {
        if startupScanInFlight {
            startupRescanPending = true
            return
        }
        startupScanInFlight = true

        queue.async { [hub] in
            let snapshot = hub.startupSnapshot()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.startupScanInFlight = false
                self.applyStartup(snapshot)
                if self.startupRescanPending {
                    self.startupRescanPending = false
                    self.requestStartupRescan()
                }
            }
        }
    }

    private func applyStartup(_ snapshot: StartupSnapshot) {
        let previous = startup
        startup = snapshot

        // 首扫只种基线：此时 `startup` 还是空快照，
        // 直接 diff 会一口气产出二十多条「新增启动项」
        guard hasStartupBaseline else {
            hasStartupBaseline = true
            rebuildAlerts()
            return
        }

        let changes = StartupDiff.compare(old: previous, new: snapshot)
        guard !changes.isEmpty else {
            rebuildAlerts()
            return
        }

        startupChanges = Array((changes + startupChanges).prefix(StartupChangeStore.limit))
        changeStore.save(startupChanges)

        // 一批变更只发一条系统通知
        let fresh = changes.filter { !$0.notified }
        if !fresh.isEmpty, StartupNotifier.shared.post(fresh) {
            markNotified(fresh.map(\.id))
        }

        rebuildAlerts()
    }

    private func markNotified(_ ids: [UUID]) {
        let target = Set(ids)
        guard startupChanges.contains(where: { target.contains($0.id) && !$0.notified }) else { return }
        for index in startupChanges.indices where target.contains(startupChanges[index].id) {
            startupChanges[index].notified = true
        }
        changeStore.save(startupChanges)
    }

    private static func alertLevel(for change: StartupChange) -> AlertLevel {
        switch change.kind {
        case .removed:
            return .info
        case .added:
            return change.riskScore >= 65 ? .critical : .warning
        case .modified:
            // 风险等级这一项变了就是升级（降级不会触发 diff，因为 text 相同才不记录）
            // 注意：`field` 是落盘用的中文键名，不能本地化，否则永远匹配不上
            return change.fields.contains { $0.field == "风险等级" } ? .critical : .warning
        }
    }

    private func applyProcesses(_ rows: [ProcessRow]) {
        guard !rows.isEmpty else { return }

        var enriched = rows
        let memTotal = max(Double(snapshot.mem.totalBytes), 1)
        for index in enriched.indices {
            let percent = Double(enriched[index].memRssBytes) / memTotal * 100
            enriched[index].memPercent = (percent * 10).rounded() / 10
        }

        ProcessRiskEngine.enrich(rows: &enriched)
        ProcessRiskEngine.attachKillability(to: &enriched)

        let sorted = enriched.sorted { $0.cpu > $1.cpu }
        let groups = ProcessRiskEngine.groupByApp(enriched)

        snapshot.processes = [
            ProcessSnapshotGroup(
                total: enriched.count,
                top: Array(sorted.prefix(5)),
                appGroups: groups
            )
        ]
        allProcesses = sorted
        processTotal = enriched.count
        if groups != appGroups {
            appGroups = Array(groups.prefix(8))
        }
    }

    private func append(_ buffer: inout [Double], _ value: Double) {
        buffer.append(value)
        if buffer.count > historyLimit {
            buffer.removeFirst(buffer.count - historyLimit)
        }
    }

    // MARK: - 元信息

    private func loadMeta() {
        var info = SystemMeta()
        info.hostname = Host.current().localizedName ?? "Mac"
        info.chip = hub.cpu.metrics.brand
        info.modelId = SysCtl.string("hw.model") ?? "—"
        info.osVersion = Self.osVersionText()
        info.kernel = SysCtl.string("kern.osrelease") ?? "—"
        info.memTotalBytes = ProcessInfo.processInfo.physicalMemory
        info.cores = hub.cpu.metrics.cores
        info.perfCores = hub.cpu.metrics.perfCores
        info.effCores = hub.cpu.metrics.effCores
        info.bootTime = Date().addingTimeInterval(-ProcessInfo.processInfo.systemUptime)
        info.model = SysCtl.string("hw.model") ?? "Mac"
        meta = info
        snapshot.cpu = hub.cpu.metrics
    }

    private static func osVersionText() -> String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        var text = "macOS \(version.majorVersion).\(version.minorVersion)"
        if version.patchVersion > 0 { text += ".\(version.patchVersion)" }
        return text
    }

    // MARK: - 告警

    private func rebuildAlerts() {
        var list: [Alert] = []
        let now = Date()

        if let temp = snapshot.temp.primaryC {
            if temp >= 95 {
                list.append(Alert(
                    id: UUID(), level: .critical,
                    title: L.t("温度过高"),
                    detail: String(format: L.t("CPU %.1f°C，已接近降频阈值"), temp),
                    createdAt: now, source: L.t("温度")
                ))
            } else if temp >= 85 {
                list.append(Alert(
                    id: UUID(), level: .warning,
                    title: L.t("温度偏高"),
                    detail: String(format: "CPU %.1f°C", temp),
                    createdAt: now, source: L.t("温度")
                ))
            }
        }

        if snapshot.mem.usedPercent >= 90 {
            list.append(Alert(
                id: UUID(), level: .critical,
                title: L.t("内存吃紧"),
                detail: String(format: L.t("已用 %.0f%%，可能触发交换"), snapshot.mem.usedPercent),
                createdAt: now, source: L.t("内存")
            ))
        }

        if snapshot.disk.usedPercent >= 92 {
            list.append(Alert(
                id: UUID(), level: .warning,
                title: L.t("磁盘空间不足"),
                detail: String(format: L.t("%.0f%% 已用"), snapshot.disk.usedPercent),
                createdAt: now, source: L.t("磁盘")
            ))
        }

        let riskyStartup = startup.items.filter { $0.risk.level >= .high }
        if !riskyStartup.isEmpty {
            list.append(Alert(
                id: UUID(), level: .warning,
                title: L.f("发现 %@ 个高风险启动项", riskyStartup.count),
                detail: riskyStartup.prefix(3).map(\.label).joined(separator: "、"),
                createdAt: now, source: L.t("启动项")
            ))
        }

        // 最近 10 分钟内的变更，最多 2 条。
        // `Alert.id` 直接复用 `change.id`（UUID 落盘不变），
        // 所以每秒重建列表也不会重复插入或闪烁。
        let recentChanges = startupChanges
            .filter { now.timeIntervalSince($0.detectedAt) < 600 }
            .prefix(2)
        for change in recentChanges {
            list.append(Alert(
                id: change.id,
                level: Self.alertLevel(for: change),
                title: change.title,
                detail: change.detail,
                createdAt: change.detectedAt,
                source: L.t("启动项变更")
            ))
        }

        let riskyProcesses = snapshot.processes.first?.top.filter { $0.risk.level >= .high } ?? []
        if !riskyProcesses.isEmpty {
            list.append(Alert(
                id: UUID(), level: .warning,
                title: L.f("发现 %@ 个高风险进程", riskyProcesses.count),
                detail: riskyProcesses.prefix(3).map(\.name).joined(separator: "、"),
                createdAt: now, source: L.t("进程")
            ))
        }

        alerts = list
    }

    // MARK: - 派生数据

    var uptimeText: String {
        Fmt.duration(ProcessInfo.processInfo.systemUptime)
    }

    var topProcesses: [ProcessRow] {
        Array(allProcesses.prefix(8))
    }
}
