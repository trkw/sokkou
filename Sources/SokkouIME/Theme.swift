import AppKit
import SwiftUI

/// 候補の窓とモードの印の色。明るい外観と暗い外観で切り替わる
enum Theme {
    static let ground = dynamic(light: 0xF5F4F0, dark: 0x141416)
    static let surface = dynamic(light: 0xFFFFFF, dark: 0x1F1F22)
    static let border = dynamic(light: 0xE4E2DC, dark: 0x2E2E33)
    static let ink = dynamic(light: 0x1C1C1E, dark: 0xF2F2F0)
    static let quiet = dynamic(light: 0x6B6B70, dark: 0xA1A1A8)
    static let rule = dynamic(light: 0xEFEDE8, dark: 0x26262A)
    /// 朱。選んでいる候補とひらがなの印に使う
    static let accent = dynamic(light: 0xC2410C, dark: 0xFB923C)

    static let cornerRadius: CGFloat = 10

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

/// 入力欄の上に浮かべる、フォーカスを奪わない窓
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

    /// 大きさ size の窓を、行の矩形 line のすぐ下に置く。下に入らなければ行の上に置き、横は画面の中に収める
    func place(size: NSSize, below line: NSRect, gap: CGFloat = 4, leading: CGFloat = 0) {
        let screen = NSScreen.screens.first { $0.frame.intersects(line) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(origin: .zero, size: size)
        var origin = NSPoint(x: line.minX - leading, y: line.minY - gap - size.height)
        if origin.y < visible.minY {
            origin.y = line.maxY + gap
        }
        origin.x = min(max(origin.x, visible.minX), visible.maxX - size.width)
        origin.y = min(max(origin.y, visible.minY), visible.maxY - size.height)
        setFrame(NSRect(origin: origin, size: size), display: true)
    }
}
