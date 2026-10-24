import AppKit
import SokkouCore
import SwiftUI

/// 候補の窓。プロセスに 1 つだけ作り、入力欄が変わっても使い回す
final class CandidatePanel {
    private let panel = FloatingPanel()
    private let model = CandidateModel()

    init() {
        let host = NSHostingView(rootView: CandidateView(model: model))
        host.sizingOptions = [.intrinsicContentSize]
        panel.contentView = host
    }

    func show(_ window: CandidateWindow, near line: NSRect) {
        model.window = window
        guard let content = panel.contentView else { return }
        content.layoutSubtreeIfNeeded()
        // 候補の文字の左端を、選んでいる文節の左端にそろえる
        panel.place(size: content.fittingSize, below: line, leading: CandidateView.textInset)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }
}

@Observable
final class CandidateModel {
    var window: CandidateWindow?
}

struct CandidateView: View {
    let model: CandidateModel

    static let width: CGFloat = 260
    /// 窓の左端から候補の文字までの幅
    static let textInset: CGFloat = 40

    var body: some View {
        if let window = model.window {
            VStack(alignment: .leading, spacing: 0) {
                header(window)
                Rectangle().fill(Theme.rule).frame(height: 1)
                VStack(spacing: 2) {
                    ForEach(Array(window.items.enumerated()), id: \.offset) { index, item in
                        row(label: window.labels[index], item: item, highlighted: index == window.highlighted)
                    }
                }
                .padding(6)
                Rectangle().fill(Theme.rule).frame(height: 1)
                Text("C-n 次 · C-p 前 · C-g 閉じる")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.quiet)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
            }
            .frame(width: Self.width, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius).strokeBorder(Theme.border))
        }
    }

    private func header(_ window: CandidateWindow) -> some View {
        HStack {
            Text(window.reading)
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.quiet)
            Spacer()
            if window.pageCount > 1 {
                Text("\(window.page + 1) / \(window.pageCount)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.quiet)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    private func row(label: Character, item: String, highlighted: Bool) -> some View {
        HStack(spacing: 0) {
            Text(String(label))
                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                .foregroundStyle(highlighted ? Theme.accent : Theme.quiet)
                .frame(width: Self.textInset - 6, alignment: .center)
            Text(item)
                .font(.system(size: 15))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .frame(height: 28)
        .background(highlighted ? Theme.accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 6))
    }
}
