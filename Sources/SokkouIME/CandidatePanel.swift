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
        // 設定の窓で形を変えたら、次に出すときから効かせる
        let style = CandidateStyle.current
        model.style = style
        model.window = window
        host.layoutSubtreeIfNeeded()
        // 候補の文字の左端を、選んでいる文節の左端にそろえる
        panel.place(size: host.fittingSize, below: line, leading: style.textInset)
        panel.appear()
    }

    func hide() {
        panel.orderOut(nil)
    }
}

@Observable
final class CandidateModel {
    var style = CandidateStyle.list
    var window: CandidateWindow?
}

struct CandidateView: View {
    let model: CandidateModel

    var body: some View {
        if let window = model.window {
            StyledCandidates(style: model.style, window: window)
        }
    }
}

/// 選んだ形で候補を描く。候補の窓、設定の見本、スナップショットで使う
struct StyledCandidates: View {
    let style: CandidateStyle
    let window: CandidateWindow

    var body: some View {
        switch style {
        case .list: CandidateList(window: window)
        case .strip: CandidateStrip(window: window)
        case .card: CandidateCard(window: window)
        }
    }
}

extension CandidateStyle {
    /// 窓の左端から候補の文字までの幅
    var textInset: CGFloat {
        switch self {
        case .list: CandidateList.textInset
        case .strip: CandidateStrip.textInset
        case .card: CandidateCard.textInset
        }
    }
}

extension CandidateWindow {
    /// 設定の見本とスナップショットに出す候補
    static let sample = CandidateWindow(
        reading: "かく",
        items: ["書く", "描く", "核", "角", "格", "閣", "欠く"],
        labels: Array("asdfjkl"),
        highlighted: 2,
        page: 0,
        pageCount: 2,
        annotations: [nil, "絵や図をかく", "ものごとの中心", nil, nil, nil, "不足する"]
    )

    /// 何ページ目かを「1 / 2」の形で。1 ページしかなければ nil
    var pageLabel: String? {
        pageCount > 1 ? "\(page + 1) / \(pageCount)" : nil
    }
}

/// 候補を選ぶキーの字
private func keyLabel(_ label: Character) -> String {
    String(label).uppercased()
}

// MARK: 案A 縦に並べる

/// 読み、候補、操作の案内を縦に並べる。選んでいる候補は薄い朱の地に、左に朱の印
struct CandidateList: View {
    static let maxWidth: CGFloat = 420
    /// 外の余白 6、行の内の余白 10、キーの字 14、間 10
    static let textInset: CGFloat = 40

    let window: CandidateWindow
    @Namespace var highlight

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            VStack(spacing: 1) {
                ForEach(Array(window.items.enumerated()), id: \.offset) { index, item in
                    row(label: window.labels[index], item: item, annotation: window.annotation(at: index), highlighted: index == window.highlighted)
                }
            }
            .padding(.horizontal, 6)
            .animation(Theme.move, value: window.highlighted)
            footer
        }
        // 長い読みや候補でも画面からはみ出さないよう幅に上限を置き、あふれた文字は末尾を省く
        .frame(minWidth: 220, maxWidth: CandidateList.maxWidth, alignment: .leading)
        .fixedSize()
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(window.reading)
                .font(.system(size: 11.5, weight: .medium))
                .tracking(0.6)
                .foregroundStyle(Theme.quiet)
                .lineLimit(1)
            Spacer(minLength: 12)
            if let page = window.pageLabel {
                Text(page)
                    .font(.system(size: 10.5).monospacedDigit())
                    .foregroundStyle(Theme.quiet)
            }
        }
        .padding(.leading, Self.textInset)
        .padding(.trailing, 16)
        .padding(.top, 11)
        .padding(.bottom, 6)
    }

    private func row(label: Character, item: String, annotation: String?, highlighted: Bool) -> some View {
        HStack(spacing: 10) {
            Text(keyLabel(label))
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(highlighted ? Theme.accent : Theme.quiet.opacity(0.8))
                .frame(width: 14)
            Text(item)
                .font(.system(size: 16, weight: highlighted ? .semibold : .regular))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .layoutPriority(1)
            Spacer(minLength: 12)
            // SKK 辞書の注釈。候補より小さく薄く右に寄せ、あふれたら注釈の方を省く
            if let annotation {
                Text(annotation)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.quiet)
                    .lineLimit(1)
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 10)
        .frame(height: 32)
        .background {
            if highlighted {
                RoundedRectangle(cornerRadius: Theme.rowRadius, style: .continuous)
                    .fill(Theme.accent.opacity(0.12))
                    .overlay(alignment: .leading) {
                        Capsule().fill(Theme.accent).frame(width: 2.5).padding(.vertical, 8)
                    }
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
                hint("⌃G", "もどす")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, Self.textInset)
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

// MARK: 案B 横一行

/// 候補を横一行に並べる。選んでいる候補には、文節と同じ朱の下線を引く。注釈は選んでいる候補の分だけ下に出す
struct CandidateStrip: View {
    static let maxWidth: CGFloat = 640
    /// 外の余白 6、候補の内の余白 9、キーの字 9、間 5
    static let textInset: CGFloat = 29

    let window: CandidateWindow
    @Namespace var highlight

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                ForEach(Array(window.items.enumerated()), id: \.offset) { index, item in
                    cell(label: window.labels[index], item: item, highlighted: index == window.highlighted)
                }
                if let page = window.pageLabel {
                    Rectangle().fill(Theme.rule).frame(width: 0.5, height: 16)
                        .padding(.horizontal, 8)
                    Text(page)
                        .font(.system(size: 10.5).monospacedDigit())
                        .foregroundStyle(Theme.quiet)
                        .fixedSize()
                        .padding(.trailing, 6)
                }
            }
            .animation(Theme.move, value: window.highlighted)
            if let annotation = window.annotation(at: window.highlighted) {
                Text(annotation)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.quiet)
                    .lineLimit(1)
                    .padding(.leading, Self.textInset - 6)
                    .padding(.bottom, 6)
            }
        }
        .padding(6)
        .frame(maxWidth: Self.maxWidth, alignment: .leading)
        .fixedSize()
    }

    private func cell(label: Character, item: String, highlighted: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(keyLabel(label))
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(highlighted ? Theme.accent : Theme.quiet.opacity(0.8))
                .frame(width: 9)
            Text(item)
                .font(.system(size: 16, weight: highlighted ? .semibold : .regular))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.top, 6)
        .padding(.bottom, 9)
        .overlay(alignment: .bottom) {
            if highlighted {
                Capsule().fill(Theme.accent)
                    .frame(height: 2)
                    .padding(.horizontal, 9)
                    .padding(.bottom, 3)
                    .matchedGeometryEffect(id: "highlight", in: highlight)
            }
        }
    }
}

// MARK: 案C 札

/// 左に候補を明朝で縦に並べ、右に選んでいる候補を大きく、読みと注釈を添えて出す
struct CandidateCard: View {
    /// 列の外の余白 8、行の内の余白 8、キーの札 18、間 10
    static let textInset: CGFloat = 44
    static let paneWidth: CGFloat = 176

    let window: CandidateWindow
    @Namespace var highlight

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(Array(window.items.enumerated()), id: \.offset) { index, item in
                    row(label: window.labels[index], item: item, highlighted: index == window.highlighted)
                }
            }
            .padding(8)
            .frame(minWidth: 132, maxWidth: 240, alignment: .leading)
            .overlay(alignment: .trailing) {
                Rectangle().fill(Theme.rule).frame(width: 0.5)
            }
            .animation(Theme.move, value: window.highlighted)
            pane
        }
        .fixedSize()
    }

    private func row(label: Character, item: String, highlighted: Bool) -> some View {
        HStack(spacing: 10) {
            Text(keyLabel(label))
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(highlighted ? Theme.onAccent : Theme.quiet)
                .frame(width: 18, height: 18)
                .background {
                    if highlighted {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Theme.accent)
                            .matchedGeometryEffect(id: "highlight", in: highlight)
                    }
                }
                .overlay {
                    if !highlighted {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(Theme.border, lineWidth: 0.5)
                    }
                }
            Text(item)
                .font(Self.mincho(size: 18, bold: highlighted))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 8)
        .frame(height: 33)
    }

    /// 右の欄。読み、選んでいる候補、注釈、ページ
    private var pane: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(window.reading)
                .font(.system(size: 11, weight: .medium))
                .tracking(0.8)
                .foregroundStyle(Theme.quiet)
                .lineLimit(1)
            if window.items.indices.contains(window.highlighted) {
                Text(window.items[window.highlighted])
                    .font(Self.mincho(size: 40, bold: false))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
            }
            if let annotation = window.annotation(at: window.highlighted) {
                Text(annotation)
                    .font(.system(size: 12))
                    .lineSpacing(3)
                    .foregroundStyle(Theme.ink.opacity(0.8))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 10)
            HStack(spacing: 6) {
                if let page = window.pageLabel {
                    Text(page).monospacedDigit()
                }
                Text("⌃N 次")
            }
            .font(.system(size: 10.5))
            .foregroundStyle(Theme.quiet)
        }
        .padding(16)
        .frame(width: Self.paneWidth, alignment: .topLeading)
    }

    /// ヒラギノ明朝。無い環境では system の明朝体の指定に任せる
    static func mincho(size: CGFloat, bold: Bool) -> Font {
        let name = bold ? "HiraMinProN-W6" : "HiraMinProN-W3"
        if NSFont(name: name, size: size) != nil {
            return .custom(name, size: size)
        }
        return .system(size: size, weight: bold ? .semibold : .regular, design: .serif)
    }
}
