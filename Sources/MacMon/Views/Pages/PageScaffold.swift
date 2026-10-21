import SwiftUI

/// 每个页面的统一外壳：大标题 + 副标题 + 右上角统计，其余区域交给页面自己分配。
///
/// `GeometryReader` 放在 `padding` 内侧，`size` 就是去掉内距后的可用区域，
/// 页面里不用再手算减 padding。
struct PageScaffold<Content: View, Accessory: View>: View {
    let page: DashboardPage
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var content: (CGSize) -> Content

    var body: some View {
        GeometryReader { geo in
            VStack(alignment: .leading, spacing: 14) {
                header
                content(geo.size)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(.init(top: 4, leading: 26, bottom: 14, trailing: 26))
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 9) {
                    Image(systemName: page.icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(page.accent)
                    Text(page.localizedTitle)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Theme.text)
                }
                Text(page.subtitle)
                    .font(.system(size: TS.caption))
                    .foregroundStyle(Theme.dim)
            }
            Spacer(minLength: 12)
            accessory
        }
        .frame(height: 46)
    }
}

extension PageScaffold where Accessory == EmptyView {
    init(page: DashboardPage, @ViewBuilder content: @escaping (CGSize) -> Content) {
        self.init(page: page, accessory: { EmptyView() }, content: content)
    }
}

/// 概览 / 性能页共用的大数字指标卡。
struct HeroMetric: View {
    var label: String
    var value: String
    var unit: String = "%"
    var color: Color = Theme.blue
    var caption: String? = nil
    var tag: String? = nil
    /// 0...100，传了就画底部细进度条
    var progress: Double? = nil
    var history: [Double]? = nil
    var maxHistory: Double = 100
    /// 折线基线（默认 0）。温度这类恒定在中高区间的指标需要非零基线
    var historyMin: Double = 0
    /// 环形仪表（温度这类没有「进度」概念的指标用）
    var ring: Double? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text(label)
                    .font(.system(size: TS.body, weight: .medium))
                    .foregroundStyle(Theme.muted)
                if let tag {
                    Text(tag)
                        .font(.system(size: TS.micro, weight: .medium))
                        .foregroundStyle(color.opacity(0.9))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(
                            RoundedRectangle(cornerRadius: 3).fill(color.opacity(0.13))
                        )
                }
                Spacer(minLength: 0)
            }

            HStack(alignment: .center, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(value)
                        .font(.system(size: TS.hero, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.text)
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(unit)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Theme.dim)
                }

                Spacer(minLength: 0)

                if let ring {
                    RingGauge(
                        value: ring,
                        color: color,
                        lineWidth: 6,
                        caption: nil,
                        subcaption: nil
                    )
                    .frame(width: 56, height: 56)
                }
            }
            .padding(.top, 10)

            if let caption {
                Text(caption)
                    .font(.system(size: TS.caption, design: .monospaced))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(1)
                    .padding(.top, 4)
            }

            // 折线独占剩余高度。这里不能再插 Spacer——Spacer 和
            // `maxHeight: .infinity` 的折线会平分剩余空间，折线只剩十几点高。
            if let history, history.count > 1 {
                Sparkline(
                    values: history,
                    maxValue: maxHistory,
                    minValue: historyMin,
                    color: color
                )
                .padding(.top, 10)
                .frame(maxHeight: .infinity, alignment: .bottom)
            } else {
                Color.clear.frame(maxHeight: .infinity)
            }

            if let progress {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.surface2)
                        Capsule()
                            .fill(color)
                            .frame(width: max(3, geo.size.width * min(max(progress, 0), 100) / 100))
                    }
                }
                .frame(height: 4)
            } else {
                Color.clear.frame(height: 4)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Theme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Theme.line, lineWidth: 1)
                )
        )
    }
}
