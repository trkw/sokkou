// dmg の窓の背景を作る。引数は出力先（.tiff）。1 倍と 2 倍の画素を 1 つの TIFF にまとめる。
// 窓は 640×400pt。左に sokkou、右に「はじめに」を置き（scripts/dmg-settings.py の icon_locations と合わせる）、
// 地は紙の色、差し色は朱一色（Theme と同じ）
import AppKit

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("使い方: swift make-dmg-background.swift <出力先.tiff>\n".utf8))
    exit(2)
}
let output = URL(fileURLWithPath: CommandLine.arguments[1])

let size = NSSize(width: 640, height: 400)
let paper = NSColor(srgbRed: 0xF5 / 255, green: 0xF4 / 255, blue: 0xF0 / 255, alpha: 1)
let ink = NSColor(srgbRed: 0x1C / 255, green: 0x19 / 255, blue: 0x17 / 255, alpha: 1)
let muted = NSColor(srgbRed: 0x78 / 255, green: 0x71 / 255, blue: 0x6C / 255, alpha: 1)
let rule = NSColor(srgbRed: 0xE7 / 255, green: 0xE5 / 255, blue: 0xE4 / 255, alpha: 1)
let vermilion = NSColor(srgbRed: 0xC2 / 255, green: 0x41 / 255, blue: 0x0C / 255, alpha: 1)

func font(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
    let name = weight == .regular ? "HiraginoSans-W3" : "HiraginoSans-W6"
    return NSFont(name: name, size: size) ?? .systemFont(ofSize: size, weight: weight)
}

/// 上端からの距離 top に、横の中心を x に置いて書く（Finder の座標は左上が原点、AppKit は左下が原点）
func draw(_ text: String, x: CGFloat, top: CGFloat, font: NSFont, color: NSColor, kern: CGFloat = 0) {
    let string = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color, .kern: kern])
    let bounds = string.size()
    string.draw(at: NSPoint(x: x - bounds.width / 2, y: size.height - top - bounds.height))
}

func render(scale: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    paper.setFill()
    NSRect(origin: .zero, size: size).fill()

    // 見出し: 名前と一言
    draw("sokkou", x: size.width / 2, top: 44, font: font(22, .semibold), color: ink, kern: 1.5)
    draw("即効 — SKK の手触りで、打てばそのまま変換", x: size.width / 2, top: 78, font: font(12, .regular), color: muted)

    // アイコンの下の名前は Finder が書く。アイコンは中心 (200, 190) と (440, 190)、112pt
    // 左のアイコンの下に朱の短い線を引き、ここを開くと示す
    vermilion.setFill()
    NSBezierPath(roundedRect: NSRect(x: 200 - 18, y: size.height - 282, width: 36, height: 3), xRadius: 1.5, yRadius: 1.5).fill()
    draw("開くと入ります", x: 200, top: 292, font: font(12, .semibold), color: vermilion)
    draw("困ったときに", x: 440, top: 292, font: font(12, .regular), color: muted)

    // 下の帯: 公証していないので最初の 1 回だけ要る手順
    rule.setFill()
    NSRect(x: 40, y: 84, width: size.width - 80, height: 1).fill()
    draw("「開けません」と出たら", x: size.width / 2, top: 330, font: font(11, .semibold), color: ink)
    draw("システム設定 → プライバシーとセキュリティ → 下の「このまま開く」を押して、もう一度開く",
         x: size.width / 2, top: 350, font: font(11, .regular), color: muted)
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let image = NSImage(size: size)
image.addRepresentation(render(scale: 1))
image.addRepresentation(render(scale: 2))
guard let tiff = image.tiffRepresentation(using: .lzw, factor: 0) else {
    FileHandle.standardError.write(Data("TIFF にできない\n".utf8))
    exit(1)
}
try tiff.write(to: output)
print("== 背景 \(output.path)")
