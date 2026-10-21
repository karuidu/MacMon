import CoreServices
import Foundation

/// 监听 LaunchAgents / LaunchDaemons 三个目录的文件变化。
///
/// **为什么用 FSEvents 而不是 `DispatchSource`（vnode）**：
/// vnode 监听目录时，目录一旦被删除或整体替换，`source` 会自动 cancel、底层 fd 失效，
/// 必须在 cancel handler 里重新 open + 重挂，而且回调里拿不到是哪个文件变了。
/// FSEvents 在目录被替换时只会报一个 `RootChanged`，重扫一遍即可，
/// 完全不需要管理 fd 生命周期；一条流还能同时看三个目录。
///
/// 保留 60s 轮询做兜底：队列积压、睡眠唤醒、流创建时路径尚不存在等情况下 FSEvents 会漏事件。
final class StartupWatcher: @unchecked Sendable {

    /// 防抖：FSEvents 自身的 latency + 尾部合并。
    private let latency: CFTimeInterval = 0.4
    private let debounce: TimeInterval = 1.0
    /// 上限：持续拷贝文件时，尾部防抖会被无限推迟，必须有个截止时间
    private let maxDelay: TimeInterval = 3.0

    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "com.macmon.startup-watch", qos: .utility)
    private var pending: DispatchWorkItem?
    private var firstPendingAt: Date?
    private var lastRestart = Date.distantPast

    private let paths: [String]
    private let handler: () -> Void

    /// - Parameter handler: 在**监听队列**上回调，不是主线程。调用方自己切 `@MainActor`。
    init(paths: [String], handler: @escaping () -> Void) {
        self.paths = paths
        self.handler = handler
    }

    // MARK: - 生命周期

    func start() {
        queue.async { [weak self] in self?.buildStream() }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.pending?.cancel()
            self.pending = nil
            self.firstPendingAt = nil
            self.teardown()
        }
    }

    private func buildStream() {
        teardown()

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let flags = UInt32(
            kFSEventStreamCreateFlagUseCFTypes
            | kFSEventStreamCreateFlagFileEvents
            | kFSEventStreamCreateFlagWatchRoot
        )

        let created = FSEventStreamCreate(
            kCFAllocatorDefault,
            { _, info, count, eventPaths, eventFlags, _ in
                guard let info else { return }
                let watcher = Unmanaged<StartupWatcher>.fromOpaque(info).takeUnretainedValue()
                watcher.handleCallback(count: count, paths: eventPaths, flags: eventFlags)
            },
            &context,
            paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            flags
        )

        guard let created else { return }
        FSEventStreamSetDispatchQueue(created, queue)
        guard FSEventStreamStart(created) else {
            FSEventStreamInvalidate(created)
            FSEventStreamRelease(created)
            return
        }
        stream = created
    }

    private func teardown() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    // MARK: - 事件处理

    private func handleCallback(
        count: Int,
        paths: UnsafeMutableRawPointer,
        flags: UnsafePointer<FSEventStreamEventFlags>
    ) {
        guard count > 0 else { return }

        // UseCFTypes 打开后，eventPaths 是 CFArrayRef（CFString 数组）
        let list = Unmanaged<CFArray>.fromOpaque(paths).takeUnretainedValue() as? [String] ?? []

        let urgentFlag = FSEventStreamEventFlags(
            kFSEventStreamEventFlagMustScanSubDirs
            | kFSEventStreamEventFlagUserDropped
            | kFSEventStreamEventFlagKernelDropped
            | kFSEventStreamEventFlagEventIdsWrapped
        )
        let rootFlag = FSEventStreamEventFlags(kFSEventStreamEventFlagRootChanged)

        var urgent = false
        var rootChanged = false

        for index in 0..<count {
            let f = flags[index]
            if f & urgentFlag != 0 { urgent = true }
            if f & rootFlag != 0 { rootChanged = true }
        }

        // 这里是**目录路径**级别的通知（RootChanged 只给目录本身），
        // 所以不要按 .plist 后缀过滤，否则整条事件会被丢掉。
        _ = list

        if rootChanged {
            // 目录被删除/替换：流对旧 inode 的监听已经失效，重扫 + 重建
            rebuildIfNeeded()
        }

        if urgent || rootChanged {
            fireNow()
        } else {
            schedule()
        }
    }

    /// 重建流，但 5s 内最多一次——`mv` 整个目录会产生一批 RootChanged，
    /// 每个都重建会把事件循环刷爆。
    private func rebuildIfNeeded() {
        let now = Date()
        guard now.timeIntervalSince(lastRestart) > 5 else { return }
        lastRestart = now
        queue.asyncAfter(deadline: .now() + 1.0) { [weak self] in self?.buildStream() }
    }

    private func schedule() {
        if let first = firstPendingAt, Date().timeIntervalSince(first) >= maxDelay {
            fireNow()
            return
        }
        pending?.cancel()
        if firstPendingAt == nil { firstPendingAt = Date() }

        let item = DispatchWorkItem { [weak self] in self?.fireNow() }
        pending = item
        queue.asyncAfter(deadline: .now() + debounce, execute: item)
    }

    private func fireNow() {
        pending?.cancel()
        pending = nil
        firstPendingAt = nil
        handler()
    }
}
