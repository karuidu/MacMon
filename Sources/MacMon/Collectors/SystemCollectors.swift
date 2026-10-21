import Darwin
import Foundation
import IOKit

// MARK: - 磁盘

final class DiskCollector {
    private var lastRead: UInt64?
    private var lastWrite: UInt64?
    private var lastTime: Date?

    func sample() -> DiskMetrics {
        var metrics = DiskMetrics()

        // 容量：取根卷
        let root = URL(fileURLWithPath: "/")
        if let values = try? root.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeLocalizedNameKey
        ]) {
            let total = UInt64(values.volumeTotalCapacity ?? 0)
            let free = UInt64(values.volumeAvailableCapacity ?? 0)
            metrics.totalBytes = total
            metrics.usedBytes = total > free ? total - free : 0
            if let name = values.volumeLocalizedName { metrics.volumeName = name }
        }

        // 吞吐：IORegistry 里 IOBlockStorageDriver 的累计字节数做差分
        let (read, write) = Self.cumulativeBytes()
        let now = Date()

        if let lastRead, let lastWrite, let lastTime {
            let dt = max(now.timeIntervalSince(lastTime), 0.001)
            metrics.readSec = read >= lastRead ? Double(read - lastRead) / dt : 0
            metrics.writeSec = write >= lastWrite ? Double(write - lastWrite) / dt : 0
        }

        lastRead = read
        lastWrite = write
        lastTime = now
        return metrics
    }

    static func cumulativeBytes() -> (UInt64, UInt64) {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IOBlockStorageDriver"),
            &iterator
        ) == KERN_SUCCESS else { return (0, 0) }

        defer { IOObjectRelease(iterator) }

        var totalRead: UInt64 = 0
        var totalWrite: UInt64 = 0

        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            guard let props = registryProperties(entry),
                  let stats = props["Statistics"] as? [String: Any] else { continue }
            totalRead += (stats["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0
            totalWrite += (stats["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0
        }
        return (totalRead, totalWrite)
    }
}

// MARK: - 网络

final class NetworkCollector {
    private var lastRx: UInt64?
    private var lastTx: UInt64?
    private var lastTime: Date?

    func sample() -> NetMetrics {
        var metrics = NetMetrics()
        guard let counters = Self.readInterface(countersFor: primaryInterface()) else {
            return metrics
        }

        metrics.iface = counters.name
        metrics.rxTotal = counters.rx
        metrics.txTotal = counters.tx

        let now = Date()
        if let lastRx, let lastTx, let lastTime {
            let dt = max(now.timeIntervalSince(lastTime), 0.001)
            metrics.rxSec = counters.rx >= lastRx ? Double(counters.rx - lastRx) / dt : 0
            metrics.txSec = counters.tx >= lastTx ? Double(counters.tx - lastTx) / dt : 0
        }
        lastRx = counters.rx
        lastTx = counters.tx
        lastTime = now
        return metrics
    }

    /// 默认路由所在接口；拿不到就退回 en0
    private func primaryInterface() -> String {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_DUMP, 0]
        var len = 0
        guard sysctl(&mib, 6, nil, &len, nil, 0) == 0, len > 0 else { return "en0" }
        var buffer = [UInt8](repeating: 0, count: len)
        guard sysctl(&mib, 6, &buffer, &len, nil, 0) == 0 else { return "en0" }

        var result = "en0"
        buffer.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var offset = 0
            while offset < len {
                let header = base.advanced(by: offset).assumingMemoryBound(to: rt_msghdr.self)
                let msgLen = Int(header.pointee.rtm_msglen)
                if msgLen <= 0 { break }

                if Int32(header.pointee.rtm_type) == RTM_GET,
                   header.pointee.rtm_flags & RTF_GATEWAY != 0,
                   header.pointee.rtm_index > 0 {
                    var nameBuffer = [CChar](repeating: 0, count: Int(IF_NAMESIZE) + 1)
                    if if_indextoname(UInt32(header.pointee.rtm_index), &nameBuffer) != nil {
                        let name = String(cString: nameBuffer)
                        if name.hasPrefix("en") { result = name }
                    }
                }
                offset += msgLen
            }
        }
        return result
    }

    private static func readInterface(countersFor name: String) -> (name: String, rx: UInt64, tx: UInt64)? {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var len = 0
        guard sysctl(&mib, 6, nil, &len, nil, 0) == 0, len > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: len)
        guard sysctl(&mib, 6, &buffer, &len, nil, 0) == 0 else { return nil }

        var found: (String, UInt64, UInt64)?
        buffer.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var offset = 0
            while offset < len {
                let header = base.advanced(by: offset).assumingMemoryBound(to: if_msghdr.self)
                let msgLen = Int(header.pointee.ifm_msglen)
                if msgLen <= 0 { break }

                if Int32(header.pointee.ifm_type) == RTM_IFINFO2 {
                    let header2 = base.advanced(by: offset).assumingMemoryBound(to: if_msghdr2.self)
                    let index = UInt32(header2.pointee.ifm_index)
                    var nameBuffer = [CChar](repeating: 0, count: Int(IF_NAMESIZE) + 1)
                    if if_indextoname(index, &nameBuffer) != nil {
                        let ifName = String(cString: nameBuffer)
                        if ifName == name {
                            found = (
                                ifName,
                                header2.pointee.ifm_data.ifi_ibytes,
                                header2.pointee.ifm_data.ifi_obytes
                            )
                        }
                    }
                }
                offset += msgLen
            }
        }
        guard let found else { return nil }
        return (found.0, found.1, found.2)
    }
}

// MARK: - 电池

final class BatteryCollector {

    func sample() -> BatteryMetrics {
        var metrics = BatteryMetrics()

        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("AppleSmartBattery")
        )
        guard service != 0 else { return metrics }
        defer { IOObjectRelease(service) }

        guard let props = registryProperties(service) else { return metrics }
        metrics.present = true

        let current = number(props["CurrentCapacity"])
        let maxCapacity = number(props["MaxCapacity"])
        let rawMax = number(props["AppleRawMaxCapacity"])
        let design = number(props["DesignCapacity"])

        if let current, let maxCapacity, maxCapacity > 0 {
            metrics.percent = Double(current) / Double(maxCapacity) * 100
        }
        if let rawMax, let design, design > 0 {
            metrics.healthPercent = Double(rawMax) / Double(design) * 100
        }

        metrics.cycleCount = Int(number(props["CycleCount"]) ?? 0)
        metrics.isCharging = (props["IsCharging"] as? Bool) ?? false
        metrics.acConnected = (props["ExternalConnected"] as? Bool) ?? false
        metrics.condition = props["Condition"] as? String

        // 电池温度单位是 1/100 ℃
        if let raw = number(props["Temperature"]), raw > 0 {
            metrics.temperatureC = Double(raw) / 100
        }
        if let remaining = number(props["TimeRemaining"]), remaining > 0 {
            metrics.timeRemainingMin = Int(remaining)
        }
        return metrics
    }

    private func number(_ value: Any?) -> Int64? {
        (value as? NSNumber)?.int64Value
    }
}

// MARK: - IORegistry 辅助

func registryProperties(_ entry: io_registry_entry_t) -> [String: Any]? {
    var unmanaged: Unmanaged<CFMutableDictionary>?
    let result = IORegistryEntryCreateCFProperties(entry, &unmanaged, kCFAllocatorDefault, 0)
    guard result == KERN_SUCCESS, let dict = unmanaged?.takeRetainedValue() else { return nil }
    return dict as NSDictionary as? [String: Any]
}
