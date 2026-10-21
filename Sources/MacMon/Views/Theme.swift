import SwiftUI

/// Catppuccin Mocha 配色，与 Web 版大屏保持一致
enum Theme {
    static let base      = Color(hex: 0x181825)
    static let surface   = Color(hex: 0x1E1E2E)
    static let surface2  = Color(hex: 0x252537)
    static let line      = Color(hex: 0x313244)
    static let text      = Color(hex: 0xCDD6F4)
    static let muted     = Color(hex: 0xA6ADC8)
    static let dim       = Color(hex: 0x6C7086)

    static let blue      = Color(hex: 0x89B4FA)
    static let green     = Color(hex: 0xA6E3A1)
    static let yellow    = Color(hex: 0xF9E2AF)
    static let red       = Color(hex: 0xF38BA8)
    static let purple    = Color(hex: 0xCBA6F7)
    static let teal      = Color(hex: 0x94E2D5)
    static let peach     = Color(hex: 0xFAB387)
    static let orange    = Color(hex: 0xFAB387)
    static let mauve     = Color(hex: 0xCBA6F7)
    static let sapphire  = Color(hex: 0x74C7EC)

    /// 页面背景：中心略亮的径向渐变，避免整屏死黑一片
    @ViewBuilder
    static var pageBackground: some View {
        ZStack {
            base
            RadialGradient(
                colors: [Color(hex: 0x222233).opacity(0.9), base.opacity(0)],
                center: .init(x: 0.5, y: 0.28),
                startRadius: 40,
                endRadius: 900
            )
        }
    }

    /// 按数值返回「健康 → 危险」的渐变色
    static func level(_ percent: Double, warn: Double = 70, danger: Double = 88) -> Color {
        if percent >= danger { return red }
        if percent >= warn { return yellow }
        return green
    }

    static func riskColor(_ level: RiskLevel) -> Color {
        switch level {
        case .none:     return dim
        case .low:      return teal
        case .medium:   return yellow
        case .high:     return peach
        case .critical: return red
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red:   Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue:  Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

// MARK: - 字号

/// 分页后每屏只有 1–3 张卡，正文可以比原来放大一档。
enum TS {
    static let hero: CGFloat    = 58
    static let metric: CGFloat  = 36
    static let title: CGFloat   = 15
    static let heading: CGFloat = 13
    static let body: CGFloat    = 12
    static let caption: CGFloat = 10.5
    static let micro: CGFloat   = 9.5
}

// MARK: - 通用容器

struct Card<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    var accent: Color = Theme.blue
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(accent)
                    .frame(width: 3, height: 15)
                Text(title)
                    .font(.system(size: TS.title, weight: .semibold))
                    .foregroundStyle(Theme.text)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: TS.caption))
                        .foregroundStyle(Theme.dim)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 15)
            .padding(.bottom, 12)

            content
                .padding(.horizontal, 20)
                .padding(.bottom, 17)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
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

struct MetricLabel: View {
    let label: String
    let value: String
    var unit: String? = nil
    var color: Color = Theme.text

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(Theme.dim)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(color)
                if let unit {
                    Text(unit)
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.dim)
                }
            }
        }
    }
}

struct RiskBadge: View {
    let risk: RiskAssessment
    var compact: Bool = false

    var body: some View {
        if risk.level == .none {
            EmptyView()
        } else {
            Text(compact ? risk.level.label : "\(risk.level.label) · \(risk.score)")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Theme.riskColor(risk.level))
                // 英文等级名（Medium / Critical）比中文长，宁可整体缩小也不要换行成竖排
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Theme.riskColor(risk.level).opacity(0.14))
                )
        }
    }
}

extension AlertLevel {
    /// 三级告警各自的颜色。以前只分「critical / 其它」，
    /// 导致「启动项被移除」这类 info 也用了警告色，看上去像出了事。
    var color: Color {
        switch self {
        case .critical: return Theme.red
        case .warning:  return Theme.yellow
        case .info:     return Theme.blue
        }
    }
}
