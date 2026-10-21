import CProc
import Darwin
import Foundation

/// 诊断探针：验证对 root 进程的各类读取途径是否可用。
enum ProcessProbe {

    static func taskInfo(pid: pid_t) -> Bool {
        var info = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.stride)
        return proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size) == size
    }

    static func rusage(pid: pid_t) -> Bool {
        var info = rusage_info_v4()
        let result: Int32 = withUnsafeMutablePointer(to: &info) { pointer in
            let raw = UnsafeMutableRawPointer(pointer)
            return proc_pid_rusage(pid, 4 /* RUSAGE_INFO_V4 */, raw.assumingMemoryBound(to: rusage_info_t?.self))
        }
        guard result == 0 else { return false }
        return info.ri_user_time > 0 || info.ri_system_time > 0
    }

    static func pctCpu(pid: pid_t) -> String {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else { return "N/A" }
        let raw = info.kp_proc.p_pctcpu
        let percent = Double(raw) / 2048.0 * 100.0
        return String(format: "raw=%u (%.1f%%)", raw, percent)
    }
}
