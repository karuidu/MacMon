import AppKit
import SwiftUI

/// 自绘横向分页器。
///
/// 为什么不用 `ScrollView + scrollPosition(id:)`：在 macOS 14 上那个 API 只「跟随」滚动，
/// 不会因为绑定值变化而跳页——实测启动到第 4 页时页签高亮正确、内容仍停在第 1 页。
/// 这里用 index × 宽度直接算偏移量，跳页是确定性的；滑动由 DragGesture 与滚轮监听提供。
struct PagePager: View {
    @EnvironmentObject private var nav: NavigationModel

    /// 拖动过程中的实时偏移（未超过阈值会回弹）
    @State private var dragOffset: CGFloat = 0
    /// 滚轮累计位移，够一页才翻
    @State private var wheelAccum: CGFloat = 0
    @State private var wheelMonitor: Any?

    private let count = DashboardPage.allCases.count

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)

            HStack(spacing: 0) {
                ForEach(DashboardPage.allCases) { page in
                    host(page)
                        .frame(width: width, height: geo.size.height)
                }
            }
            .frame(width: width * CGFloat(count), alignment: .leading)
            .offset(x: -CGFloat(nav.page.rawValue) * width + dragOffset)
            .animation(.easeOut(duration: 0.26), value: nav.page)
            .contentShape(Rectangle())
            .gesture(dragGesture(width: width))
        }
        .clipped()
        .onAppear { startWheelMonitor() }
        .onDisappear { stopWheelMonitor() }
    }

    // MARK: - 拖动

    private func dragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 16)
            .onChanged { value in
                // 只接管明确的水平手势，纵向留给页面内的列表
                guard abs(value.translation.width) > abs(value.translation.height) * 1.5 else { return }
                var delta = value.translation.width
                if (nav.page.rawValue == 0 && delta > 0)
                    || (nav.page.rawValue == count - 1 && delta < 0) {
                    delta *= 0.28   // 到边界时加阻尼
                }
                dragOffset = delta
            }
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) * 1.5 else {
                    dragOffset = 0
                    return
                }
                // 用预测落点判断，轻扫也能翻页
                let projected = value.predictedEndTranslation.width
                let threshold = width * 0.22
                var target = nav.page.rawValue
                if projected < -threshold { target += 1 }
                else if projected > threshold { target -= 1 }

                withAnimation(.easeOut(duration: 0.26)) {
                    dragOffset = 0
                    nav.page = DashboardPage(rawValue: min(max(target, 0), count - 1)) ?? nav.page
                }
            }
    }

    // MARK: - 触控板横滑

    /// 用本地事件监听拿横向滚动量。不吞事件，所以页面内的纵向列表照常滚动。
    private func startWheelMonitor() {
        guard wheelMonitor == nil else { return }
        wheelMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            guard event.window === NSApp.keyWindow else { return event }

            let dx = event.scrollingDeltaX
            let dy = event.scrollingDeltaY
            guard abs(dx) > abs(dy) * 1.5, abs(dx) > 1 else {
                wheelAccum = 0
                return event
            }

            Task { @MainActor in handleWheel(dx) }
            return event
        }
    }

    private func stopWheelMonitor() {
        if let monitor = wheelMonitor {
            NSEvent.removeMonitor(monitor)
            wheelMonitor = nil
        }
    }

    @MainActor
    private func handleWheel(_ dx: CGFloat) {
        wheelAccum += dx
        // 触控板一次滑动会产生几十个事件，累计到阈值才翻一页
        guard abs(wheelAccum) > 52 else { return }
        let step = wheelAccum > 0 ? -1 : 1
        wheelAccum = 0

        let target = min(max(nav.page.rawValue + step, 0), count - 1)
        guard target != nav.page.rawValue else { return }
        withAnimation(.easeOut(duration: 0.26)) {
            nav.page = DashboardPage(rawValue: target) ?? nav.page
        }
    }

    // MARK: - 页面

    @ViewBuilder
    private func host(_ page: DashboardPage) -> some View {
        switch page {
        case .overview:    OverviewPage()
        case .performance: PerformancePage()
        case .processes:   ProcessPage()
        case .security:    SecurityPage()
        case .storage:     StoragePage()
        }
    }
}
