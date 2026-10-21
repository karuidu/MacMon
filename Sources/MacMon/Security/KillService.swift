import Darwin
import Foundation

/// 结束进程：唯一一处真正会改变系统状态的操作，因此规则收得很紧。
enum KillService {

    struct Outcome {
        let success: Bool
        let message: String
    }

    /// 二次确认后调用；`force` 为真时用 SIGKILL
    static func terminate(pid: Int32, force: Bool) -> Outcome {
        guard pid > 1 else {
            return Outcome(success: false, message: L.t("PID 非法"))
        }
        guard pid != ProcessInfo.processInfo.processIdentifier else {
            return Outcome(success: false, message: L.t("不能结束监控服务自身"))
        }

        let signal = force ? SIGKILL : SIGTERM
        let result = kill(pid, signal)

        if result == 0 {
            return Outcome(
                success: true,
                message: force ? L.t("已强制结束（SIGKILL）") : L.t("已发送结束信号（SIGTERM）")
            )
        }

        switch errno {
        case EPERM:
            return Outcome(success: false, message: L.t("权限不足，该进程属于其他用户"))
        case ESRCH:
            return Outcome(success: false, message: L.t("进程不存在或已退出"))
        default:
            return Outcome(success: false, message: L.f("失败：%@", String(cString: strerror(errno))))
        }
    }
}
