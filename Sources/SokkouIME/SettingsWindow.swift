import AppKit
import Carbon
import SwiftUI

/// 入力メニューの「設定…」で開く窓。入力ソースの追加の具合、変換と更新の設定、キーの早見表、版の情報を見せる。
/// 入力メソッドは Dock に出ないプロセスなので、開いている間だけ前に出られるようにする
final class SettingsWindow: NSObject, NSWindowDelegate {
    static let shared = SettingsWindow()

    private let model = SettingsModel()
    private var window: NSWindow?

    func show(_ tab: SettingsTab = .general) {
        model.tab = tab
        model.refresh()
        let window = window ?? makeWindow()
        self.window = window
        NSApplication.shared.setActivationPolicy(.accessory)
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: SettingsView.size),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "sokkou"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.contentView = NSHostingView(rootView: SettingsView(model: model))
        window.center()
        window.delegate = self
        return window
    }

    func windowDidBecomeKey(_ notification: Notification) {
        // システム設定で入力ソースを足して戻ってきたら、すぐに表示を直す
        model.refresh()
    }

    func windowWillClose(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.prohibited)
    }
}

enum SettingsTab: String, CaseIterable, Identifiable {
    case general = "一般"
    case appearance = "見た目"
    case skk = "SKK"
    case keys = "キー"
    case about = "情報"

    var id: Self { self }
}

@Observable
final class SettingsModel {
    var tab: SettingsTab = .general
    var learns = Settings.learns {
        didSet { Settings.learns = learns }
    }
    var autoUpdates = Settings.autoUpdates {
        didSet { Settings.autoUpdates = autoUpdates }
    }
    var candidateStyle = CandidateStyle.current {
        didSet { CandidateStyle.current = candidateStyle }
    }
    /// 使っている SKK の手触りの機能
    var features = Set(SKKFeature.allCases.filter(\.isOn)) {
        didSet {
            for feature in SKKFeature.allCases { feature.isOn = features.contains(feature) }
        }
    }
    /// 有効になっている sokkou の入力ソース
    var enabled: Set<InputSourceRow> = []
    /// macOS が知っている sokkou の入力ソース。入れ替えで増えた入力ソースは、ログインし直すまで macOS に知られない
    var installed: Set<InputSourceRow> = []
    var forgotten = false

    func refresh() {
        learns = Settings.learns
        autoUpdates = Settings.autoUpdates
        candidateStyle = CandidateStyle.current
        features = Set(SKKFeature.allCases.filter(\.isOn))
        enabled = InputSourceRow.enabled()
        installed = InputSourceRow.installed()
    }

    func isOn(_ feature: SKKFeature) -> Binding<Bool> {
        Binding(
            get: { self.features.contains(feature) },
            set: { on in
                if on { self.features.insert(feature) } else { self.features.remove(feature) }
            }
        )
    }

    func forget() {
        sharedLearning.forget()
        forgotten = true
    }
}

/// 利用者がシステム設定で足す 2 つの入力ソース
enum InputSourceRow: String, CaseIterable {
    case japanese = "Japanese"
    case roman = "Roman"

    var title: String {
        switch self {
        case .japanese: "sokkou (日本語)"
        case .roman: "sokkou (英数)"
        }
    }

    var detail: String {
        switch self {
        case .japanese: "ひらがな・カタカナ・自動変換"
        case .roman: "C-l で入り、C-j で日本語に戻る"
        }
    }

    /// sokkou の入力ソースのうち、macOS で有効になっているもの。
    /// TISCreateInputSourceList の「有効なものだけ」は入力メソッドのモードを有効でなくても返すことがあるので、
    /// 入れてあるものをすべて取り、1 つずつ有効かを確かめる
    static func enabled() -> Set<InputSourceRow> {
        Set(sources().compactMap { row, source in
            property(source, kTISPropertyInputSourceIsEnabled) as? Bool == true ? row : nil
        })
    }

    static func installed() -> Set<InputSourceRow> {
        Set(sources().map(\.row))
    }

    /// 日本語か英数のどちらかが有効なら、足りないほうも有効にする。
    /// 入力ソースを 1 つにまとめていた版から入れ替えると、英数が入力メニューに出ないまま残るため。起動時と設定の窓から呼ぶ
    @discardableResult
    static func enableMissing() -> Bool {
        let all = sources()
        guard all.contains(where: { property($0.source, kTISPropertyInputSourceIsEnabled) as? Bool == true }) else { return false }
        var changed = false
        for (_, source) in all where property(source, kTISPropertyInputSourceIsEnabled) as? Bool != true {
            changed = TISEnableInputSource(source) == noErr || changed
        }
        return changed
    }

    /// 入れてある sokkou の入力ソース。有効でないものも含む
    private static func sources() -> [(row: InputSourceRow, source: TISInputSource)] {
        guard let bundleID = Bundle.main.bundleIdentifier else { return [] }
        let filter = [kTISPropertyBundleID as String: bundleID] as CFDictionary
        guard let list = TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource] else { return [] }
        return list.compactMap { source in
            guard let id = property(source, kTISPropertyInputSourceID) as? String,
                  let row = allCases.first(where: { id == "\(bundleID).\($0.rawValue)" })
            else { return nil }
            return (row, source)
        }
    }

    private static func property(_ source: TISInputSource, _ key: CFString) -> Any? {
        guard let raw = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<AnyObject>.fromOpaque(raw).takeUnretainedValue()
    }

    static func openKeyboardSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!)
    }
}

// MARK: 窓の中身

struct SettingsView: View {
    static let size = NSSize(width: 620, height: 580)

    @Bindable var model: SettingsModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                ForEach(SettingsTab.allCases) { tab in
                    TabPill(title: tab.rawValue, selected: model.tab == tab) { model.tab = tab }
                }
            }
            .padding(.top, 14)
            .padding(.bottom, 12)
            Rectangle().fill(Theme.rule).frame(height: 0.5)
            Group {
                switch model.tab {
                case .general: GeneralPage(model: model)
                case .appearance: AppearancePage(model: model)
                case .skk: SKKPage(model: model)
                case .keys: KeysPage()
                case .about: AboutPage()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(Theme.ground)
        .animation(Theme.move, value: model.tab)
    }
}

private struct TabPill: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12.5, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? Theme.ink : Theme.quiet)
                .padding(.horizontal, 14)
                .padding(.vertical, 5)
                .background {
                    if selected {
                        Capsule().fill(Theme.surface)
                            .overlay(Capsule().strokeBorder(Theme.border, lineWidth: 0.5))
                            .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// 見出しと、白い板に載せた行の並び
struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.quiet)
                .padding(.leading, 4)
            VStack(spacing: 0) {
                content
            }
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.border, lineWidth: 0.5))
        }
    }
}

/// 板の中の 1 行。上の行との間に細い線を引く
struct SettingsRow<Accessory: View>: View {
    let title: String
    var detail: String? = nil
    var first = false
    @ViewBuilder let accessory: Accessory

    var body: some View {
        VStack(spacing: 0) {
            if !first {
                Rectangle().fill(Theme.rule).frame(height: 0.5).padding(.leading, 14)
            }
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.ink)
                    if let detail {
                        Text(detail)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.quiet)
                    }
                }
                Spacer(minLength: 12)
                accessory
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }
}

private struct GeneralPage: View {
    @Bindable var model: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsSection(title: "入力ソース") {
                ForEach(Array(InputSourceRow.allCases.enumerated()), id: \.element) { index, row in
                    SettingsRow(title: row.title, detail: row.detail, first: index == 0) {
                        SourceStatus(added: model.enabled.contains(row))
                    }
                }
                if model.installed.count < InputSourceRow.allCases.count {
                    SettingsRow(title: "ログインし直してください", detail: "入れ替えで足した入力ソースは、macOS がログインし直したときに読み込みます") {
                        EmptyView()
                    }
                } else if model.enabled.count < InputSourceRow.allCases.count {
                    if model.enabled.isEmpty {
                        SettingsRow(title: "キーボードの設定で足す", detail: "入力ソース → 編集 → ＋ → 日本語 から、2 つとも選びます") {
                            Button("開く") { InputSourceRow.openKeyboardSettings() }
                                .buttonStyle(PaperButtonStyle(prominent: true))
                        }
                    } else {
                        SettingsRow(title: "足りない入力ソースを足す", detail: "英数と日本語の両方を入力メニューに出します") {
                            Button("足す") {
                                InputSourceRow.enableMissing()
                                model.refresh()
                            }
                            .buttonStyle(PaperButtonStyle(prominent: true))
                        }
                    }
                }
            }
            SettingsSection(title: "変換") {
                SettingsRow(title: "選んだ候補を覚える", detail: "次に同じ読みを打ったとき、C-n 1 回で出す", first: true) {
                    Toggle("", isOn: $model.learns).toggleStyle(PaperToggleStyle())
                }
                SettingsRow(title: "覚えた候補を忘れる", detail: model.forgotten ? "忘れました" : "覚えた読みと候補をすべて消す") {
                    Button("忘れる") { model.forget() }
                        .buttonStyle(PaperButtonStyle())
                        .disabled(model.forgotten)
                }
            }
            if Updater.isAvailable {
                SettingsSection(title: "更新") {
                    SettingsRow(title: "新しいリリースを自動で入れる", detail: "2 分打たなかったときに入れ替える", first: true) {
                        Toggle("", isOn: $model.autoUpdates).toggleStyle(PaperToggleStyle())
                    }
                    SettingsRow(title: "いまの版", detail: Updater.build) {
                        Button("最新版に更新") { Updater.install() }
                            .buttonStyle(PaperButtonStyle())
                    }
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 22)
    }
}

/// 候補の窓の形を選ぶ。下に選んだ形の見本を出す
private struct AppearancePage: View {
    @Bindable var model: SettingsModel

    /// 窓に収まるよう、候補を 4 つにした見本
    static let sample = CandidateWindow(
        reading: "かく",
        items: ["書く", "描く", "核", "角"],
        labels: Array("asdf"),
        highlighted: 2,
        page: 0,
        pageCount: 3,
        annotations: [nil, "絵や図をかく", "ものごとの中心", nil]
    )

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsSection(title: "候補の窓") {
                ForEach(Array(CandidateStyle.allCases.enumerated()), id: \.element) { index, style in
                    Button {
                        model.candidateStyle = style
                    } label: {
                        SettingsRow(title: style.title, detail: style.detail, first: index == 0) {
                            Choice(selected: model.candidateStyle == style)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(model.candidateStyle == style ? .isSelected : [])
                }
            }
            VStack(alignment: .leading, spacing: 7) {
                Text("見本")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.quiet)
                    .padding(.leading, 4)
                StyledCandidates(style: model.candidateStyle, window: Self.sample)
                    .background(PaperPlate(radius: Theme.windowRadius))
                    .padding(.top, 4)
                    .frame(maxWidth: .infinity)
                    .animation(Theme.move, value: model.candidateStyle)
            }
            Text("変えると、次に候補を出したときから効きます")
                .font(.system(size: 11))
                .foregroundStyle(Theme.quiet)
                .padding(.leading, 4)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 22)
    }
}

/// 選べるものの印。選んでいれば朱の丸
private struct Choice: View {
    let selected: Bool

    var body: some View {
        ZStack {
            Circle().strokeBorder(selected ? Theme.accent : Theme.quiet.opacity(0.4), lineWidth: 1.5)
            if selected {
                Circle().fill(Theme.accent).padding(4.5)
            }
        }
        .frame(width: 18, height: 18)
        .animation(Theme.move, value: selected)
    }
}

/// SKK の手触りの機能を 1 つずつ切り替える
private struct SKKPage: View {
    @Bindable var model: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsSection(title: "SKK の手触り") {
                ForEach(Array(SKKFeature.allCases.enumerated()), id: \.element) { index, feature in
                    SettingsRow(title: feature.title, detail: feature.detail, first: index == 0) {
                        Toggle("", isOn: model.isOn(feature)).toggleStyle(PaperToggleStyle())
                    }
                }
            }
            Text("自動変換と ; の ▽ はそのままに、SKK の操作を足します。切り替えはすぐに効きます")
                .font(.system(size: 11))
                .foregroundStyle(Theme.quiet)
                .padding(.leading, 4)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 22)
    }
}

/// 入力ソースを足してあるか。足してあれば朱の印、まだなら薄い文字
private struct SourceStatus: View {
    let added: Bool

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(added ? Theme.accent : Theme.quiet.opacity(0.35))
                .frame(width: 7, height: 7)
            Text(added ? "追加済み" : "まだ")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(added ? Theme.ink : Theme.quiet)
        }
    }
}

// MARK: キーの早見表

private struct KeysPage: View {
    struct Entry: Identifiable {
        let keys: [String]
        let action: String
        var id: String { action }
    }

    static let groups: [(title: String, entries: [Entry])] = [
        ("モード", [
            Entry(keys: ["⌃J"], action: "ひらがな"),
            Entry(keys: ["⌃L"], action: "英数"),
            Entry(keys: ["⌃K"], action: "カタカナにする"),
            Entry(keys: ["⌃Q"], action: "半角カナ"),
            Entry(keys: ["⌃⇧L"], action: "全角英数"),
        ]),
        ("打っている途中", [
            Entry(keys: ["⏎"], action: "確定"),
            Entry(keys: ["⇧Space"], action: "文節を選んで直す"),
            Entry(keys: ["⌃F", "⌃B"], action: "区切りを伸ばす・縮める"),
            Entry(keys: ["⌃G"], action: "かなに戻す・取り消す"),
            Entry(keys: [";"], action: "自分で区切る（▽）"),
            Entry(keys: ["⇥"], action: "読みを補完する"),
            Entry(keys: ["/"], action: "英字の読みで辞書を引く（abbrev）"),
            Entry(keys: ["⌃/"], action: "確定した直後に、選び直す"),
        ]),
        ("候補を選ぶ", [
            Entry(keys: ["⌃N", "⌃P"], action: "次・前の候補"),
            Entry(keys: ["x"], action: "▼ で前の候補"),
            Entry(keys: ["A", "S", "D", "F"], action: "窓の候補を選ぶ"),
            Entry(keys: ["⇧⏎"], action: "選んでいる文節まで確定"),
            Entry(keys: ["⇧X"], action: "候補を消す"),
            Entry(keys: ["登録…"], action: "最後の候補で単語を登録"),
        ]),
    ]

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 20) {
                group(Self.groups[0])
                group(Self.groups[2])
            }
            group(Self.groups[1])
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 22)
    }

    private func group(_ group: (title: String, entries: [Entry])) -> some View {
        SettingsSection(title: group.title) {
            ForEach(Array(group.entries.enumerated()), id: \.element.id) { index, entry in
                VStack(spacing: 0) {
                    if index > 0 {
                        Rectangle().fill(Theme.rule).frame(height: 0.5).padding(.leading, 12)
                    }
                    HStack(spacing: 10) {
                        HStack(spacing: 3) {
                            ForEach(entry.keys, id: \.self) { Keycap(text: $0) }
                        }
                        .frame(width: 78, alignment: .leading)
                        Text(entry.action)
                            .font(.system(size: 12))
                            .lineLimit(1)
                            .fixedSize()
                            .foregroundStyle(Theme.ink)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: 情報

private struct AboutPage: View {
    var body: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 10)
            Image(nsImage: Bundle.main.image(forResource: "AppIcon") ?? NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath))
                .resizable()
                .frame(width: 112, height: 112)
            VStack(spacing: 4) {
                Text("sokkou")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text(Updater.build)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(Theme.quiet)
            }
            Text("SKK の手触りで、打てばそのまま変換される日本語入力")
                .font(.system(size: 13))
                .foregroundStyle(Theme.ink)
            HStack(spacing: 8) {
                Button("GitHub") { open("https://github.com/trkw/sokkou") }
                    .buttonStyle(PaperButtonStyle())
                Button("不具合を知らせる") { open("https://github.com/trkw/sokkou/issues/new") }
                    .buttonStyle(PaperButtonStyle())
            }
            .padding(.top, 4)
            Spacer(minLength: 10)
            Text("変換は AzooKeyKanaKanjiConverter、キー操作は macSKK を手本にしています")
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.quiet)
                .multilineTextAlignment(.center)
                .padding(.bottom, 20)
        }
        .padding(.horizontal, 40)
    }

    private func open(_ url: String) {
        NSWorkspace.shared.open(URL(string: url)!)
    }
}

// MARK: 部品

/// 朱のスイッチ。AppKit の部品を使わないので、画像にも書き出せる
struct PaperToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Capsule()
            .fill(configuration.isOn ? Theme.accent : Theme.quiet.opacity(0.25))
            .frame(width: 34, height: 20)
            .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                Circle()
                    .fill(.white)
                    .shadow(color: .black.opacity(0.18), radius: 1.5, y: 1)
                    .padding(2)
            }
            .animation(Theme.move, value: configuration.isOn)
            .contentShape(Capsule())
            .onTapGesture { configuration.isOn.toggle() }
            .accessibilityAddTraits(.isButton)
            .accessibilityValue(configuration.isOn ? "オン" : "オフ")
    }
}

/// 紙の上のボタン。prominent は朱で塗る
struct PaperButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(prominent ? Theme.onAccent : Theme.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(prominent ? Theme.accent : Theme.surface, in: shape)
            .overlay(shape.strokeBorder(prominent ? .clear : Theme.border, lineWidth: 0.5))
            .shadow(color: .black.opacity(prominent ? 0.12 : 0.05), radius: 1.5, y: 1)
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.45)
            .contentShape(shape)
    }
}
