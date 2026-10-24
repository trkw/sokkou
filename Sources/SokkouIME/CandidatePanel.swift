import AppKit
import SokkouCore
import SwiftUI

/// 候補の窓。プロセスに 1 つだけ作り、入力欄が変わっても使い回す
final class CandidatePanel {
    private let panel = FloatingPanel()
    private let model = CandidateModel()
    private let host: NSHostingView<CandidateView>

    init() {
        host = NSHostingView(rootView: CandidateView(model: model))
        host.sizingOptions = [.intrinsicContentSize]
        panel.setGlassContent(host, cornerRadius: Theme.windowRadius)
    }

    func show(_ window: CandidateWindow, near line: NSRect) {
        model.window = window
        host.layoutSubtreeIfNeeded()
        // 候補の文字の左端を、選んでいる文節の左端にそろえる
        panel.place(size: host.fittingSize, below: line, leading: CandidateView.textInset)
        panel.appear()
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

    /// 窓の左端から候補の文字までの幅
    static let textInset: CGFloat = 44

    var body: some View {
        if let window = model.window {
            CandidateList(window: window)
        }
    }
}

/// 候補の窓の中身。読み、候補、操作の案内を縦に並べる
struct CandidateList: View {
    static let maxWidth: CGFloat = 420

    let window: CandidateWindow
    @Namespace var highlight

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            VStack(spacing: 1) {
                ForEach(Array(window.items.enumerated()), id: \.offset) { index, item in
                    row(label: window.labels[index], item: item, highlighted: index == window.highlighted)
                }
            }
            .padding(.horizontal, 6)
            .animation(Theme.move, value: window.highlighted)
            footer
        }
        // 長い読みや候補でも画面からはみ出さないよう幅に上限を置き、あふれた文字は末尾を省く
        .frame(minWidth: 196, maxWidth: CandidateList.maxWidth, alignment: .leading)
        .fixedSize()
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(window.reading)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Theme.quiet)
                .lineLimit(1)
            Spacer(minLength: 12)
            if window.pageCount > 1 {
                PageDots(page: window.page, count: window.pageCount)
            }
        }
        .padding(.leading, CandidateView.textInset)
        .padding(.trailing, 14)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    private func row(label: Character, item: String, highlighted: Bool) -> some View {
        HStack(spacing: 0) {
            Text(String(label).uppercased())
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(highlighted ? Theme.onAccent.opacity(0.75) : Theme.quiet.opacity(0.8))
                .frame(width: CandidateView.textInset - 6)
            Text(item)
                .font(.system(size: 16, weight: highlighted ? .medium : .regular))
                .foregroundStyle(highlighted ? Theme.onAccent : Theme.ink)
                .lineLimit(1)
            Spacer(minLength: 16)
        }
        .frame(height: 30)
        .background {
            if highlighted {
                RoundedRectangle(cornerRadius: Theme.rowRadius)
                    .fill(Theme.accent)
                    .shadow(color: Theme.accent.opacity(0.22), radius: 4, y: 1.5)
                    .matchedGeometryEffect(id: "highlight", in: highlight)
            }
        }
    }

    /// 操作の案内。候補より目立たないよう、細い線の下に小さく置く
    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Theme.rule).frame(height: 0.5)
                .padding(.horizontal, 12)
            HStack(spacing: 12) {
                hint("⌃N", "次")
                hint("⌃P", "前")
                hint("⌃G", "閉じる")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, CandidateView.textInset)
            .padding(.trailing, 14)
            .padding(.top, 7)
            .padding(.bottom, 9)
        }
        .padding(.top, 6)
    }

    private func hint(_ key: String, _ action: String) -> some View {
        HStack(spacing: 3) {
            Text(key)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
            Text(action)
                .font(.system(size: 10))
        }
        .foregroundStyle(Theme.quiet.opacity(0.85))
    }
}

/// 候補のページの数と今のページ
struct PageDots: View {
    let page: Int
    let count: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Self.visible(page: page, count: count), id: \.self) { index in
                Capsule()
                    .fill(index == page ? Theme.accent : Theme.quiet.opacity(0.3))
                    .frame(width: index == page ? 12 : 5, height: 5)
            }
        }
        .animation(Theme.move, value: page)
    }

    static let limit = 8

    /// 点は 8 個までにし、今のページが入るように窓をずらす
    static func visible(page: Int, count: Int) -> Range<Int> {
        guard count > limit else { return 0..<count }
        let start = min(max(page - limit / 2, 0), count - limit)
        return start..<(start + limit)
    }
}
