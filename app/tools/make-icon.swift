// Renders the Claude Switch app icon (1024×1024 PNG) in the macOS 26 style:
// a warm squircle with soft depth and two overlapping glass "account" discs with a swap glyph.
// Usage: swift make-icon.swift out.png
import AppKit
import CoreGraphics

let out = CommandLine.arguments.dropFirst().first ?? "icon.png"
let S: CGFloat = 1024
let cs = CGColorSpace(name: CGColorSpace.displayP3)!
let ctx = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8, bytesPerRow: 0,
                    space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: cs, components: [r / 255, g / 255, b / 255, a])!
}

func squircle(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    // continuous-corner rounded rect (good approximation of Apple's squircle)
    let p = CGMutablePath()
    let r = min(radius, rect.width / 2)
    let k: CGFloat = 1.28 * r   // extend the curve like a continuous corner
    let (minX, minY, maxX, maxY) = (rect.minX, rect.minY, rect.maxX, rect.maxY)
    p.move(to: CGPoint(x: minX + k, y: maxY))
    p.addLine(to: CGPoint(x: maxX - k, y: maxY))
    p.addCurve(to: CGPoint(x: maxX, y: maxY - k), control1: CGPoint(x: maxX - k * 0.35, y: maxY), control2: CGPoint(x: maxX, y: maxY - k * 0.35))
    p.addLine(to: CGPoint(x: maxX, y: minY + k))
    p.addCurve(to: CGPoint(x: maxX - k, y: minY), control1: CGPoint(x: maxX, y: minY + k * 0.35), control2: CGPoint(x: maxX - k * 0.35, y: minY))
    p.addLine(to: CGPoint(x: minX + k, y: minY))
    p.addCurve(to: CGPoint(x: minX, y: minY + k), control1: CGPoint(x: minX + k * 0.35, y: minY), control2: CGPoint(x: minX, y: minY + k * 0.35))
    p.addLine(to: CGPoint(x: minX, y: maxY - k))
    p.addCurve(to: CGPoint(x: minX + k, y: maxY), control1: CGPoint(x: minX, y: maxY - k * 0.35), control2: CGPoint(x: minX + k * 0.35, y: maxY))
    p.closeSubpath()
    return p
}

let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = squircle(tile, 186)

// Drop shadow under the tile
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 34, color: rgb(0, 0, 0, 0.32))
ctx.addPath(tilePath); ctx.setFillColor(rgb(200, 90, 55)); ctx.fillPath()
ctx.restoreGState()

// Tile body: warm Claude-like gradient
ctx.saveGState()
ctx.addPath(tilePath); ctx.clip()
let bg = CGGradient(colorsSpace: cs, colors: [rgb(246, 168, 128), rgb(222, 114, 78), rgb(176, 72, 42)] as CFArray, locations: [0, 0.55, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: tile.maxY), end: CGPoint(x: 0, y: tile.minY), options: [])
// soft top-left light
let glow = CGGradient(colorsSpace: cs, colors: [rgb(255, 236, 220, 0.55), rgb(255, 236, 220, 0)] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 330, y: 820), startRadius: 0, endCenter: CGPoint(x: 330, y: 820), endRadius: 560, options: [])
ctx.restoreGState()

// Glass disc helper
func disc(center: CGPoint, radius: CGFloat, fill: [CGColor], rim: CGFloat, shadow: CGFloat) {
    let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 40, color: rgb(90, 30, 10, shadow))
    ctx.addEllipse(in: rect); ctx.setFillColor(fill.last!); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addEllipse(in: rect); ctx.clip()
    let g = CGGradient(colorsSpace: cs, colors: fill as CFArray, locations: nil)!
    ctx.drawLinearGradient(g, start: CGPoint(x: rect.minX, y: rect.maxY), end: CGPoint(x: rect.maxX, y: rect.minY), options: [])
    // specular highlight
    let hl = CGGradient(colorsSpace: cs, colors: [rgb(255, 255, 255, 0.55), rgb(255, 255, 255, 0)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(hl, start: CGPoint(x: 0, y: rect.maxY), end: CGPoint(x: 0, y: rect.midY + radius * 0.1), options: [])
    ctx.restoreGState()
    // rim
    ctx.saveGState()
    ctx.addEllipse(in: rect.insetBy(dx: rim / 2, dy: rim / 2))
    ctx.setStrokeColor(rgb(255, 255, 255, 0.7)); ctx.setLineWidth(rim); ctx.strokePath()
    ctx.restoreGState()
}

// Person glyph on a disc
func person(center: CGPoint, scale: CGFloat, color: CGColor) {
    ctx.saveGState()
    ctx.setFillColor(color)
    let head = CGRect(x: center.x - 52 * scale, y: center.y + 8 * scale, width: 104 * scale, height: 104 * scale)
    ctx.addEllipse(in: head); ctx.fillPath()
    let body = CGMutablePath()
    body.addArc(center: CGPoint(x: center.x, y: center.y - 120 * scale), radius: 108 * scale, startAngle: 0, endAngle: .pi, clockwise: false)
    body.closeSubpath()
    ctx.addPath(body); ctx.fillPath()
    ctx.restoreGState()
}

// Back disc (left, frosted)
disc(center: CGPoint(x: 400, y: 560), radius: 200,
     fill: [rgb(255, 255, 255, 0.55), rgb(255, 240, 230, 0.30)], rim: 6, shadow: 0.25)
ctx.saveGState()
ctx.addEllipse(in: CGRect(x: 200, y: 360, width: 400, height: 400)); ctx.clip()
person(center: CGPoint(x: 400, y: 560), scale: 1.0, color: rgb(255, 255, 255, 0.85))
ctx.restoreGState()

// Front disc (right, bright glass)
disc(center: CGPoint(x: 624, y: 464), radius: 200,
     fill: [rgb(255, 255, 255, 0.97), rgb(255, 232, 218, 0.92)], rim: 6, shadow: 0.35)
ctx.saveGState()
ctx.addEllipse(in: CGRect(x: 424, y: 264, width: 400, height: 400)); ctx.clip()
person(center: CGPoint(x: 624, y: 464), scale: 1.0, color: rgb(214, 108, 72))
ctx.restoreGState()

// Swap badge
let badgeC = CGPoint(x: 712, y: 712), badgeR: CGFloat = 92
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 22, color: rgb(80, 20, 0, 0.35))
ctx.addEllipse(in: CGRect(x: badgeC.x - badgeR, y: badgeC.y - badgeR, width: badgeR * 2, height: badgeR * 2))
ctx.setFillColor(rgb(255, 255, 255)); ctx.fillPath()
ctx.restoreGState()
if let sym = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: nil)?
    .withSymbolConfiguration(.init(pointSize: 112, weight: .bold)) {
    let tinted = NSImage(size: sym.size, flipped: false) { r in
        sym.draw(in: r)
        NSColor(red: 0.84, green: 0.40, blue: 0.27, alpha: 1).set()
        r.fill(using: .sourceAtop)
        return true
    }
    var rect = CGRect(x: 0, y: 0, width: sym.size.width, height: sym.size.height)
    if let cg = tinted.cgImage(forProposedRect: &rect, context: nil, hints: nil) {
        let w = sym.size.width, h = sym.size.height
        ctx.draw(cg, in: CGRect(x: badgeC.x - w / 2, y: badgeC.y - h / 2, width: w, height: h))
    }
}

// Inner edge highlight of the tile (glassy rim)
ctx.saveGState()
ctx.addPath(tilePath); ctx.clip()
ctx.addPath(tilePath)
ctx.setStrokeColor(rgb(255, 255, 255, 0.35)); ctx.setLineWidth(5); ctx.strokePath()
ctx.restoreGState()

let img = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: img)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
