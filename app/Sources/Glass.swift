import AppKit
import SwiftUI

/// Real Liquid Glass (`NSGlassEffectView`, macOS 26+) looked up at runtime, so the app builds with
/// older SDKs. On older systems it falls back to a vibrancy material.
struct GlassBackground: NSViewRepresentable {
    var cornerRadius: CGFloat = 22
    var tint: NSColor? = nil
    var clear = false

    static let glassClass: NSView.Type? = NSClassFromString("NSGlassEffectView") as? NSView.Type
    static var isLiquidGlass: Bool { glassClass != nil }

    func makeNSView(context: Context) -> NSView {
        if let cls = Self.glassClass {
            let v = cls.init(frame: .zero)
            configure(v)
            return v
        }
        let v = NSVisualEffectView()
        v.material = .popover
        v.blendingMode = .behindWindow
        v.state = .active
        v.wantsLayer = true
        configure(v)
        return v
    }

    func updateNSView(_ v: NSView, context: Context) { configure(v) }

    private func configure(_ v: NSView) {
        if Self.glassClass != nil {
            v.setValue(cornerRadius, forKey: "cornerRadius")
            v.setValue(tint, forKey: "tintColor")
            v.setValue(clear ? 1 : 0, forKey: "style")
        } else {
            v.layer?.cornerRadius = cornerRadius
            v.layer?.cornerCurve = .continuous
            v.layer?.masksToBounds = true
            if let tint { v.layer?.backgroundColor = tint.withAlphaComponent(0.25).cgColor }
        }
    }
}

/// Window-wide translucent backdrop (behind-window blur).
struct WindowBackdrop: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .underWindowBackground

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = .behindWindow
        v.state = .followsWindowActiveState
        return v
    }

    func updateNSView(_ v: NSVisualEffectView, context: Context) { v.material = material }
}

extension View {
    func glass(_ radius: CGFloat = 22, tint: Color? = nil, clear: Bool = false) -> some View {
        background(GlassBackground(cornerRadius: radius, tint: tint.map { NSColor($0) }, clear: clear))
    }

    /// Soft card for content (Apple keeps glass for the navigation layer and uses fills for content).
    func card(_ radius: CGFloat = 18) -> some View {
        background(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(.primary.opacity(0.045))
                .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(.primary.opacity(0.07), lineWidth: 0.5))
        )
    }
}

// MARK: - Buttons

struct GlassButtonStyle: ButtonStyle {
    var prominent = false
    var tint: Color = Palette.claude
    var radius: CGFloat = 999

    func makeBody(configuration: Configuration) -> some View {
        StyledBody(configuration: configuration, style: self)
    }

    private struct StyledBody: View {
        var configuration: Configuration
        var style: GlassButtonStyle
        @Environment(\.isEnabled) private var enabled

        var body: some View {
            style.styled(configuration).opacity(enabled ? 1 : 0.45).saturation(enabled ? 1 : 0.3)
        }
    }

    fileprivate func styled(_ configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background {
                if prominent {
                    Capsule(style: .continuous)
                        .fill(LinearGradient(colors: [tint.opacity(0.95), tint], startPoint: .top, endPoint: .bottom))
                        .overlay(Capsule(style: .continuous).strokeBorder(.white.opacity(0.35), lineWidth: 0.7).blendMode(.overlay))
                        .shadow(color: tint.opacity(0.35), radius: 8, y: 3)
                } else {
                    GlassBackground(cornerRadius: radius == 999 ? 17 : radius)
                }
            }
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Round glass icon button, like the Control Center tiles.
struct GlassIconButton: View {
    var systemName: String
    var size: CGFloat = 34
    var help: String = ""
    var action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.42, weight: .semibold))
                .frame(width: size, height: size)
                .background(GlassBackground(cornerRadius: size / 2))
                .overlay(Circle().fill(.primary.opacity(hover ? 0.06 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hover = $0 }
    }
}

// MARK: - Shared pieces

struct Avatar: View {
    var name: String
    var size: CGFloat = 36
    var active = false

    var body: some View {
        let (a, b) = Palette.avatar(name)
        ZStack {
            Circle().fill(LinearGradient(colors: [a, b], startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle().fill(LinearGradient(colors: [.white.opacity(0.45), .clear], startPoint: .top, endPoint: .center))
                .padding(size * 0.06)
                .blendMode(.overlay)
            Text(String(name.prefix(1)).uppercased())
                .font(.system(size: size * 0.44, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.15), radius: 1, y: 1)
        }
        .frame(width: size, height: size)
        .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 0.8))
        .overlay(alignment: .bottomTrailing) {
            if active {
                Circle().fill(Color(red: 0.20, green: 0.78, blue: 0.45))
                    .frame(width: size * 0.3, height: size * 0.3)
                    .overlay(Circle().strokeBorder(.white, lineWidth: max(1.5, size * 0.05)))
                    .offset(x: size * 0.03, y: size * 0.03)
            }
        }
    }
}

struct UsageBar: View {
    var label: String
    var value: Double?
    var stale = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(label).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                Spacer()
                Text(value.map { "\(Int($0))%" } ?? "—")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(stale ? .secondary : .primary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.primary.opacity(0.10))
                    Capsule()
                        .fill(LinearGradient(colors: [Palette.usage(value).opacity(0.85), Palette.usage(value)],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(6, geo.size.width * CGFloat(min(100, value ?? 0)) / 100))
                        .opacity(value == nil ? 0 : (stale ? 0.4 : 1))
                }
            }
            .frame(height: 6)
        }
    }
}

struct UsageRing: View {
    var value: Double?
    var lineWidth: CGFloat = 10
    var stale = false

    var body: some View {
        ZStack {
            Circle().stroke(.primary.opacity(0.08), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: CGFloat(min(100, value ?? 0)) / 100)
                .stroke(AngularGradient(colors: [Palette.usage(value).opacity(0.7), Palette.usage(value)], center: .center),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .opacity(stale ? 0.45 : 1)
            VStack(spacing: 0) {
                Text(value.map { "\(Int($0))" } ?? "—")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("%").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            }
        }
        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: value)
    }
}

struct Sparkline: View {
    var points: [Double]
    var color: Color

    var body: some View {
        GeometryReader { geo in
            let maxV = 100.0
            let w = geo.size.width, h = geo.size.height
            let step = points.count > 1 ? w / CGFloat(points.count - 1) : 0
            let pts = points.enumerated().map { CGPoint(x: CGFloat($0.offset) * step, y: h - CGFloat($0.element / maxV) * h) }
            ZStack {
                Path { p in
                    guard let first = pts.first else { return }
                    p.move(to: CGPoint(x: first.x, y: h))
                    pts.forEach { p.addLine(to: $0) }
                    p.addLine(to: CGPoint(x: pts.last!.x, y: h))
                }
                .fill(LinearGradient(colors: [color.opacity(0.28), color.opacity(0)], startPoint: .top, endPoint: .bottom))
                Path { p in
                    guard let first = pts.first else { return }
                    p.move(to: first)
                    pts.dropFirst().forEach { p.addLine(to: $0) }
                }
                .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
        }
    }
}

struct Chip: View {
    var text: String
    var color: Color = .secondary
    var systemImage: String? = nil

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage).font(.system(size: 9, weight: .bold)) }
            Text(text).font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(color.opacity(0.14)))
    }
}
