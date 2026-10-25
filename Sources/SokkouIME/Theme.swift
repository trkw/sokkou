import AppKit
import SwiftUI

/// 候補の窓とモードの印の色。明るい外観と暗い外観で切り替わる
enum Theme {
    // 色は設定の「色」で選んだ組から、描くときに引く。はじめは紙の地に墨、差し色は朱ひと色
    static let ground = dynamic(.ground)
    static let surface = dynamic(.surface)
    static let border = dynamic(.rule)
    static let ink = dynamic(.ink)
    static let quiet = dynamic(.quiet)
    static let rule = dynamic(.rule)
    /// 差し色。選んでいる候補とひらがなの印に使う
    static let accent = Color(nsColor: accentNSColor)
    /// 差し色の NSColor。入力欄の、選んでいる文節の下線の色に使う
    static let accentNSColor = dynamicNSColor(.accent)
    /// 差し色の上に載せる文字
    static let onAccent = dynamic(.onAccent)

    static let windowRadius: CGFloat = 14
    static let rowRadius: CGFloat = 8

    /// 選ぶ候補が移るときの動き。速く、跳ねすぎない
    static let move = Animation.spring(response: 0.2, dampingFraction: 0.86)

    private static func dynamic(_ role: ThemeRole) -> Color {
        Color(nsColor: dynamicNSColor(role))
    }

    private static func dynamicNSColor(_ role: ThemeRole) -> NSColor {
        NSColor(name: nil) { appearance in
            role.color(dark: appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
        }
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

/// ガラスの代わりに敷く紙の板。ガラスは画像にならないので、設定の見本とスナップショットで使う
struct PaperPlate: View {
    let radius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(Theme.surface.opacity(0.92))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Theme.border, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.12), radius: 14, y: 6)
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
            context.duration = 0.09
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
