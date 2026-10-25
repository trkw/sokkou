import Carbon
import Cocoa
import InputMethodKit
import SokkouCore

/// 英数と日本語の入力ソースの ID は、バンドル ID に接尾辞を付けたもの
extension InputSourceKind {
    private var suffix: String { self == .roman ? "Roman" : "Japanese" }

    var sourceID: String { "\(Bundle.main.bundleIdentifier!).\(suffix)" }

    /// sokkou の入力ソースの ID でなければ nil
    init?(sourceID: String) {
        guard let bundleID = Bundle.main.bundleIdentifier, sourceID.hasPrefix(bundleID + ".") else { return nil }
        self = sourceID.hasSuffix(".Roman") ? .roman : .japanese
    }
}

/// アプリごとのモード。入力欄ごとの入力コントローラで共有し、入れ替えや再起動のあとも覚えておく
let modeMemory = ModeMemory(saved: Settings.appModes)

/// Carbon の仮想キーコード。NSEvent.keyCode と同じ UInt16 にそろえる
private enum KeyCode {
    static let returnKey = UInt16(kVK_Return)
    static let enter = UInt16(kVK_ANSI_KeypadEnter)
    static let space = UInt16(kVK_Space)
    static let backspace = UInt16(kVK_Delete)
    static let escape = UInt16(kVK_Escape)
    static let eisu = UInt16(kVK_JIS_Eisu)
    static let kana = UInt16(kVK_JIS_Kana)
    static let left = UInt16(kVK_LeftArrow)
    static let right = UInt16(kVK_RightArrow)
    static let down = UInt16(kVK_DownArrow)
    static let up = UInt16(kVK_UpArrow)
    static let tab = UInt16(kVK_Tab)
}

@objc(SokkouInputController)
final class SokkouInputController: IMKInputController {
    /// キー操作の状態は入力欄ごとに持つ。変換エンジンと覚えた候補はプロセスで共有する
    private lazy var composer: Composer = {
        let composer = Composer(engine: sharedEngine, learning: sharedLearning, lexicon: sharedLexicon)
        Self.apply(to: composer)
        return composer
    }()
    /// 未確定の文字列を表示しているか。表示していないときに空の未確定の文字列を送らない
    private var showsMarkedText = false
    /// 入力欄のアプリのバンドル ID。モードをアプリごとに覚えるのに使う
    private var app: String?

    // MARK: InputMethodKit からの呼び出し
    // InputMethodKit の基底クラスは隔離の指定を持たないので、上書きする関数は nonisolated にし、中身を onMain でメインアクターとして動かす

    private nonisolated func onMain<T: Sendable>(_ work: @MainActor () -> T) -> T {
        MainActor.assumeIsolated(work)
    }

    nonisolated override init!(server: IMKServer!, delegate: Any!, client inputClient: Any!) {
        super.init(server: server, delegate: delegate, client: inputClient)
    }

    nonisolated override init() {
        super.init()
    }

    nonisolated override func recognizedEvents(_ sender: Any!) -> Int {
        Int(NSEvent.EventTypeMask.keyDown.rawValue)
    }

    /// macOS が入力ソースを切り替えたとき（Ctrl-Space、入力メニュー、英数・かなキー）
    nonisolated override func setValue(_ value: Any!, forTag tag: Int, client sender: Any!) {
        guard let id = value as? String else { return }
        nonisolated(unsafe) let client = sender as? IMKTextInput
        onMain {
            guard let source = InputSourceKind(sourceID: id) else { return }
            selectSource(source, client: client)
        }
    }

    nonisolated override func commitComposition(_ sender: Any!) {
        guard let client = sender as? IMKTextInput else { return }
        nonisolated(unsafe) let target = client
        onMain {
            composer.commitAll()
            flush(target)
        }
    }

    nonisolated override func activateServer(_ sender: Any!) {
        super.activateServer(sender)
        nonisolated(unsafe) let target = sender as? IMKTextInput
        onMain {
            if let target { activate(target) }
        }
    }

    nonisolated override func deactivateServer(_ sender: Any!) {
        nonisolated(unsafe) let target = sender as? IMKTextInput
        onMain {
            if let target {
                composer.commitAll()
                flush(target)
            }
            candidatePanel.hide()
            modeBadge.hide()
        }
        super.deactivateServer(sender)
    }

    nonisolated override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event, event.type == .keyDown, let client = sender as? IMKTextInput else { return false }
        nonisolated(unsafe) let keyEvent = event
        nonisolated(unsafe) let target = client
        return onMain { handleKeyDown(keyEvent, client: target) }
    }

    nonisolated override func menu() -> NSMenu! {
        // NSMenu は Sendable ではないので onMain の戻り値にできない。メインアクターで作って外の変数に入れる
        nonisolated(unsafe) var menu: NSMenu?
        MainActor.assumeIsolated { menu = makeMenu() }
        return menu
    }

    // MARK: キー入力

    private func handleKeyDown(_ event: NSEvent, client: IMKTextInput) -> Bool {
        Updater.noteKey()
        // パスワード欄などで安全入力が有効なら、何も変換せずアプリに渡す
        if IsSecureEventInputEnabled() {
            composer.commitAll()
            flush(client)
            return false
        }
        guard let key = Self.key(for: event) else {
            // 割り当ての無いキー（Cmd・Option 付き、ファンクションキーなど）は、確定してからアプリに渡す
            composer.commitAll()
            flush(client)
            return false
        }
        // 設定はほかの入力欄のメニューや設定の窓からも変わるので、打鍵ごとに読み直す
        Self.apply(to: composer)
        if app == nil { app = client.bundleIdentifier() }
        if key == .control("/"), let text = composer.undoableCommit, Self.range(before: text, in: client) == nil {
            // 入力欄のカーソルの前が確定した文字列でない（カーソルが動いた、読めないアプリ）なら、取り消さずにアプリに渡す
            composer.forgetCommit()
        }
        let before = composer.mode
        let wasComposing = composer.isComposing
        let handled = composer.handle(key, leading: { Self.leadingContext(of: client) })
        flush(client)
        if case .control = key, handled, !wasComposing, !composer.isComposing, ModeMemory.isTerminal(app) {
            tellKeyWasUsed(client)
        }
        if composer.mode != before {
            modeDidChange(from: before, client: client)
        }
        return handled
    }

    // MARK: モード

    /// 入力欄に入ったとき。アプリを移ったらそのアプリで最後に使ったモードに、同じアプリの中なら今の入力ソースにそろえる
    private func activate(_ client: IMKTextInput) {
        app = client.bundleIdentifier()
        let current = Self.currentSourceID().flatMap(InputSourceKind.init(sourceID:))
        let mode = modeMemory.activate(app, current: composer.mode, source: current)
        Settings.appModes = modeMemory.saved
        if composer.mode != mode {
            composer.select(mode: mode)
            flush(client)
        }
        let source = InputSourceKind(mode)
        if let current, current != source {
            client.selectMode(source.sourceID)
        }
    }

    /// いま選ばれている入力ソースの ID
    private static func currentSourceID() -> String? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyInputSourceID)
        else { return nil }
        return Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
    }

    /// macOS が入力ソースを切り替えたとき。カタカナなど日本語の中のモードにいて日本語が選ばれたなら、そのまま
    private func selectSource(_ source: InputSourceKind, client: IMKTextInput?) {
        guard InputSourceKind(composer.mode) != source else { return }
        composer.select(mode: source.mode)
        modeMemory.remember(composer.mode, for: app)
        Settings.appModes = modeMemory.saved
        if let client { flush(client) }
    }

    /// 英数とそれ以外の行き来は入力ソースを切り替え、macOS の札に任せる。
    /// カタカナ・半角カナ・全角英数は日本語の入力ソースの中のモードで、macOS は何も出さないので sokkou の札で見せる
    private func modeDidChange(from before: InputMode, client: IMKTextInput) {
        modeMemory.remember(composer.mode, for: app)
        Settings.appModes = modeMemory.saved
        switch ModeChangeReaction(from: before, to: composer.mode) {
        case .selectSource(let source):
            client.selectMode(source.sourceID)
        case .showBadge:
            modeBadge.show(composer.mode, near: caretRect(client))
        }
    }

    /// 何も打っていないときに Ctrl キーをモードの切り替えに使ったことを、ターミナルに知らせる。
    /// ターミナルの多くは、IME が何も表示しなかったキーを自分でも処理するので、C-j が改行、C-l が画面の消去になってしまう。
    /// 未確定の文字列を一瞬出して消す（AquaSKK・macSKK の空文字挿入と同じ）
    private func tellKeyWasUsed(_ client: IMKTextInput) {
        let none = NSRange(location: NSNotFound, length: 0)
        client.setMarkedText("\u{0C}", selectionRange: none, replacementRange: none)
        client.setMarkedText("", selectionRange: none, replacementRange: none)
    }

    /// 設定を Composer に移す
    private static func apply(to composer: Composer) {
        composer.learns = Settings.learns
        composer.undoesCommit = SKKFeature.undoCommit.isOn
        composer.convertsWithQ = SKKFeature.katakanaWithQ.isOn
        composer.usesSKKCandidateKeys = SKKFeature.candidateKeys.isOn
        composer.commitsAtPunctuation = SKKFeature.commitAtPunctuation.isOn
        composer.suggestsCompletion = SKKFeature.completionHint.isOn
        composer.showsAnnotations = SKKFeature.annotations.isOn
    }

    /// 入力欄のカーソルの直前にある text の範囲。カーソルの前が text でないか、読めなければ nil
    private static func range(before text: String, in client: IMKTextInput) -> NSRange? {
        let selection = client.selectedRange()
        let length = (text as NSString).length
        guard selection.location != NSNotFound, selection.length == 0, selection.location >= length else { return nil }
        let range = NSRange(location: selection.location - length, length: length)
        guard client.attributedSubstring(from: range)?.string == text else { return nil }
        return range
    }

    /// sokkou が区別するキーにする。区別しないキーは nil
    static func key(for event: NSEvent) -> Key? {
        let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
        switch event.keyCode {
        case KeyCode.eisu: return .eisu
        case KeyCode.kana: return .kana
        default: break
        }
        if flags.contains(.command) || flags.contains(.option) { return nil }
        if flags.contains(.control) {
            // 英字と、確定の取り消しの C-/
            guard let letter = event.charactersIgnoringModifiers?.first, letter.isASCII, letter.isLetter || letter == "/" else { return nil }
            return .control(Character(flags.contains(.shift) ? letter.uppercased() : letter.lowercased()))
        }
        let shift = flags.contains(.shift)
        switch event.keyCode {
        case KeyCode.returnKey, KeyCode.enter: return shift ? .shiftEnter : .enter
        case KeyCode.space: return shift ? .shiftSpace : .space
        case KeyCode.backspace: return .backspace
        case KeyCode.escape: return .escape
        case KeyCode.left: return shift ? .shiftLeft : .left
        case KeyCode.right: return shift ? .shiftRight : .right
        case KeyCode.up: return .up
        case KeyCode.down: return .down
        case KeyCode.tab: return shift ? nil : .tab
        default: break
        }
        guard let text = event.characters, text.count == 1, let scalar = text.unicodeScalars.first,
              (0x21...0x7E).contains(scalar.value)
        else { return nil }
        return .character(Character(text))
    }

    /// 入力欄のカーソルの直前の 1 文字を読む。読めない、空白・改行、文末の記号の後なら文頭とする
    private static func leadingContext(of client: IMKTextInput) -> Leading {
        let selection = client.selectedRange()
        guard selection.location != NSNotFound, selection.location > 0,
              let before = client.attributedSubstring(from: NSRange(location: selection.location - 1, length: 1))?.string.last,
              !before.isWhitespace,
              !before.unicodeScalars.contains(where: \.properties.isSentenceTerminal)
        else { return .start }
        return before.isASCII ? .afterEnglish : .afterJapanese
    }

    // MARK: 表示と確定

    /// 確定した文字列をアプリに渡し、未確定の文字列と候補の窓を今の状態にする
    private func flush(_ client: IMKTextInput) {
        let text = composer.takeCommitted()
        if !text.isEmpty {
            client.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
            showsMarkedText = false
        }
        // 確定を取り消したら、入力欄の確定した文字列を未確定の文字列で置き換える
        let replaced = composer.takeReplaced().flatMap { Self.range(before: $0, in: client) }
        let presentation = composer.presentation
        if !presentation.segments.isEmpty || showsMarkedText {
            let marked = markedText(presentation)
            // カーソルは常に末尾に置く。ターミナル（xterm.js）はカーソルの位置を未確定の文字列の終わりとして読む
            client.setMarkedText(
                marked,
                selectionRange: NSRange(location: marked.length, length: 0),
                replacementRange: replaced ?? NSRange(location: NSNotFound, length: 0)
            )
            showsMarkedText = marked.length > 0
        }
        if let window = presentation.window {
            candidatePanel.show(window, near: caretRect(client, at: focusedOffset(presentation)))
        } else {
            candidatePanel.hide()
        }
    }

    private func markedText(_ presentation: Presentation) -> NSAttributedString {
        let marked = NSMutableAttributedString()
        for segment in presentation.segments {
            let range = NSRange(location: marked.length, length: (segment.text as NSString).length)
            var attributes = highlight(for: segment.style, at: range)
            // 選んでいる文節の下線は朱にする。候補の窓の印と同じ色で、どこを直しているかを示す
            if segment.style == .focused {
                attributes[.underlineColor] = Theme.vermilion
            }
            if segment.style == .english {
                attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue | NSUnderlineStyle.patternDot.rawValue
            }
            if segment.style == .suggestion {
                attributes[.foregroundColor] = NSColor.tertiaryLabelColor
                attributes[.underlineStyle] = 0
            }
            marked.append(NSAttributedString(string: segment.text, attributes: attributes))
        }
        return marked
    }

    /// 下線の種類と太さはアプリが決めるので、文節の状態だけを IMK に渡して属性を受け取る
    private func highlight(for style: MarkedSegment.Style, at range: NSRange) -> [NSAttributedString.Key: Any] {
        let kind = switch style {
        case .focused: kTSMHiliteSelectedConvertedText
        case .clause: kTSMHiliteConvertedText
        case .japanese, .english, .raw, .manual, .suggestion: kTSMHiliteRawText
        }
        let raw = mark(forStyle: kind, at: range) ?? [:]
        return Dictionary(uniqueKeysWithValues: raw.compactMap { key, value in
            (key as? String).map { (NSAttributedString.Key($0), value) }
        })
    }

    /// 候補の窓を出す文節が、未確定の文字列の何文字目（UTF-16）から始まるか
    private func focusedOffset(_ presentation: Presentation) -> Int {
        var offset = 0
        for segment in presentation.segments {
            if segment.style == .focused { return offset }
            offset += (segment.text as NSString).length
        }
        return 0
    }

    /// 未確定の文字列の index 文字目の、画面上の行の矩形
    private func caretRect(_ client: IMKTextInput, at index: Int = 0) -> NSRect {
        var rect = NSRect.zero
        client.attributes(forCharacterIndex: index, lineHeightRectangle: &rect)
        return rect
    }

    // MARK: メニュー

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "設定…", action: #selector(openSettings(_:)), keyEquivalent: ""))
        menu.addItem(.separator())
        let learning = NSMenuItem(title: "選んだ候補を覚える", action: #selector(toggleLearning(_:)), keyEquivalent: "")
        learning.state = Settings.learns ? .on : .off
        menu.addItem(learning)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "SKK-JISYO.L を入れる", action: #selector(downloadLargeDictionary(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "SKK 辞書を追加…", action: #selector(addDictionary(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "SKK のユーザー辞書を取り込む…", action: #selector(importUserDictionary(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "辞書のフォルダを開く", action: #selector(openDictionaries(_:)), keyEquivalent: ""))
        menu.addItem(.separator())
        // どのビルドが動いているかを、試すたびに確かめられるように出す
        let build = NSMenuItem(title: Updater.build, action: nil, keyEquivalent: "")
        build.isEnabled = false
        menu.addItem(build)
        if Updater.isAvailable {
            menu.addItem(NSMenuItem(title: "最新版に更新", action: #selector(installLatest(_:)), keyEquivalent: ""))
            menu.addItem(NSMenuItem(title: "PR の版を入れる…", action: #selector(installPR(_:)), keyEquivalent: ""))
            let auto = NSMenuItem(title: "新しいリリースを自動で入れる", action: #selector(toggleAutoUpdates(_:)), keyEquivalent: "")
            auto.state = Settings.autoUpdates ? .on : .off
            menu.addItem(auto)
            if let previous = Updater.previousBuild {
                menu.addItem(NSMenuItem(title: "前の版に戻す（\(previous)）", action: #selector(rollback(_:)), keyEquivalent: ""))
            }
        }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "sokkou を取り除く…", action: #selector(uninstall(_:)), keyEquivalent: ""))
        return menu
    }

    @objc nonisolated func openSettings(_ sender: Any?) {
        onMain { SettingsWindow.shared.show() }
    }

    @objc nonisolated func installLatest(_ sender: Any?) {
        onMain { Updater.install() }
    }

    @objc nonisolated func installPR(_ sender: Any?) {
        onMain { Updater.askAndInstallPR() }
    }

    @objc nonisolated func rollback(_ sender: Any?) {
        onMain { Updater.rollback() }
    }

    @objc nonisolated func uninstall(_ sender: Any?) {
        onMain { Updater.askAndUninstall() }
    }

    @objc nonisolated func toggleAutoUpdates(_ sender: Any?) {
        onMain { Settings.autoUpdates.toggle() }
    }

    @objc nonisolated func downloadLargeDictionary(_ sender: Any?) {
        onMain { Dictionaries.downloadLarge() }
    }

    @objc nonisolated func addDictionary(_ sender: Any?) {
        onMain { Dictionaries.add() }
    }

    @objc nonisolated func importUserDictionary(_ sender: Any?) {
        onMain { Dictionaries.importUserDictionary() }
    }

    @objc nonisolated func openDictionaries(_ sender: Any?) {
        onMain { Dictionaries.openFolder() }
    }

    @objc nonisolated func toggleLearning(_ sender: Any?) {
        onMain {
            Settings.learns.toggle()
            Self.apply(to: composer)
        }
    }
}
