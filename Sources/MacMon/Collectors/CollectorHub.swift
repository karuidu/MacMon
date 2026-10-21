import Foundation

/// 采集中枢：集中持有所有采集器，只在**一条串行队列**上被调用。
///
/// 单独抽出来是为了让 `AppModel` 保持 `@MainActor` 纯净——
/// 否则后台队列里访问主线程隔离的属性，会触发真实的并发风险
/// （编译器给出 `main actor-isolated property can not be referenced from a Sendable closure`）。
final class CollectorHub: @unchecked Sendable {

    let cpu = CPUCollector()

    private let memory = MemoryCollector()
    private let temperature = TemperatureCollector()
    private let network = NetworkCollector()
    private let disk = DiskCollector()
    private let battery = BatteryCollector()
    private let processes = ProcessCollector()
    private let startupCollector = StartupCollector()

    private var didWarmup = false

    /// 预热：CPU、网络、磁盘都依赖两次采样之间的差值，首帧前先打一次底。
    /// 这里**不**采进程——那是一次 700 条的全量扫描，结果又不会被用到，
    /// 会让首屏白等好几秒。
    func warmup() {
        guard !didWarmup else { return }
        didWarmup = true
        _ = cpu.sample()
        _ = network.sample()
        _ = disk.sample()
        Thread.sleep(forTimeInterval: 0.35)
    }

    /// 1s 周期：CPU / 内存 / 温度 / 网络 / 磁盘 / 电池
    func fastSnapshot() -> MetricsSnapshot {
        var next = MetricsSnapshot()
        next.cpu = cpu.sample()
        next.mem = memory.sample()
        next.battery = battery.sample()
        next.temp = temperature.sample(batteryFallback: next.battery.temperatureC)
        next.net = network.sample()
        next.disk = disk.sample()
        next.updatedAt = Date()
        return next
    }

    /// 3s 周期：全量进程表
    func processRows() -> [ProcessRow] {
        processes.sample()
    }

    /// 首帧与低频重扫：启动项
    func startupSnapshot() -> StartupSnapshot {
        startupCollector.scan()
    }

    func sensorDump() -> [String] {
        temperature.dumpSensors()
    }
}
