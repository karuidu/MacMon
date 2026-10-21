import Darwin
import Foundation

/// 内存采集：Mach `host_statistics64` + `vm.swapusage`。
///
/// 口径与 macOS 活动监视器一致（**不是** `vm_stat` 的队列口径）：
/// - 已使用 = internal + wired + compressed
/// - App 内存 = internal − purgeable
/// - 已缓存文件 = external
///
/// 早期用的是 `active + wired + compressed`，但 `active_count` 混入了大量
/// file-backed 文件缓存页，会把已用内存高估 2–3 GB（实测 12.3 GB vs 活动监视器 9.50 GB）。
/// 用截图的三个数反推可验证：internal 8.03 + wired 1.47 = 9.50 = 已使用；
/// 8.03 − purgeable 0.82 = 7.21 = App 内存；external = 11.39 = 已缓存文件。
final class MemoryCollector {

    func sample() -> MemMetrics {
        var metrics = MemMetrics()
        metrics.totalBytes = ProcessInfo.processInfo.physicalMemory

        // mach_host_self() 每次返回一个 port right，必须还回去，否则常驻会一直累积
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }

        var pageSize: vm_size_t = 0
        host_page_size(host, &pageSize)
        let page = UInt64(pageSize)

        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride
        )

        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics64(host, HOST_VM_INFO64, rebound, &count)
            }
        }

        if result == KERN_SUCCESS {
            let internalPages = UInt64(stats.internal_page_count)
            let externalPages = UInt64(stats.external_page_count)
            let purgeable    = UInt64(stats.purgeable_count)
            let wired        = UInt64(stats.wire_count)
            let compressed   = UInt64(stats.compressor_page_count)
            let free         = UInt64(stats.free_count)

            // 饱和减法：purgeable 理论上可能包含 file-backed 页，直接相减会下溢成天文数字
            let appPages = internalPages > purgeable ? internalPages - purgeable : 0

            metrics.appBytes       = appPages * page
            metrics.cachedBytes    = externalPages * page
            metrics.purgeableBytes = purgeable * page
            metrics.usedBytes      = (internalPages + wired + compressed) * page
            metrics.wiredBytes     = wired * page
            metrics.compressedBytes = compressed * page
            metrics.activeBytes    = UInt64(stats.active_count) * page   // 仅诊断用

            let used = metrics.usedBytes
            let cached = metrics.cachedBytes
            metrics.freeBytes = metrics.totalBytes > used + cached
                ? metrics.totalBytes - used - cached
                : 0
            metrics.availableBytes = metrics.totalBytes > used
                ? metrics.totalBytes - used
                : free * page
        }

        readSwap(into: &metrics)
        metrics.pressure = readPressure()
        return metrics
    }

    private func readSwap(into metrics: inout MemMetrics) {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.stride
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return }
        metrics.swapTotalBytes = usage.xsu_total
        metrics.swapUsedBytes = usage.xsu_used
    }

    private func readPressure() -> MemoryPressure {
        guard let raw = SysCtl.int32("kern.memorystatus_vm_pressure_level") else {
            return .normal
        }
        switch raw {
        case 4:  return .critical
        case 2:  return .warning
        default: return .normal
        }
    }
}
