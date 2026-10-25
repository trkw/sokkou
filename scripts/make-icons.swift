// 入力メニューのアイコンを作る。引数は出力先ディレクトリ
// macOS 同梱の日本語入力（Hiragana.tiff）と同じ大きさにする: 16pt 四方、1 倍と 2 倍の画素のテンプレート画像。
// 日本語は角丸の四角を塗って文字を抜き、英数は角丸の枠の中に文字を書く（デザイン案 v2 の c: 日本語だけ塗る）
import AppKit

let icons: [(name: String, glyph: String, filled: Bool)] = [("japanese", "そ", true), ("roman", "A", false)]
let pointSize: CGFloat = 16
let scales: [CGFloat] = [1, 2]
let cornerRadius: CGFloat = 3.5
/// 英数の枠の線の太さ。メニューバーのほかのアイコンの線に合わせる
let frameWidth: CGFloat = 1.3
/// 文字の形の縦横の大きい方が四角に占める割合。同梱の Hiragana.tiff の「あ」に合わせた
let glyphRatio: CGFloat = 0.56

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("使い方: swift make-icons.swift <出力先>\n".utf8))
    exit(2)
}
let outDir = URL(fileURLWithPath: CommandLine.arguments[1])

func render(_ glyph: String, filled: Bool, scale: CGFloat) -> NSBitmapImageRep {
    let pixels = Int(pointSize * scale)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: pointSize, height: pointSize)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let box = NSRect(x: 0, y: 0, width: pointSize, height: pointSize)
    if filled {
        NSColor.black.setFill()
        NSBezierPath(roundedRect: box, xRadius: cornerRadius, yRadius: cornerRadius).fill()
    } else {
        let inset = frameWidth / 2
        let frame = NSBezierPath(
            roundedRect: box.insetBy(dx: inset, dy: inset), xRadius: cornerRadius - inset, yRadius: cornerRadius - inset
        )
        frame.lineWidth = frameWidth
        NSColor.black.setStroke()
        frame.stroke()
    }

    // 文字の実際の形（ベースライン基準の外接矩形）で大きさを決め、四角の中央に置く
    func attributed(_ size: CGFloat) -> NSAttributedString {
        NSAttributedString(string: glyph, attributes: [
            .font: NSFont.systemFont(ofSize: size, weight: .semibold),
            .foregroundColor: NSColor.black,
        ])
    }
    let reference: CGFloat = 100
    let referenceInk = attributed(reference).boundingRect(with: .zero, options: [.usesDeviceMetrics])
    // 枠では線の分だけ文字を小さくし、線に触れないようにする
    let ratio = filled ? glyphRatio : glyphRatio * 0.9
    let text = attributed(reference * pointSize * ratio / max(referenceInk.width, referenceInk.height))
    let ink = text.boundingRect(with: .zero, options: [.usesDeviceMetrics])
    let baseline = NSPoint(x: box.midX - ink.midX, y: box.midY - ink.midY)
    // 塗った四角では文字の形を透明に抜き、枠では文字をそのまま書く。options に usesLineFragmentOrigin を入れないと、rect の原点はベースラインになる
    if filled {
        NSGraphicsContext.current?.compositingOperation = .destinationOut
    }
    text.draw(with: NSRect(origin: baseline, size: .zero), options: [])
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

for (name, glyph, filled) in icons {
    let reps = scales.map { render(glyph, filled: filled, scale: $0) }
    guard let tiff = NSBitmapImageRep.tiffRepresentationOfImageReps(in: reps) else {
        FileHandle.standardError.write(Data("\(name) のアイコンを作れない\n".utf8))
        exit(1)
    }
    try tiff.write(to: outDir.appendingPathComponent("\(name).tiff"))
    print("\(name).tiff")
}
