import AppKit
import SwiftUI

/// 打っている途中の表示が打った読みと合わないときに、未確定の文字列の下に出す小さな窓（tugime の RewriteWarning と同じ知らせ）。
/// 決まった文言だけを出し、ほかの知らせは載せない
final class RewriteWarning {
    static let message = "入力と違う変換"
    static let radius: CGFloat = 8

    private let panel = FloatingPanel()
    private let host = NSHostingView(rootView: WarningView())

    init() {
        host.sizingOptions = [.intrinsicContentSize]
        panel.setGlassContent(host, cornerRadius: Self.radius)
    }

    /// 行の矩形 line の下に出す。アプリが位置を返さない（無限大や高さ 0）ときは出さない
    func show(below line: NSRect) {
        guard line.minX.isFinite, line.minY.isFinite, line.height > 0 else {
            hide()
            return
        }
        host.layoutSubtreeIfNeeded()
        panel.place(size: host.fittingSize, below: line)
        panel.appear()
    }

    func hide() {
        panel.orderOut(nil)
    }
}

private struct WarningView: View {
    var body: some View {
        Text(RewriteWarning.message)
            .font(.system(size: 13))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .fixedSize()
    }
}
