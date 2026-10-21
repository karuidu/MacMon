import SwiftUI

// MARK: - 环形仪表

struct RingGauge: View {
    var value: Double            // 0...100
    var color: Color = Theme.blue
    var lineWidth: CGFloat = 7
    var caption: String? = nil
    var subcaption: String? = nil

    private var clamped: Double { min(max(value, 0), 100) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.surface2, lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: clamped / 100)
                .stroke(
                    AngularGradient(
                        colors: [color.opacity(0.75), color],
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360)
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.35), value: clamped)

            VStack(spacing: 2) {
                if let caption {
                    Text(caption)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.text)
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                if let subcaption {
                    // 环形内径很窄，英文（Plugged in / Charging）比中文长得多：
                    // 不限制行数会折成两行把大数字挤歪，必须单行 + 自动缩小
                    Text(subcaption)
                        .font(.system(size: 8.5))
                        .foregroundStyle(Theme.dim)
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                        .padding(.horizontal, 2)
                }
            }
        }
    }
}

// MARK: - 迷你折线

struct Sparkline: View {
    var values: [Double]
    var maxValue: Double
    /// 非零基线。温度这类「永远在 30–70℃ 之间」的指标需要它，
    /// 否则曲线会被 0–110 的量程死死压在底部。
    var minValue: Double = 0
    var color: Color = Theme.blue
    var showArea: Bool = true
    /// 极淡的水平网格。数据平稳时折线接近直线，没有网格会显得「图没画出来」。
    var showGrid: Bool = true

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let lower = minValue
            let upper = max(maxValue, lower + 0.0001)
            let points = points(in: size, lower: lower, upper: upper)

            ZStack {
                // 高度不足时不要画面积填充：50pt 高的图里，填充会糊成一根实心色条，
                // 看着像「图坏了」而不是「数据平稳」
                if showArea, points.count > 1, size.height > 44 {
                    areaPath(points, in: size)
                        .fill(
                            LinearGradient(
                                colors: [color.opacity(0.34), color.opacity(0.04)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
                // 网格画在面积填充之上，否则被填充色洗掉、只剩填充区外可见
                if showGrid {
                    Path { path in
                        for index in 1..<4 {
                            let y = size.height * CGFloat(index) / 4
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: size.width, y: y))
                        }
                    }
                    .stroke(Theme.line.opacity(0.85), lineWidth: 0.5)
                }
                if points.count > 1 {
                    smoothPath(points)
                        .stroke(color, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                }
            }
        }
    }

    private func points(in size: CGSize, lower: Double, upper: Double) -> [CGPoint] {
        guard values.count > 1 else { return [] }
        let span = max(upper - lower, 0.0001)
        let stepX = size.width / CGFloat(values.count - 1)
        return values.enumerated().map { index, value in
            let ratio = min(max((value - lower) / span, 0), 1)
            return CGPoint(
                x: CGFloat(index) * stepX,
                y: size.height - CGFloat(ratio) * size.height
            )
        }
    }

    private func smoothPath(_ points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)

        for index in 1..<points.count {
            let previous = points[index - 1]
            let current = points[index]
            let mid = CGPoint(x: (previous.x + current.x) / 2, y: (previous.y + current.y) / 2)
            path.addQuadCurve(to: mid, control: previous)
        }
        if let last = points.last {
            path.addLine(to: last)
        }
        return path
    }

    private func areaPath(_ points: [CGPoint], in size: CGSize) -> Path {
        var path = smoothPath(points)
        path.addLine(to: CGPoint(x: points[points.count - 1].x, y: size.height))
        path.addLine(to: CGPoint(x: points[0].x, y: size.height))
        path.closeSubpath()
        return path
    }
}

// MARK: - 温度量程

/// 温度折线的自适应量程。
///
/// 量程固定 0–110℃ 时，38℃ 的曲线只占 35% 高度、视觉上贴着卡片底边。
/// 但如果直接取「历史 min…max」，历史峰值会把区间撑得很宽（47℃ 的旧峰值 + 此刻 37℃），
/// 曲线仍会被压到下沿。所以窗口**以当前值为中心**、跨度取近期波动（至少 8℃），
/// 超出窗口的历史点被裁到边界——温度看的是短时趋势，这样读起来最稳。
enum TempScale {
    /// 与温度卡环形仪表的绝对刻度保持一致，只作上限兜底
    static let hardMax: Double = 110
    /// 最小跨度，避免平稳时把 0.5℃ 的噪声放大成锯齿
    static let minSpan: Double = 8

    static func range(for history: [Double], current: Double? = nil) -> (lower: Double, upper: Double) {
        // 剔除 0 占位与异常值；`primaryC` 读不到时历史里可能是 0
        var values = history.filter { $0.isFinite && $0 > 1 && $0 < 130 }
        if let current, current.isFinite, current > 1, current < 130 {
            values.append(current)
        }
        guard let cur = current ?? values.last,
              cur.isFinite, cur > 1, cur < 130 else { return (30, 40) }

        let lo = values.min() ?? cur
        let hi = values.max() ?? cur
        let span = max(hi - lo + 2, minSpan)

        var lower = floor((cur - span * 0.5) / 5) * 5
        var upper = ceil((cur + span * 0.5) / 5) * 5
        lower = min(max(lower, 10), 95)
        if upper - lower < minSpan { upper = lower + minSpan }
        upper = min(upper, hardMax)
        if upper - lower < minSpan { lower = max(upper - minSpan, 5) }
        return (lower, upper)
    }

    static func label(_ range: (lower: Double, upper: Double)) -> String {
        String(format: "%.0f–%.0f℃", range.lower, range.upper)
    }
}

// MARK: - 每核柱状

struct CoreBars: View {
    var cores: [CoreLoad]

    var body: some View {
        GeometryReader { geo in
            let count = max(cores.count, 1)
            let spacing: CGFloat = 3
            let barWidth = (geo.size.width - spacing * CGFloat(count - 1)) / CGFloat(count)

            HStack(alignment: .bottom, spacing: spacing) {
                ForEach(cores) { core in
                    VStack(spacing: 3) {
                        Spacer(minLength: 0)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(
                                core.cluster == .performance
                                    ? Theme.blue
                                    : Theme.green
                            )
                            .opacity(core.load > 0.5 ? 0.35 + 0.65 * min(core.load / 100, 1) : 0.22)
                            .frame(width: barWidth, height: max(2, geo.size.height * min(core.load / 100, 1)))
                            .animation(.easeOut(duration: 0.3), value: core.load)
                        Text("\(core.cluster.rawValue)\(core.index)")
                            .font(.system(size: 7.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(core.cluster == .performance ? Theme.blue.opacity(0.8) : Theme.green.opacity(0.8))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                    .frame(maxWidth: barWidth)
                }
            }
            .frame(height: geo.size.height)
        }
    }
}

// MARK: - 水平堆叠条

struct StackBar: View {
    struct Segment: Identifiable {
        var label: String
        var value: Double
        var color: Color
        // 每秒重建数组，用 UUID 会让 ForEach 每秒全部重算；label 才是稳定身份
        var id: String { label }
    }

    var segments: [Segment]
    var height: CGFloat = 8

    /// 过滤掉 0 值段：它们不占宽度，却仍会吃掉一段间距，条形上会出现莫名的豁口
    private var visible: [Segment] {
        segments.filter { $0.value > 0 }
    }

    private var total: Double {
        max(visible.reduce(0) { $0 + $1.value }, 0.0001)
    }

    var body: some View {
        GeometryReader { geo in
            // 按可用宽度整体分配，而不是每段各自减去间距——后者会累计少画 2×(n−1) 点，
            // 5 段时偏差接近 10pt，短段误差尤其明显。
            let gap: CGFloat = visible.count > 1 ? 2 : 0
            let usable = max(geo.size.width - gap * CGFloat(max(visible.count - 1, 0)), 1)
            HStack(spacing: gap) {
                ForEach(visible) { segment in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(segment.color)
                        .frame(width: usable * CGFloat(segment.value / total))
                }
            }
        }
        .frame(height: height)
        .background(
            RoundedRectangle(cornerRadius: 2).fill(Theme.surface2)
        )
        .clipShape(RoundedRectangle(cornerRadius: 2))
    }
}

// MARK: - 状态点

struct StatusDot: View {
    var color: Color
    var size: CGFloat = 6

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .shadow(color: color.opacity(0.7), radius: 3)
    }
}
