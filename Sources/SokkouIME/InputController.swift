import Carbon
import Cocoa
import InputMethodKit
import SokkouCore

/// 日本語と英数の入力ソースの ID は、バンドル ID に接尾辞を付けたもの
enum InputSource: String {
    case japanese = "Japanese"
    case roman = "Roman"

    var sourceID: String { "\(Bundle.main.bundleIdentifier!).\(rawValue)" }

    init(sourceID: String) {
        self = sourceID.hasSuffix(".\(InputSource.roman.rawValue)") ? .roman : .japanese
    }
}

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
}

@objc(SokkouInputController)
final class SokkouInputController: IMKInputController {
    /// キー操作の状態は入力欄ごとに持つ。変換エンジンと覚えた候補はプロセスで共有する
    private lazy var composer: Composer = {
        let composer = Composer(engine: sharedEngine, learning: sharedLearning)
        composer.learns = Settings.learns
        return composer
    }()
    /// 未確定の文字列を表示しているか。表示していないときに空の未確定の文字列を送らない
    private var showsMarkedText = false

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

    nonisolated override func setValue(_ value: Any!, forTag tag: Int, client sender: Any!) {
        guard let id = value as? String else { return }
        nonisolated(unsafe) let client = sender as? IMKTextInput
        onMain { selectSource(InputSource(sourceID: id), client: client) }
    }

    nonisolated override func commitComposition(_ sender: Any!) {
        guard let client = sender as? IMKTextInput else { return }
        nonisolated(unsafe) let target = client
        onMain {
            composer.commitAll()
            flush(target)
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
        // 設定はほかの入力欄のメニューからも変わるので、打鍵ごとに読み直す
        composer.learns = Settings.learns
        let before = composer.mode
        let handled = composer.handle(key, leading: { Self.leadingContext(of: client) })
        flush(client)
        if composer.mode != before {
            modeDidChange(from: before, client: client)
        }
        return handled
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
            guard let letter = event.charactersIgnoringModifiers?.first, letter.isASCII, letter.isLetter else { return nil }
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

    // MARK: モード

    private func selectSource(_ source: InputSource, client: IMKTextInput?) {
        switch source {
        case .roman:
            guard composer.mode != .ascii else { return }
            composer.select(mode: .ascii)
        case .japanese:
            guard composer.mode == .ascii else { return }
            composer.select(mode: .hiragana)
        }
        if let client {
            flush(client)
            modeBadge.show(composer.mode, near: caretRect(client))
        }
    }

    /// sokkou のキーでモードが変わったら、メニューバーの入力ソースもそろえる
    private func modeDidChange(from before: InputMode, client: IMKTextInput) {
        if composer.mode == .ascii {
            client.selectMode(InputSource.roman.sourceID)
        } else if before == .ascii {
            client.selectMode(InputSource.japanese.sourceID)
        }
        modeBadge.show(composer.mode, near: caretRect(client))
    }

    // MARK: 表示と確定

    /// 確定した文字列をアプリに渡し、未確定の文字列と候補の窓を今の状態にする
    private func flush(_ client: IMKTextInput) {
        let text = composer.takeCommitted()
        if !text.isEmpty {
            client.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
            showsMarkedText = false
        }
        let presentation = composer.presentation
        if !presentation.segments.isEmpty || showsMarkedText {
            let marked = markedText(presentation)
            // カーソルは常に末尾に置く。ターミナル（xterm.js）はカーソルの位置を未確定の文字列の終わりとして読む
            client.setMarkedText(
                marked,
                selectionRange: NSRange(location: marked.length, length: 0),
                replacementRange: NSRange(location: NSNotFound, length: 0)
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
            if segment.style == .english {
                attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue | NSUnderlineStyle.patternDot.rawValue
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
        case .japanese, .english, .raw, .manual: kTSMHiliteRawText
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
        let learning = NSMenuItem(title: "選んだ候補を覚える", action: #selector(toggleLearning(_:)), keyEquivalent: "")
        learning.state = Settings.learns ? .on : .off
        menu.addItem(learning)
        menu.addItem(.separator())
        // どのビルドが動いているかを、試すたびに確かめられるように出す
        let build = NSMenuItem(title: Updater.build, action: nil, keyEquivalent: "")
        build.isEnabled = false
        menu.addItem(build)
        if Updater.isAvailable {
            menu.addItem(NSMenuItem(title: "最新版に更新", action: #selector(installLatest(_:)), keyEquivalent: ""))
            menu.addItem(NSMenuItem(title: "PR の版を入れる…", action: #selector(installPR(_:)), keyEquivalent: ""))
        }
        return menu
    }

    @objc nonisolated func installLatest(_ sender: Any?) {
        onMain { Updater.install() }
    }

    @objc nonisolated func installPR(_ sender: Any?) {
        onMain { Updater.askAndInstallPR() }
    }

    @objc nonisolated func toggleLearning(_ sender: Any?) {
        onMain {
            Settings.learns.toggle()
            composer.learns = Settings.learns
        }
    }
}
