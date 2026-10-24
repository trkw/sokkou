import AppKit
import SokkouCore
import SwiftUI

/// モードを変えたときに、カーソルの近くに 1 秒ほど出る小さな印
final class ModeBadge {
    private let panel = FloatingPanel()
    private let model = BadgeModel()
    private var fade: Task<Void, Never>?

    static let size: CGFloat = 22

    init() {
        panel.hasShadow = false
        panel.contentView = NSHostingView(rootView: BadgeView(model: model))
    }

    func show(_ mode: InputMode, near line: NSRect) {
        model.mode = mode
        fade?.cancel()
        panel.alphaValue = 1
        panel.place(size: NSSize(width: Self.size, height: Self.size), below: line, gap: 6)
        panel.orderFrontRegardless()
        fade = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, let self else { return }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.25
                self.panel.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                // 消えるまでの間に次のモードが出ていたら、その印は残す
                MainActor.assumeIsolated {
                    guard let self, self.panel.alphaValue == 0 else { return }
                    self.panel.orderOut(nil)
                }
            })
        }
    }

    func hide() {
        fade?.cancel()
        panel.orderOut(nil)
    }
}

@Observable
final class BadgeModel {
    var mode: InputMode = .hiragana
}

struct BadgeView: View {
    let model: BadgeModel

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 6)
        let (glyph, filled, color) = Self.look(model.mode)
        Text(glyph)
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(filled ? Theme.surface : color)
            .frame(width: ModeBadge.size, height: ModeBadge.size)
            .background(filled ? color : Theme.surface, in: shape)
            .overlay(shape.strokeBorder(color, lineWidth: filled ? 0 : 1.5))
    }

    /// ひらがなは朱で塗る。カタカナは朱の枠、英字は墨の枠
    static func look(_ mode: InputMode) -> (String, Bool, Color) {
        switch mode {
        case .hiragana: ("あ", true, Theme.accent)
        case .katakana: ("ア", false, Theme.accent)
        case .halfwidthKatakana: ("ｱ", false, Theme.accent)
        case .ascii: ("A", false, Theme.ink)
        case .fullwidthRoman: ("Ａ", false, Theme.ink)
        }
    }
}
