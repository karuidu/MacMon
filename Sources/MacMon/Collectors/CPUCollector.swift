import Darwin
import Foundation

/// CPU 采集：直接走 Mach `host_processor_info`，不经任何 shell。
///
/// 与 Node 版的 `systeminformation` 相比，这里能稳定拿到**每核** tick，
/// 且 Apple Silicon 上 P/E 核分组来自 `hw.perflevel*`，不靠猜。
final class CPUCollector {
    /// 每个核上一次的累计 tick：[user, system, idle, nice]
    private var previous: [[UInt32]] = []

    /// 最近一次采样结果，供 UI 读取静态信息（型号、核数）而无需再采样
    private(set) var metrics = CPUMetrics()

    private let perfCores: Int
    private let effCores: Int
    private let brand: String

    init() {
        let p = SysCtl.int("hw.perflevel0.logicalcpu") ?? 0
        let e = SysCtl.int("hw.perflevel1.logicalcpu") ?? 0
        perfCores = p
        effCores = e
        brand = SysCtl.string("machdep.cpu.brand_string") ?? "Apple Silicon"

        metrics.brand = brand
        metrics.perfCores = p
        metrics.effCores = e
        metrics.cores = p + e
    }

    var clusterLayout: (perf: Int, eff: Int) { (perfCores, effCores) }

    func sample() -> CPUMetrics {
        metrics.brand = brand
        metrics.perfCores = perfCores
        metrics.effCores = effCores
        metrics.loadAvg = Fmt.loadAverage()

        guard let ticks = readTicks(), !ticks.isEmpty else {
            return metrics
        }

        defer { previous = ticks }
        let coreTotal = ticks.count
        metrics.cores = coreTotal

        // 首次采样没有基线，先全部报 0，等下一轮才是真实值
        guard previous.count == ticks.count else {
            metrics.perCore = (0..<coreTotal).map { i in
                CoreLoad(id: i, index: i, load: 0, cluster: cluster(at: i))
            }
            return metrics
        }

        var totalDelta: Double = 0
        var idleDelta: Double = 0
        var userDelta: Double = 0
        var systemDelta: Double = 0
        var cores: [CoreLoad] = []
        cores.reserveCapacity(coreTotal)

        for i in 0..<coreTotal {
            let now = ticks[i]
            let prev = previous[i]
            let dUser   = Double(now[0] &- prev[0])
            let dSystem = Double(now[1] &- prev[1])
            let dIdle   = Double(now[2] &- prev[2])
            let dNice   = Double(now[3] &- prev[3])

            let dTotal = dUser + dSystem + dIdle + dNice
            let load = dTotal > 0 ? (dUser + dSystem + dNice) / dTotal * 100 : 0

            totalDelta += dTotal
            idleDelta += dIdle
            userDelta += dUser + dNice
            systemDelta += dSystem

            cores.append(CoreLoad(id: i, index: i, load: load, cluster: cluster(at: i)))
        }

        metrics.perCore = cores
        if totalDelta > 0 {
            metrics.total = (totalDelta - idleDelta) / totalDelta * 100
            metrics.idle = idleDelta / totalDelta * 100
            metrics.user = userDelta / totalDelta * 100
            metrics.system = systemDelta / totalDelta * 100
        }
        return metrics
    }    /// Apple Silicon 的 `host_processor_info` 按 **能效核在前、性能核在后** 排列。
    /// 与 Node 版用 `yes` 压测（index 4–7 打满）的结论一致。
    private func cluster(at index: Int) -> CoreCluster {
        if effCores > 0, index < effCores { return .efficiency }
        return .performance
    }

    private func readTicks() -> [[UInt32]]? {
        var cpuInfo: processor_info_array_t?
        var numCpuInfo: mach_msg_type_number_t = 0
        var numCpus: natural_t = 0

        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &numCpus,
            &cpuInfo,
            &numCpuInfo
        )

        guard result == KERN_SUCCESS, let info = cpuInfo else { return nil }
        defer {
            let size = vm_size_t(numCpuInfo) * vm_size_t(MemoryLayout<integer_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: info)), size)
        }

        let stride = Int(CPU_STATE_MAX)
        var ticks: [[UInt32]] = []
        ticks.reserveCapacity(Int(numCpus))

        for core in 0..<Int(numCpus) {
            let base = core * stride
            ticks.append([
                UInt32(bitPattern: info[base + Int(CPU_STATE_USER)]),
                UInt32(bitPattern: info[base + Int(CPU_STATE_SYSTEM)]),
                UInt32(bitPattern: info[base + Int(CPU_STATE_IDLE)]),
                UInt32(bitPattern: info[base + Int(CPU_STATE_NICE)])
            ])
        }
        return ticks
    }
}
