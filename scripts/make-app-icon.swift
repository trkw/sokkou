// アプリのアイコン（AppIcon.icns）を作る。引数は出力先ディレクトリ。
// 紙の地に墨の「そ」、その下に朱の実線。日本語の文節に引く実線を、そのまま印にした
import AppKit

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("使い方: swift make-app-icon.swift <出力先>\n".utf8))
    exit(2)
}
let outDir = URL(fileURLWithPath: CommandLine.arguments[1])

func color(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

let paperTop = color(0xFBFAF6)
let paperBottom = color(0xEEEBE3)
let ink = color(0x1C1C1E)
let vermilion = color(0xC2410C)

/// 1024 の画布に描く。macOS のアイコンの格子どおり、824 四方の角丸の板を真ん中に置き、下に影を落とす
func draw(in canvas: CGFloat) {
    let unit = canvas / 1024
    let plate = NSRect(x: 100 * unit, y: 100 * unit, width: 824 * unit, height: 824 * unit)
    let radius = 185 * unit
    let shape = NSBezierPath(roundedRect: plate, xRadius: radius, yRadius: radius)

    // 板の影。小さい大きさでは濁るので、64 画素より大きいときだけ落とす
    if canvas > 64 {
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
        shadow.shadowBlurRadius = 18 * unit
        shadow.shadowOffset = NSSize(width: 0, height: -10 * unit)
        shadow.set()
        paperBottom.setFill()
        shape.fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    // 紙の地。上から下へわずかに暗くする
    NSGradient(starting: paperTop, ending: paperBottom)!.draw(in: shape, angle: -90)
    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    // 縁の内側にごく薄い線を引き、紙の厚みにする
    let rim = NSBezierPath(roundedRect: plate.insetBy(dx: 1.5 * unit, dy: 1.5 * unit), xRadius: radius - 1.5 * unit, yRadius: radius - 1.5 * unit)
    rim.lineWidth = 3 * unit
    NSColor.white.withAlphaComponent(0.7).setStroke()
    rim.stroke()
    NSGraphicsContext.restoreGraphicsState()

    // 墨の「そ」。明朝の太字があればそれを、無ければ system の太字を使う
    let font = NSFont(name: "HiraMinProN-W6", size: 100) ?? NSFont.systemFont(ofSize: 100, weight: .semibold)
    func glyph(_ size: CGFloat) -> NSAttributedString {
        NSAttributedString(string: "そ", attributes: [.font: font.withSize(size), .foregroundColor: ink])
    }
    let reference = glyph(100).boundingRect(with: .zero, options: [.usesDeviceMetrics])
    // 字の形の高さを板の 46% にする
    let size = 100 * plate.height * 0.46 / reference.height
    let text = glyph(size)
    let shapeRect = text.boundingRect(with: .zero, options: [.usesDeviceMetrics])
    let center = NSPoint(x: plate.midX, y: plate.minY + plate.height * 0.56)
    text.draw(with: NSRect(origin: NSPoint(x: center.x - shapeRect.midX, y: center.y - shapeRect.midY), size: .zero), options: [])

    // 朱の実線。字の下に、字より少し広く引く
    let lineWidth = max(plate.width * 0.44, shapeRect.width * 1.1)
    let thickness = max(2, 32 * unit)
    let line = NSRect(
        x: plate.midX - lineWidth / 2,
        y: center.y - shapeRect.height / 2 - plate.height * 0.085 - thickness,
        width: lineWidth,
        height: thickness
    )
    vermilion.setFill()
    NSBezierPath(roundedRect: line, xRadius: thickness / 2, yRadius: thickness / 2).fill()
}

func render(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    draw(in: CGFloat(pixels))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

// iconutil が読む形の iconset を作り、icns にまとめる
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon-\(getpid()).iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    try render(pixels: points).write(to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    try render(pixels: points * 2).write(to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", outDir.appendingPathComponent("AppIcon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
guard iconutil.terminationStatus == 0 else {
    FileHandle.standardError.write(Data("iconutil が失敗した\n".utf8))
    exit(1)
}
print("AppIcon.icns")
