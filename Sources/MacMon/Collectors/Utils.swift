import Darwin
import Foundation

// MARK: - sysctl 工具

enum SysCtl {
    /// 读一个 Int32 类型的 sysctl 值
    static func int32(_ name: String) -> Int32? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return value
    }

    static func int(_ name: String) -> Int? {
        int32(name).map(Int.init)
    }

    /// 读一个 Int64 类型的 sysctl 值
    static func int64(_ name: String) -> Int64? {
        var value: Int64 = 0
        var size = MemoryLayout<Int64>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return value
    }

    /// 读字符串类型的 sysctl 值
    static func string(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size + 1)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }
}

// MARK: - 时间与格式化

enum Fmt {
    static func bytes(_ value: UInt64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var v = Double(value)
        var idx = 0
        while v >= 1024, idx < units.count - 1 {
            v /= 1024
            idx += 1
        }
        return idx == 0
            ? String(format: "%.0f %@", v, units[idx])
            : String(format: "%.1f %@", v, units[idx])
    }

    static func gb(_ value: UInt64) -> String {
        String(format: "%.1f GB", Double(value) / 1_073_741_824)
    }

    static func rate(_ bytesPerSec: Double) -> String {
        if bytesPerSec < 1024 { return String(format: "%.0f B/s", bytesPerSec) }
        if bytesPerSec < 1024 * 1024 { return String(format: "%.1f KB/s", bytesPerSec / 1024) }
        return String(format: "%.1f MB/s", bytesPerSec / 1_048_576)
    }

    static func percent(_ value: Double, digits: Int = 0) -> String {
        String(format: "%.\(digits)f%%", value)
    }

    static func temp(_ value: Double?) -> String {
        guard let value, value > 0, value < 130 else { return "—" }
        return String(format: "%.1f°C", value)
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let d = total / 86400
        let h = (total % 86400) / 3600
        let m = (total % 3600) / 60
        if d > 0 { return L.f("%@ 天 %@ 小时", d, h) }
        if h > 0 { return L.f("%@ 小时 %@ 分", h, m) }
        return L.f("%@ 分", m)
    }

    static func loadAverage() -> (Double, Double, Double) {
        var loads = [Double](repeating: 0, count: 3)
        guard getloadavg(&loads, 3) > 0 else { return (0, 0, 0) }
        return (loads[0], loads[1], loads[2])
    }
}

// MARK: - 用户名解析

enum UserNames {
    private static var cache: [uid_t: String] = [:]
    private static let lock = NSLock()

    static func name(for uid: uid_t) -> String {
        lock.lock()
        defer { lock.unlock() }
        if let hit = cache[uid] { return hit }

        guard let pw = getpwuid(uid), let raw = pw.pointee.pw_name else {
            let fallback = "\(uid)"
            cache[uid] = fallback
            return fallback
        }
        let name = String(cString: raw)
        cache[uid] = name
        return name
    }
}
