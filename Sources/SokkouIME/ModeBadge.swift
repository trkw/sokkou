import AppKit
import SokkouCore
import SwiftUI

/// モードを変えたときに、カーソルの近くに 1 秒ほど出る小さな札
final class ModeBadge {
    private let panel = FloatingPanel()
    private let model = BadgeModel()
    private let host: NSHostingView<BadgeView>
    private var fade: Task<Void, Never>?

    init() {
        host = NSHostingView(rootView: BadgeView(model: model))
        host.sizingOptions = [.intrinsicContentSize]
        panel.setGlassContent(host, cornerRadius: BadgeView.radius)
    }

    func show(_ mode: InputMode, near line: NSRect) {
        model.mode = mode
        fade?.cancel()
        host.layoutSubtreeIfNeeded()
        panel.place(size: host.fittingSize, below: line, gap: 8)
        if panel.isVisible {
            panel.alphaValue = 1
        } else {
            panel.appear()
        }
        fade = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.1))
            guard !Task.isCancelled, let self else { return }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.3
                self.panel.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                // 消えるまでの間に次のモードが出ていたら、その札は残す
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

    /// 札の一辺。字だけの小さな四角にする
    static let height: CGFloat = 28
    static let radius: CGFloat = 8

    var body: some View {
        ModeGlyph(mode: model.mode)
            .fixedSize()
            .animation(Theme.move, value: model.mode)
    }
}

/// モードの字だけの四角。ひらがなは朱で塗り、カタカナは朱の枠、半角カナは朱の点線の枠。英数は墨の枠、全角英数は墨で塗る
struct ModeGlyph: View {
    let mode: InputMode

    var body: some View {
        let look = Self.look(mode)
        let shape = RoundedRectangle(cornerRadius: BadgeView.radius, style: .continuous)
        Text(look.glyph)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(look.filled ? look.onFill : look.color)
            .frame(width: BadgeView.height, height: BadgeView.height)
            .background(look.filled ? look.color : .clear, in: shape)
            .overlay(
                shape.inset(by: 0.75).stroke(
                    look.filled ? Color.clear : look.color,
                    style: StrokeStyle(lineWidth: 1.5, dash: look.dashed ? [2.5, 2] : [])
                )
            )
            .contentTransition(.opacity)
            .accessibilityLabel(look.name)
    }

    static func look(_ mode: InputMode) -> (glyph: String, name: String, filled: Bool, dashed: Bool, color: Color, onFill: Color) {
        switch mode {
        case .hiragana: ("あ", "ひらがな", true, false, Theme.accent, Theme.onAccent)
        case .katakana: ("ア", "カタカナ", false, false, Theme.accent, Theme.onAccent)
        case .halfwidthKatakana: ("ｱ", "半角カナ", false, true, Theme.accent, Theme.onAccent)
        case .ascii: ("A", "英数", false, false, Theme.ink, Theme.ground)
        case .fullwidthRoman: ("Ａ", "全角英数", true, false, Theme.ink, Theme.ground)
        }
    }
}
