// dmg の窓の背景を作る。引数は出力先（.tiff）。1 倍と 2 倍の画素を 1 つの TIFF にまとめる。
// 窓は 640×400pt。真ん中に sokkou だけを置き（scripts/dmg-settings.py の icon_locations と合わせる）、
// その下に「ダブルクリックで、入ります」と添える。地は紙の色、線画は罫の色（デザイン案 v2）
import AppKit

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("使い方: swift make-dmg-background.swift <出力先.tiff>\n".utf8))
    exit(2)
}
let output = URL(fileURLWithPath: CommandLine.arguments[1])

let size = NSSize(width: 640, height: 400)
let paper = NSColor(srgbRed: 0xF6 / 255, green: 0xF4 / 255, blue: 0xEF / 255, alpha: 1)
let ink = NSColor(srgbRed: 0x1E / 255, green: 0x1C / 255, blue: 0x19 / 255, alpha: 1)
let muted = NSColor(srgbRed: 0x6B / 255, green: 0x67 / 255, blue: 0x5F / 255, alpha: 1)
let rule = NSColor(srgbRed: 0xE2 / 255, green: 0xDE / 255, blue: 0xD3 / 255, alpha: 1)

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

    // 下のほうに、ゆるい線画。上端からの距離で書くため、y は size.height から引く
    let wave = NSBezierPath()
    wave.move(to: NSPoint(x: 40, y: size.height - 366))
    wave.curve(to: NSPoint(x: 210, y: size.height - 334), controlPoint1: NSPoint(x: 120, y: size.height - 366), controlPoint2: NSPoint(x: 150, y: size.height - 334))
    wave.curve(to: NSPoint(x: 370, y: size.height - 358), controlPoint1: NSPoint(x: 270, y: size.height - 334), controlPoint2: NSPoint(x: 300, y: size.height - 364))
    wave.curve(to: NSPoint(x: 600, y: size.height - 332), controlPoint1: NSPoint(x: 450, y: size.height - 350), controlPoint2: NSPoint(x: 520, y: size.height - 314))
    wave.lineWidth = 1.5
    wave.lineCapStyle = .round
    rule.setStroke()
    wave.stroke()
    for (x, y, width) in [(100.0, 380.0, 40.0), (510.0, 374.0, 30.0)] {
        let dash = NSBezierPath()
        dash.move(to: NSPoint(x: x, y: size.height - y))
        dash.line(to: NSPoint(x: x + width, y: size.height - y))
        dash.lineWidth = 1.5
        dash.lineCapStyle = .round
        dash.stroke()
    }

    // アイコンは中心 (320, 160)、128pt。その下の名前は Finder が書く
    draw("ダブルクリックで、入ります", x: size.width / 2, top: 262, font: font(16, .semibold), color: ink, kern: 0.6)
    draw("アプリケーションに移さなくて大丈夫。入れたら、この窓は閉じてください",
         x: size.width / 2, top: 292, font: font(11.5, .regular), color: muted)
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
