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
        panel.setGlassContent(host, cornerRadius: BadgeView.height / 2)
    }

    /// macOS が入力ソースを切り替えたときにカーソルの下に出す札の幅と、その札との間
    private static let systemIndicatorWidth: CGFloat = 30
    private static let systemIndicatorGap: CGFloat = 6

    /// besideSystemIndicator なら、macOS の札と重ならないようにその右に出す
    func show(_ mode: InputMode, near line: NSRect, besideSystemIndicator: Bool = false) {
        model.mode = mode
        fade?.cancel()
        host.layoutSubtreeIfNeeded()
        let shift = besideSystemIndicator && Self.systemIndicatorEnabled ? Self.systemIndicatorWidth + Self.systemIndicatorGap : 0
        panel.place(size: host.fittingSize, below: line, gap: 8, leading: -shift)
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

    /// `defaults write -g TSMLanguageIndicatorEnabled -bool false` で macOS の札を消していれば false
    private static var systemIndicatorEnabled: Bool {
        UserDefaults.standard.object(forKey: "TSMLanguageIndicatorEnabled") as? Bool ?? true
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

    static let height: CGFloat = 30

    var body: some View {
        ModeChip(mode: model.mode)
            .padding(.leading, 5)
            .padding(.trailing, 11)
            .frame(height: Self.height)
            .fixedSize()
            .animation(Theme.move, value: model.mode)
    }
}

/// モードの字と名前。ひらがなは朱で塗り、カタカナは朱の枠。英数は墨の枠、全角英数は墨で塗る
struct ModeChip: View {
    let mode: InputMode

    var body: some View {
        let look = Self.look(mode)
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        HStack(spacing: 7) {
            Text(look.glyph)
                .font(.system(size: 12.5, weight: .bold))
                .foregroundStyle(look.filled ? Theme.onAccent : look.color)
                .frame(width: 21, height: 21)
                .background(look.filled ? look.color : .clear, in: shape)
                .overlay(shape.strokeBorder(look.color, lineWidth: look.filled ? 0 : 1.4))
                .contentTransition(.opacity)
            Text(look.name)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.ink)
                .contentTransition(.opacity)
        }
    }

    static func look(_ mode: InputMode) -> (glyph: String, name: String, filled: Bool, color: Color) {
        switch mode {
        case .hiragana: ("あ", "ひらがな", true, Theme.accent)
        case .katakana: ("ア", "カタカナ", false, Theme.accent)
        case .halfwidthKatakana: ("ｱ", "半角カナ", false, Theme.accent)
        case .ascii: ("A", "英数", false, Theme.ink)
        case .fullwidthRoman: ("Ａ", "全角英数", true, Theme.ink)
        }
    }
}
