import Foundation

/// 英文翻译表。键是界面上的中文原文，值是英文译文。
///
/// 约定：
/// - 纯文案直接用中文原文当键，例如 `"概览": "Overview"`。
/// - 含插值的文案在源码里统一写成 `%@` 占位，键也用 `%@`，例如
///   `"共 %@ 项": "%@ total"`。参数顺序由 `L.f` 保证，不依赖格式符位置。
/// - 少数文案原本交给 `String(format:)` 处理（`%.1f` 这种），译文必须保留
///   同样的格式符，否则运行时格式化会出错。
/// - 表里查不到就退回中文，因此新增文案哪怕忘了翻译也不会崩。
extension L {
    static let en: [String: String] = [
        // MARK: - 页签与通用
        "概览": "Overview",
        "性能": "Performance",
        "进程": "Processes",
        "安全": "Security",
        "存储网络": "Storage & Network",
        "页面": "Pages",
        "下一页": "Next Page",
        "上一页": "Previous Page",
        "取消": "Cancel",
        "退出": "Quit",
        "正在扫描…": "Scanning…",

        // MARK: - 菜单
        // 这些是 macOS 标准菜单项：标题由**系统语言**决定，App 内切语言不会变。
        // MenuLayout 会按 action（selector 不随语言变）把它们改成这里的译文。
        "编辑": "Edit",
        "显示": "View",
        "进入全屏": "Enter Full Screen",
        "关于 MacMon": "About MacMon",
        "隐藏 MacMon": "Hide MacMon",
        "隐藏其他": "Hide Others",
        "全部显示": "Show All",
        "退出 MacMon": "Quit MacMon",
        "剪切": "Cut",
        "拷贝": "Copy",
        "粘贴": "Paste",
        "删除": "Delete",
        "全选": "Select All",

        // MARK: - 页面副标题
        "所有关键指标一眼看完": "Every key metric at a glance",
        "处理器、温度与内存的实时细节": "CPU, temperature and memory in detail",
        "全量进程，按占用排序，可结束": "All processes, sorted by usage, quittable safely",
        "开机启动项与风险扫描": "Startup items and risk scanning",
        "网络吞吐、磁盘容量与电池健康": "Network throughput, disk capacity and battery health",

        // MARK: - 顶栏
        "主机": "Host",
        "已运行": "Uptime",
        "更新": "Updated",
        "预热中": "Warming up",
        "实时": "Live",

        // MARK: - 设备信息
        "设备": "Device",
        "型号": "Model",
        "芯片": "Chip",
        "核心": "Cores",
        "系统": "System",
        "处理器": "CPU",
        "内存": "Memory",
        "温度": "Temperature",
        "磁盘": "Disk",
        "网络": "Network",
        "电池": "Battery",
        "%@ 核 · P%@/E%@": "%@ cores · P%@/E%@",
        "%@ · %@ 核": "%@ · %@ cores",

        // MARK: - 处理器
        "总占用": "Total",
        "用户": "User",
        "负载": "Load",
        "每核占用": "Per-core",
        "性能核": "Performance",
        "能效核": "Efficiency",
        "负载走势": "Load history",
        "峰值 %.1f%%": "Peak %.1f%%",
        "用户 %.1f%% · 系统 %.1f%%": "User %.1f%% · System %.1f%%",

        // MARK: - 温度
        "温度走势": "Temperature history",
        "风扇": "Fan",
        "传感器": "Sensors",
        "待机": "Idle",
        "峰值 %@": "Peak %@",
        "%@ 路": "%@ channels",
        "HID 传感器 · %@ 路": "HID sensors · %@ channels",
        "SoC %@ · 电池 %@": "SoC %@ · Battery %@",
        "电池温度回退": "Battery temp fallback",
        "不可用": "Unavailable",

        // MARK: - 内存
        "压力 %@": "Pressure %@",
        "正常": "Normal",
        "偏高": "Elevated",
        "紧张": "Tight",
        "App 内存": "App Memory",
        "共 %@ · 缓存 %@ · 压力 %@": "Total %@ · Cached %@ · Pressure %@",
        "固定": "Wired",
        "压缩": "Compressed",
        "已缓存": "Cached",
        "空闲": "Free",
        "交换": "Swap",
        "未使用": "Unused",
        "占用走势": "Usage history",
        "峰值 %.0f%%": "Peak %.0f%%",
        "应用内存：所有进程实际占用的匿名页（栈、堆、对象），已扣掉可被系统随时回收的可清除内存。":
            "App Memory: anonymous pages (stacks, heaps, objects) actually held by processes, with purgeable memory — reclaimable by the system at any moment — already subtracted.",
        "文件缓存：从磁盘读过的文件内容留在内存里，随时可丢弃，紧张时会自动释放，不算真正占用。":
            "Cached Files: contents of files read from disk, kept around in memory. Always discardable and released automatically under pressure, so not real usage.",
        "固定内存（wired memory）就是活动监视器里的「联动内存」：已锁定在物理内存中，不可换出、不可压缩，主要由内核、驱动和 IO 缓冲占用。":
            "Wired memory is what Activity Monitor calls \"Wired\": locked in RAM, it cannot be paged out or compressed. Mostly kernel, drivers and I/O buffers.",
        "压缩内存：物理内存吃紧时，系统把不活跃的页压缩后存放，省出空间；解压要花一点 CPU。":
            "Compressed memory: under pressure the system compresses inactive pages to free up space. Decompressing costs a little CPU.",
        "交换空间：连压缩都放不下时写进磁盘的那部分。长期不为 0 说明物理内存已经不够用。":
            "Swap: whatever does not fit even after compression gets written to disk. Persistently non-zero means RAM is no longer enough.",

        // MARK: - 网络与磁盘
        "↓ 下行": "↓ Down",
        "↑ 上行": "↑ Up",
        "下行": "Down",
        "上行": "Up",
        "累计 ↓ %@": "Total ↓ %@",
        "峰值 %@/s": "Peak %@/s",
        "已用": "Used",
        "容量": "Capacity",
        "读取": "Read",
        "写入": "Write",
        "可用": "Available",
        "已用 %@": "%@ used",
        "总计 %@": "%@ total",
        "%.0f%% 已用": "%.0f%% used",

        // MARK: - 电池
        "充电中": "Charging",
        "放电中": "Discharging",
        "已接电源": "Plugged in",
        "使用电池": "On battery",
        "外接电源": "AC power",
        "电池供电": "Battery power",
        "健康度": "Health",
        "循环": "Cycles",
        "%@ 次": "%@",
        "状态": "Status",
        "未检测到电池": "No battery detected",

        // MARK: - 预警
        "预警": "Alerts",
        "无异常": "All clear",
        "%@ 条": "%@ items",
        "未触发预警": "No alerts triggered",
        "温度、内存、磁盘均在阈值内": "Temperature, memory and disk are all within thresholds",

        // MARK: - 告警文案（AppModel 生成）
        "温度过高": "Temperature critical",
        "温度偏高": "Temperature elevated",
        "CPU %.1f°C，已接近降频阈值": "CPU at %.1f°C, close to thermal throttling",
        "内存吃紧": "Memory pressure high",
        "已用 %.0f%%，可能触发交换": "%.0f%% used, swap may kick in",
        "磁盘空间不足": "Low disk space",
        "发现 %@ 个高风险启动项": "%@ high-risk startup items found",
        "发现 %@ 个高风险进程": "%@ high-risk processes found",
        "启动项": "Startup items",
        "启动项变更": "Startup changes",
        "发现 %@ 个启动项变更": "%@ startup item changes detected",
        "%@ 等": "%@ etc.",

        // MARK: - 进程页
        "Top 进程": "Top Processes",
        "应用": "App",
        "属主": "Owner",
        "%@ 个": "%@",
        "共 %@ 个": "%@ total",
        "进程列表": "Processes",
        "%@ 个 · 右键可结束": "%@ · right-click to quit",
        "按 CPU 排序": "Sorted by CPU",
        "搜索进程 / 应用 / 属主": "Search process / app / owner",
        "结束进程": "Quit Process",
        "结束进程（SIGTERM）": "Quit (SIGTERM)",
        "结束 %@（SIGTERM）": "Quit %@ (SIGTERM)",
        "强制结束（SIGKILL）": "Force Quit (SIGKILL)",
        "不可结束": "Not quittable",
        "PID %@ · 属于「%@」\n强制结束可能导致未保存的数据丢失。":
            "PID %@ · owned by \"%@\"\nForcing it to quit may lose unsaved data.",
        "系统保留进程": "Reserved system process",
        "不能结束监控自身": "Cannot quit the monitor itself",
        "系统关键进程": "Critical system process",
        "属于用户「%@」，无权限": "Owned by \"%@\", no permission",
        "内核线程，不可结束": "Kernel thread, cannot be quit",

        // MARK: - 结束结果（KillService）
        "PID 非法": "Invalid PID",
        "不能结束监控服务自身": "Cannot quit the monitor itself",
        "已强制结束（SIGKILL）": "Force quit (SIGKILL)",
        "已发送结束信号（SIGTERM）": "Quit signal sent (SIGTERM)",
        "权限不足，该进程属于其他用户": "Permission denied: the process belongs to another user",
        "进程不存在或已退出": "Process is gone or already exited",
        "失败：%@": "Failed: %@",

        // MARK: - 风险等级
        "无": "None",
        "低": "Low",
        "中": "Medium",
        "高": "High",
        "严重": "Critical",
        "风险": "Risk",
        "中高风险": "Medium+ risk",
        "可执行文件": "Executable",

        // MARK: - 签名类型
        "Apple 签名": "Apple signed",
        "临时签名": "Ad-hoc",
        "未签名": "Unsigned",
        "未知": "Unknown",

        // MARK: - 风险判定依据
        "可执行文件位于可疑目录": "Executable lives in a suspicious directory",
        "可执行文件位于可疑目录：%@": "Executable lives in a suspicious directory: %@",
        "进程名伪装成系统组件，但不在系统目录":
            "Name mimics a system component but the binary sits outside system directories",
        "仅临时签名（ad-hoc）": "Ad-hoc signed only",
        "仅临时签名（ad-hoc），未通过开发者验证": "Ad-hoc signed only, not signed by a developer",
        "未签名或签名失效": "Unsigned or invalid signature",
        "未签名或签名已失效": "Unsigned or signature no longer valid",
        "指向的可执行文件不存在（卸载残留）": "Target executable is missing (leftover from an uninstall)",
        "未声明 Program / ProgramArguments": "No Program / ProgramArguments declared",
        "开机自启且被结束后自动重启，路径不在标准安装位置":
            "Starts at boot and restarts itself after being quit, from a non-standard location",
        "在登录窗口（尚未登录时）即加载": "Loads at the login window, before anyone signs in",
        "以 root 权限常驻的系统级守护进程": "System-level daemon running as root",

        // MARK: - 启动项页
        "开机启动项": "Startup items",
        "LaunchAgents / LaunchDaemons · 按风险排序": "LaunchAgents / LaunchDaemons · ranked by risk",
        "用户级": "User",
        "系统级": "System",
        "未发现可疑进程": "No suspicious processes",
        "高风险进程": "High-risk processes",
        "构成": "Breakdown",
        "共 %@ 项": "%@ total",
        "%@ 项 · 风险 %@": "%@ items · risk %@",
        "名称 / 类型": "Name / Type",
        "判定依据": "Reasons",

        // MARK: - 启动项类型
        "用户 LaunchAgent": "User LaunchAgent",
        "全局 LaunchAgent": "Global LaunchAgent",
        "系统 LaunchDaemon": "System LaunchDaemon",
        "用户 Agent": "User Agent",
        "全局 Agent": "Global Agent",
        "系统 Daemon": "System Daemon",

        // MARK: - 启动项标签
        "开机": "Boot",
        "保活": "KeepAlive",
        "登录窗": "Login",
        "开机自启": "Runs at load",
        "保活重启": "Keep-alive",
        "登录前加载": "At login window",
        "文件缺失": "File missing",
        "无 Program": "No Program",
        "⚠ 文件不存在": "⚠ File missing",

        // MARK: - 启动项变更
        "新增": "New",
        "移除": "Removed",
        "修改": "Changed",
        "新增启动项 %@": "New startup item %@",
        "移除启动项 %@": "Startup item removed %@",
        "修改启动项 %@": "Startup item changed %@",
        "最近变更": "Recent changes",
        "近期变更": "Recent changes",
        "监听中。新增、修改或删除 plist 会在这里实时出现。":
            "Watching. Added, changed or deleted plists appear here in real time.",
        "刚刚": "just now",
        "%@ 分钟前": "%@ min ago",
        "%@ 小时前": "%@ h ago",
        "%@ 天前": "%@ d ago",

        // MARK: - 通知
        "系统通知": "Notifications",
        "系统通知·系统已关闭": "Notifications · off in System Settings",
        "系统通知（需 .app 运行）": "Notifications (requires .app)",
        "启动项发生变化时弹系统通知（应用内告警始终开启）":
            "Send a system notification when startup items change (in-app alerts stay on)",
        "系统设置里已关闭本 App 的通知，点开关会跳到系统设置":
            "Notifications are disabled in System Settings; the switch takes you there",

        // MARK: - 菜单栏
        "打开大屏": "Open Dashboard",
        "隐藏大屏": "Hide Dashboard",
        "隐藏主窗口，采集继续在后台跑": "Hide the window; collection keeps running in the background",
        "把主窗口带到最前面": "Bring the main window to the front",

        // MARK: - 运行时长
        "%@ 天 %@ 小时": "%@d %@h",
        "%@ 小时 %@ 分": "%@h %@m",
        "%@ 分": "%@m"
    ]
}
