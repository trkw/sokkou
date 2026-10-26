/// sokkou の入力モード。ひらがなモードだけが日英の自動判定と自動変換をする
/// 生の値はアプリごとのモードを保存するときに使う
public enum InputMode: String, Sendable, Hashable, CaseIterable {
    case hiragana
    case katakana
    case halfwidthKatakana
    /// 打ったままアプリに渡す
    case ascii
    case fullwidthRoman
}

/// 1 つの文字種にする変換。入力中に `C-k` `C-q` `C-l` `C-L` を押したときに使う
public enum CharacterForm: Sendable, Equatable {
    case hiragana
    case katakana
    case halfwidthKatakana
    case fullwidthRoman
    /// 打ったままの英字
    case roman
}

/// 打ち始めたときにカーソルの前にあったもの
public enum Leading: Sendable, Equatable {
    /// 文頭。前に何も無いか、空白・改行・文末の記号の後
    case start
    case afterJapanese
    case afterEnglish
    /// 半角数字の後。続く日本語は助数詞として読む（3 の後の nin → 人）
    case afterNumber(String)
}

extension Leading {
    /// 入力欄のカーソルの前の文字列から決める。空か、空白・改行・文末の記号の後なら文頭
    public init(before text: some StringProtocol) {
        guard let last = text.last, !last.isWhitespace,
              !last.unicodeScalars.contains(where: \.properties.isSentenceTerminal)
        else {
            self = .start
            return
        }
        self = Leading(ending: text) ?? .start
    }

    /// 文字列に続けて打つときの形。半角数字で終われば数字の後、ASCII なら英語の後、それ以外は日本語の後。空なら nil
    public init?(ending text: some StringProtocol) {
        guard let last = text.last else { return nil }
        let digits = String(text.reversed().prefix { $0.isASCII && $0.isNumber }.reversed())
        if !digits.isEmpty {
            self = .afterNumber(digits)
        } else {
            self = last.isASCII ? .afterEnglish : .afterJapanese
        }
    }
}

/// 入力メソッドが受け取ったキーを、sokkou が区別する形にしたもの
public enum Key: Sendable, Equatable {
    /// 印字できる ASCII 1 文字（Shift はすでに反映している）
    case character(Character)
    /// Ctrl を押しながらの英字。Ctrl+Shift+L は `control("L")`
    case control(Character)
    case space
    case shiftSpace
    case enter
    case shiftEnter
    case backspace
    case escape
    case left
    case right
    case up
    case down
    case shiftLeft
    case shiftRight
    /// ▽ の読みを、ユーザー辞書の読みで補完する
    case tab
    /// JIS キーボードの英数キー
    case eisu
    /// JIS キーボードのかなキー
    case kana
    /// 候補の窓のページ送り（Meltype と同じ）。変換していないときはアプリに渡す
    case pageUp
    case pageDown
}

/// 打っている途中の 1 区間
public struct Span: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case japanese
        case english
        case punctuation
    }

    public var kind: Kind
    /// 表示する文字列
    public var text: String
    /// 日本語はかな、それ以外は打ったまま
    public var reading: String

    public init(kind: Kind, text: String, reading: String) {
        self.kind = kind
        self.text = text
        self.reading = reading
    }
}

/// 文節選択で選び直せる 1 文節
public struct Clause: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case japanese
        case english
        case punctuation
        /// 未確定の文字列全体を 1 つの文字種にした文節
        case whole
    }

    public var kind: Kind
    public var reading: String
    /// 重複の無い候補。先頭は変換エンジンが選んだもの
    public var candidates: [String]
    public var selected: Int

    public init(kind: Kind, reading: String, candidates: [String], selected: Int = 0) {
        self.kind = kind
        self.reading = reading
        self.candidates = candidates
        self.selected = selected
    }

    public var output: String { candidates[selected] }
}

/// 文節の並び。payload は変換エンジンが伸縮や確定のために持つ値で、sokkou は中身を見ない
public struct ClauseList {
    public var clauses: [Clause]
    public var payload: Any?

    public init(clauses: [Clause], payload: Any? = nil) {
        self.clauses = clauses
        self.payload = payload
    }
}
