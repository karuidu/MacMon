// MacMon 应用图标生成器
//
// 用法：swift make-icon.swift <pulse|dial> <out.png> [边长]
//
// 规范：1024 画布，824 连续圆角方块居中（macOS Big Sur 起的图标网格），
// 圆角 186 ≈ 0.2256 × 824；投影自己画，画布留透明边距。
//
// 两个方案共用同一套底色与光照，只有主形状不同，方便横向对比。

import AppKit
import CoreGraphics

let canvas: CGFloat = 1024
let bodySide: CGFloat = 824
let inset = (canvas - bodySide) / 2
let corner: CGFloat = 186

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: a)
}

/// 视觉坐标（左上原点、y 向下）；绘制时整体翻转，写数值不用换算
func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

func squircle(_ r: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

/// 按视觉角度（0° 指右、90° 指上）采样圆弧。翻转坐标系后 `addArc` 的角度
/// 和方向都是反的，用采样点最省心。
func arcPath(center: CGPoint, radius: CGFloat, from: CGFloat, to: CGFloat) -> CGPath {
    let path = CGMutablePath()
    let steps = max(24, Int(abs(to - from) / 3))
    for i in 0...steps {
        let v = (from + (to - from) * CGFloat(i) / CGFloat(steps)) * .pi / 180
        let point = CGPoint(x: center.x + radius * cos(v), y: center.y - radius * sin(v))
        i == 0 ? path.move(to: point) : path.addLine(to: point)
    }
    return path
}

/// 渐变描边：先按白色描进透明层，再 sourceIn 灌渐变。
/// 渐变范围要盖住整条路径，否则没盖到的地方会露出白色。
func strokeGradient(_ ctx: CGContext, path: CGPath, width: CGFloat,
                    colors: [CGColor], from: CGPoint, to: CGPoint) {
    ctx.saveGState()
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    ctx.addPath(path)
    ctx.setLineWidth(width)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.setStrokeColor(CGColor(gray: 1, alpha: 1))
    ctx.strokePath()
    ctx.setBlendMode(.sourceIn)
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                              colors: colors as CFArray,
                              locations: nil)!
    ctx.drawLinearGradient(gradient, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.endTransparencyLayer()
    ctx.restoreGState()
}

/// 辉光：同一形状用带阴影的描边画两遍，近的一层收紧、远的一层铺开
func glow(_ ctx: CGContext, path: CGPath, width: CGFloat,
          color: CGColor, blur: CGFloat, alpha: CGFloat) {
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: blur, color: rgb(0x5FD0FF, alpha))
    ctx.addPath(path)
    ctx.setLineWidth(width)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.setStrokeColor(color)
    ctx.strokePath()
    ctx.restoreGState()
}

func drawBackground(_ ctx: CGContext, body: CGRect, bodyPath: CGPath) {
    let space = CGColorSpaceCreateDeviceRGB()

    // 投影：让它在浅色桌面上也立得住
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 38, color: rgb(0x000000, 0.46))
    ctx.addPath(bodyPath)
    ctx.setFillColor(rgb(0x05060A))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(bodyPath)
    ctx.clip()

    // 靛蓝 → 深墨
    let base = CGGradient(colorsSpace: space,
                          colors: [rgb(0x3A4270), rgb(0x1B2036), rgb(0x0B0E18)] as CFArray,
                          locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(base, start: p(0, inset), end: p(0, inset + bodySide), options: [])

    // 左上柔光。用径向而不是线性：线性渐变到端点会戛然而止，
    // 在方块上留下一道斜向的硬边（踩过一次）。
    let sheen = CGGradient(colorsSpace: space,
                           colors: [rgb(0xFFFFFF, 0.20), rgb(0xFFFFFF, 0)] as CFArray,
                           locations: [0, 1])!
    ctx.drawRadialGradient(sheen,
                           startCenter: p(360, 150), startRadius: 0,
                           endCenter: p(360, 150), endRadius: 540,
                           options: [])

    // 右下角冷光
    let cool = CGGradient(colorsSpace: space,
                          colors: [rgb(0x5B8CFF, 0.24), rgb(0x5B8CFF, 0)] as CFArray,
                          locations: [0, 1])!
    ctx.drawRadialGradient(cool,
                           startCenter: p(830, 860), startRadius: 0,
                           endCenter: p(830, 860), endRadius: 440,
                           options: [])

    // 底部暗角
    let vignette = CGGradient(colorsSpace: space,
                              colors: [rgb(0x000000, 0), rgb(0x000000, 0.30)] as CFArray,
                              locations: [0.5, 1])!
    ctx.drawRadialGradient(vignette,
                           startCenter: p(512, 470), startRadius: 200,
                           endCenter: p(512, 470), endRadius: 670,
                           options: [])

    ctx.restoreGState()
}

func drawPulse(_ ctx: CGContext, simplified: Bool) {
    let baseY: CGFloat = 546
    let path = CGMutablePath()

    if simplified {
        // 16/32px 下，两个小波峰只会糊成两个点。小尺寸只留主峰，
        // 并把线加粗——这是 macOS 图标常见的「按尺寸改稿」。
        path.move(to: p(174, baseY))
        path.addLine(to: p(374, baseY))
        path.addLine(to: p(520, baseY - 198))
        path.addLine(to: p(566, baseY + 166))
        path.addLine(to: p(614, baseY))
        path.addLine(to: p(850, baseY))
    } else {
        // 主形状占方块的 ~78% 宽度，视觉重心比几何中心略低一点点
        path.move(to: p(176, baseY))
        path.addLine(to: p(344, baseY))
        path.addLine(to: p(388, baseY - 48))
        path.addLine(to: p(432, baseY))
        path.addLine(to: p(482, baseY))
        path.addLine(to: p(520, baseY - 188))   // R 峰
        path.addLine(to: p(558, baseY + 156))   // S 谷
        path.addLine(to: p(596, baseY))
        path.addLine(to: p(646, baseY))
        path.addLine(to: p(684, baseY - 34))
        path.addLine(to: p(722, baseY))
        path.addLine(to: p(848, baseY))
    }

    let width: CGFloat = simplified ? 48 : 38

    // 两层辉光：宽的一层做氛围，窄的一层让管子边缘不发虚
    glow(ctx, path: path, width: width + 22, color: rgb(0x4FA8FF, 0.30),
         blur: simplified ? 30 : 46, alpha: 0.30)
    glow(ctx, path: path, width: width + 6, color: rgb(0x5FD0FF, 0.95),
         blur: simplified ? 14 : 22, alpha: 0.85)

    // 管身：青 → 长春花蓝
    strokeGradient(ctx, path: path, width: width,
                   colors: [rgb(0x7FE8FF), rgb(0x8FB6FF)],
                   from: p(180, 0), to: p(850, 0))

    // 高光芯：一条更细的白线，营造「灯管」的通透感
    ctx.saveGState()
    ctx.addPath(path)
    ctx.setLineWidth(simplified ? 14 : 11)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.setStrokeColor(rgb(0xFFFFFF, 0.85))
    ctx.strokePath()
    ctx.restoreGState()
}

func drawDial(_ ctx: CGContext) {
    let center = p(512, 512)
    let radius: CGFloat = 262

    // 轨道：底部留 90° 缺口
    ctx.addPath(arcPath(center: center, radius: radius, from: 135, to: -135))
    ctx.setLineWidth(46)
    ctx.setLineCap(.round)
    ctx.setStrokeColor(rgb(0xFFFFFF, 0.10))
    ctx.strokePath()

    // 量程弧
    let value = arcPath(center: center, radius: radius, from: 135, to: -30)
    glow(ctx, path: value, width: 62, color: rgb(0x4FA8FF, 0.30), blur: 44, alpha: 0.30)
    glow(ctx, path: value, width: 46, color: rgb(0x5FD0FF, 0.95), blur: 20, alpha: 0.80)
    strokeGradient(ctx, path: value, width: 44,
                   colors: [rgb(0x7FE8FF), rgb(0x8FB6FF)],
                   from: p(240, 0), to: p(790, 0))

    // 指针
    let needle = CGMutablePath()
    needle.move(to: CGPoint(x: center.x - 34 * cos(CGFloat(52) * .pi / 180),
                            y: center.y + 34 * sin(CGFloat(52) * .pi / 180)))
    needle.addLine(to: CGPoint(x: center.x + 168 * cos(CGFloat(52) * .pi / 180),
                               y: center.y - 168 * sin(CGFloat(52) * .pi / 180)))
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 18, color: rgb(0x000000, 0.55))
    ctx.addPath(needle)
    ctx.setLineWidth(20)
    ctx.setLineCap(.round)
    ctx.setStrokeColor(rgb(0xF2F8FF))
    ctx.strokePath()
    ctx.restoreGState()

    // 轴心
    ctx.setFillColor(rgb(0xEAF4FF))
    ctx.fillEllipse(in: CGRect(x: center.x - 26, y: center.y - 26, width: 52, height: 52))
    ctx.setFillColor(rgb(0x1A1E33))
    ctx.fillEllipse(in: CGRect(x: center.x - 11, y: center.y - 11, width: 22, height: 22))
}

func drawIcon(variant: String, side: Int, into ctx: CGContext) {
    ctx.translateBy(x: 0, y: canvas)
    ctx.scaleBy(x: 1, y: -1)
    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high

    let body = CGRect(x: inset, y: inset, width: bodySide, height: bodySide)
    let bodyPath = squircle(body, corner)
    let simplified = side <= 32

    drawBackground(ctx, body: body, bodyPath: bodyPath)

    // 主形状画在底色之上、边缘高光之下
    ctx.saveGState()
    ctx.addPath(bodyPath)
    ctx.clip()
    if variant == "dial" { drawDial(ctx) } else { drawPulse(ctx, simplified: simplified) }
    ctx.restoreGState()

    // 内侧高光，压住边缘
    ctx.setLineWidth(2)
    ctx.setStrokeColor(rgb(0xFFFFFF, 0.15))
    ctx.addPath(squircle(body.insetBy(dx: 1, dy: 1), corner - 1))
    ctx.strokePath()
}

func render(variant: String, side: Int) -> CGImage? {
    guard let ctx = CGContext(data: nil, width: side, height: side,
                              bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    ctx.scaleBy(x: CGFloat(side) / canvas, y: CGFloat(side) / canvas)
    drawIcon(variant: variant, side: side, into: ctx)
    return ctx.makeImage()
}

// MARK: - main

let args = CommandLine.arguments
guard args.count >= 3 else {
    print("用法: swift make-icon.swift <pulse|dial> <out.png> [边长]")
    exit(1)
}
let side = args.count >= 4 ? (Int(args[3]) ?? 1024) : 1024
guard let image = render(variant: args[1], side: side),
      let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
else {
    print("渲染失败")
    exit(1)
}
do {
    try data.write(to: URL(fileURLWithPath: args[2]))
    print("✓ \(args[1]) → \(args[2]) (\(side)×\(side))")
} catch {
    print("写入失败: \(error)")
    exit(1)
}
