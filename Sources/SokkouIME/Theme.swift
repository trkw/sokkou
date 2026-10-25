import AppKit
import SwiftUI

/// 候補の窓とモードの印の色。明るい外観と暗い外観で切り替わる
enum Theme {
    static let ground = dynamic(light: 0xF5F4F0, dark: 0x141416)
    static let surface = dynamic(light: 0xFFFFFF, dark: 0x1F1F22)
    static let border = dynamic(light: 0xE4E2DC, dark: 0x2E2E33)
    static let ink = dynamic(light: 0x1C1C1E, dark: 0xF2F2F0)
    static let quiet = dynamic(light: 0x6B6B70, dark: 0xA1A1A8)
    static let rule = dynamic(light: 0xE9E6DF, dark: 0x34343A)
    /// 朱。選んでいる候補とひらがなの印に使う
    static let accent = dynamic(light: 0xC2410C, dark: 0xFB923C)
    /// 朱の上に載せる文字
    static let onAccent = dynamic(light: 0xFFFFFF, dark: 0x1A0E08)

    static let windowRadius: CGFloat = 14
    static let rowRadius: CGFloat = 8

    /// 選ぶ候補が移るときの動き。速く、跳ねすぎない
    static let move = Animation.spring(response: 0.2, dampingFraction: 0.86)

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return color(isDark ? dark : light)
        })
    }

    private static func color(_ hex: UInt32) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

/// キーの形の小さな札。候補を選ぶキーと、窓の下の操作の案内に使う
struct Keycap: View {
    let text: String
    var inverted = false

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(inverted ? Theme.onAccent : Theme.quiet)
            .frame(minWidth: 17, minHeight: 17)
            .padding(.horizontal, text.count > 1 ? 3 : 0)
            .background(
                RoundedRectangle(cornerRadius: 4.5)
                    .fill(inverted ? Color.white.opacity(0.22) : Theme.quiet.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4.5)
                    .strokeBorder(inverted ? Color.white.opacity(0.35) : Theme.quiet.opacity(0.22), lineWidth: 0.5)
            )
    }
}

/// 入力欄の上に浮かべる、フォーカスを奪わない窓。macOS 26 では Liquid Glass、それより前はすりガラスの素材で描く
final class FloatingPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .popUpMenu
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        ignoresMouseEvents = true
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// content をガラスの上に載せる
    func setGlassContent(_ content: NSView, cornerRadius: CGFloat) {
        if #available(macOS 26, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = cornerRadius
            glass.contentView = content
            contentView = glass
        } else {
            let effect = NSVisualEffectView()
            effect.material = .popover
            effect.blendingMode = .behindWindow
            effect.state = .active
            effect.maskImage = Self.mask(radius: cornerRadius)
            content.frame = effect.bounds
            content.autoresizingMask = [.width, .height]
            effect.addSubview(content)
            contentView = effect
        }
    }

    /// 大きさ size の窓を、行の矩形 line のすぐ下に置く。下に入らなければ行の上に置き、横は画面の中に収める
    func place(size: NSSize, below line: NSRect, gap: CGFloat = 6, leading: CGFloat = 0) {
        let screen = NSScreen.screens.first { $0.frame.intersects(line) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(origin: .zero, size: size)
        var origin = NSPoint(x: line.minX - leading, y: line.minY - gap - size.height)
        if origin.y < visible.minY {
            origin.y = line.maxY + gap
        }
        origin.x = min(max(origin.x, visible.minX), visible.maxX - size.width)
        origin.y = min(max(origin.y, visible.minY), visible.maxY - size.height)
        setFrame(NSRect(origin: origin, size: size), display: true)
        invalidateShadow()
    }

    /// 現れるときに、短く透明から浮かび上がらせる
    func appear() {
        guard !isVisible else { return }
        alphaValue = 0
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            animator().alphaValue = 1
        }
    }

    private static func mask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}
