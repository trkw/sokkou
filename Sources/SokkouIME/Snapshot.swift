import AppKit
import SokkouCore
import SwiftUI

/// 候補の窓とモードの札を、明るい外観と暗い外観の PNG に書き出す。入力メソッドを入れずに見た目を確かめるため。
/// ガラスは画像にならないので、近い色の板で代わりに描く
enum Snapshot {
    static func write(to path: String) -> Int32 {
        let folder = URL(fileURLWithPath: path, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for (name, appearance, scheme) in [
                ("light", NSAppearance.Name.aqua, ColorScheme.light),
                ("dark", NSAppearance.Name.darkAqua, ColorScheme.dark),
            ] {
                var failure: Error?
                NSAppearance(named: appearance)!.performAsCurrentDrawingAppearance {
                    do {
                        let file = folder.appendingPathComponent("ui-\(name).png")
                        try render(Board().environment(\.colorScheme, scheme), to: file)
                        print(file.path)
                        for tab in SettingsTab.allCases {
                            let model = SettingsModel()
                            model.tab = tab
                            // 片方だけ足した状態にして、両方の見た目を確かめる
                            model.enabled = [.japanese]
                            let page = folder.appendingPathComponent("settings-\(tab.id)-\(name).png")
                            try render(SettingsView(model: model).environment(\.colorScheme, scheme), to: page)
                            print(page.path)
                        }
                    } catch {
                        failure = error
                    }
                }
                if let failure { throw failure }
            }
            return 0
        } catch {
            print("書き出せない: \(error)")
            return 1
        }
    }

    private static func render(_ view: some View, to file: URL) throws {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:])
        else { throw InstallError("画像にできない") }
        try png.write(to: file)
    }

    /// 入力欄の 1 行とその下の候補の窓を、候補の窓の形ごとに並べ、横にアイコンとモードの札を置いた見本
    struct Board: View {
        let window = CandidateWindow.sample

        var body: some View {
            HStack(alignment: .top, spacing: 48) {
                ForEach(CandidateStyle.allCases) { style in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(style.title)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.quiet)
                            .padding(.bottom, 8)
                        HStack(spacing: 0) {
                            Text("今日は ").foregroundStyle(Theme.ink)
                            Text("GitHub").underline(pattern: .dot).foregroundStyle(Theme.ink)
                            Text(" で").underline().foregroundStyle(Theme.ink)
                            Text("核").underline(color: Theme.accent).fontWeight(.semibold).foregroundStyle(Theme.ink)
                        }
                        .font(.system(size: 17))
                        StyledCandidates(style: style, window: window)
                            .background(glass(radius: Theme.windowRadius))
                            .padding(.leading, 70 - style.textInset)
                    }
                }
                VStack(alignment: .leading, spacing: 12) {
                    // アプリのアイコン。Finder・dmg・通知に出る
                    Image(nsImage: Bundle.main.image(forResource: "AppIcon") ?? NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath))
                        .resizable()
                        .frame(width: 128, height: 128)
                    HStack(spacing: 10) {
                        ForEach([InputMode.hiragana, .katakana, .halfwidthKatakana, .ascii, .fullwidthRoman], id: \.self) { mode in
                            ModeGlyph(mode: mode)
                                .background(glass(radius: BadgeView.radius))
                        }
                    }
                }
            }
            .padding(36)
            .background(Theme.ground)
        }

        private func glass(radius: CGFloat) -> some View {
            PaperPlate(radius: radius)
        }
    }
}
