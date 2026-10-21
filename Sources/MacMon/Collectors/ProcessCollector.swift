import CProc
import Darwin
import Foundation

/// 进程采集：`sysctl(KERN_PROC_ALL)` 拿全量进程表，再用 `libproc` 补充细节。
///
/// 为什么是两条路径：
/// · `sysctl` 的 `kinfo_proc` 由内核维护，**任何用户都能读全部进程**（含 root 的
///   WindowServer），并且自带 `p_pctcpu`，口径与 `ps` 的 `%CPU` 完全一致；
/// · `proc_pidinfo` 能给 RSS / 线程数，但只能读到自己有权限的进程。
/// 两者合并，既保证 700+ 个进程一个不漏，又尽量把内存填满。
final class ProcessCollector {

    private var previousCPU: [pid_t: UInt64] = [:]
    private var previousTime: Date?

    /// 每核百分比（100% = 占满一个核），与 `ps` 的 `pcpu` 一致
    func sample() -> [ProcessRow] {
        let entries = readKernelProcesses()
        guard !entries.isEmpty else { return [] }

        let now = Date()
        let elapsed = previousTime.map { max(now.timeIntervalSince($0), 0.001) } ?? 0
        var nextCPU: [pid_t: UInt64] = [:]
        nextCPU.reserveCapacity(entries.count)

        var rows: [ProcessRow] = []
        rows.reserveCapacity(entries.count)

        for entry in entries {
            var row = ProcessRow(
                pid: entry.pid,
                ppid: entry.ppid,
                name: entry.name,
                path: "",
                user: UserNames.name(for: entry.uid),
                cpu: entry.fallbackCPU,
                memPercent: 0,
                memRssBytes: 0,
                state: entry.state,
                threadCount: 0
            )

            // 用累计 CPU 时间差分，能得到瞬时的每核占比；
            // 读不到 taskinfo 的进程（多为 root 的内核态进程）保留内核给的衰减值。
            if let detail = readDetail(pid: entry.pid) {
                let total = detail.userNanos &+ detail.systemNanos
                nextCPU[entry.pid] = total
                if elapsed > 0, let previous = previousCPU[entry.pid], total >= previous {
                    let delta = Double(total - previous)
                    row.cpu = (delta / (elapsed * 1_000_000_000) * 100 * 10).rounded() / 10
                }
                row.memRssBytes = detail.rss
                row.threadCount = detail.threads
                row.path = detail.path
                if !detail.path.isEmpty {
                    let base = (detail.path as NSString).lastPathComponent
                    if !base.isEmpty { row.name = base }
                }
            }
            rows.append(row)
        }

        previousCPU = nextCPU
        previousTime = now
        return rows
    }

    // MARK: - 内核进程表

    private struct KernelEntry {
        let pid: pid_t
        let ppid: pid_t
        let uid: uid_t
        /// 内核 `p_pctcpu` 衰减值；新版 macOS 常常为 0，仅作兜底
        let fallbackCPU: Double
        let state: String
        let name: String
    }

    private func readKernelProcesses() -> [KernelEntry] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size = 0
        guard sysctl(&mib, 4, nil, &size, nil, 0) == 0, size > 0 else { return [] }

        // 进程数在两次调用之间可能变化，留 20% 余量并允许重试
        for _ in 0..<3 {
            let capacity = max(size / MemoryLayout<kinfo_proc>.stride, 1) + 32
            var buffer = [kinfo_proc](repeating: kinfo_proc(), count: capacity)
            var actualSize = capacity * MemoryLayout<kinfo_proc>.stride

            let result = buffer.withUnsafeMutableBytes { raw -> Int32 in
                guard let base = raw.baseAddress else { return -1 }
                return sysctl(&mib, 4, base, &actualSize, nil, 0)
            }
            guard result == 0 else { continue }

            let count = actualSize / MemoryLayout<kinfo_proc>.stride
            var entries: [KernelEntry] = []
            entries.reserveCapacity(count)

            for index in 0..<count {
                let info = buffer[index]
                let pid = info.kp_proc.p_pid
                guard pid > 0 else { continue }

                // p_pctcpu 是内核维护的定点数（FSCALE = 2048）
                let cpu = Double(info.kp_proc.p_pctcpu) / 2048.0 * 100.0

                entries.append(KernelEntry(
                    pid: pid,
                    ppid: info.kp_eproc.e_ppid,
                    uid: info.kp_eproc.e_ucred.cr_uid,
                    fallbackCPU: (cpu * 10).rounded() / 10,
                    state: Self.stateLabel(info.kp_proc.p_stat),
                    name: Self.commName(info.kp_proc.p_comm)
                ))
            }
            if !entries.isEmpty { return entries }
        }
        return []
    }

    // MARK: - 细节补充

    private struct Detail {
        let path: String
        let rss: UInt64
        let threads: Int
        let userNanos: UInt64
        let systemNanos: UInt64
    }

    private func readDetail(pid: pid_t) -> Detail? {
        var taskInfo = proc_taskinfo()
        let taskSize = Int32(MemoryLayout<proc_taskinfo>.stride)
        guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &taskInfo, taskSize) == taskSize else {
            return nil
        }
        return Detail(
            path: Self.executablePath(pid: pid),
            rss: taskInfo.pti_resident_size,
            threads: Int(taskInfo.pti_threadnum),
            userNanos: taskInfo.pti_total_user,
            systemNanos: taskInfo.pti_total_system
        )
    }

    static func executablePath(pid: pid_t) -> String {
        // PROC_PIDPATHINFO_MAXSIZE 是 libproc.h 里的简单宏（4 * MAXPATHLEN = 4096）
        let maxSize = 4 * 1024
        var buffer = [CChar](repeating: 0, count: maxSize)
        let length = buffer.withUnsafeMutableBufferPointer { pointer -> Int32 in
            guard let base = pointer.baseAddress else { return 0 }
            return proc_pidpath(pid, base, UInt32(maxSize))
        }
        guard length > 0 else { return "" }
        return String(cString: buffer)
    }

    /// `p_comm` 是 `char[MAXCOMLEN + 1]`，即 17 个字节
    private static func commName(_ tuple: (CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
                                          CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
                                          CChar)) -> String {
        var value = tuple
        return withUnsafePointer(to: &value) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: 17) { charPointer in
                String(cString: charPointer)
            }
        }
    }

    private static func stateLabel(_ status: Int8) -> String {
        switch status {
        case 1: return "I"   // SIDL
        case 2: return "R"   // SRUN
        case 3: return "S"   // SSLEEP
        case 4: return "T"   // SSTOP
        case 5: return "Z"   // SZOMB
        default: return "?"
        }
    }
}
