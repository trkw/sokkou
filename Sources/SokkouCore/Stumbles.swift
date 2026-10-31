/// Composer の状態の大まかな種類
public enum Stage: String, Sendable, Equatable, Codable {
    case idle
    /// 打っている途中（自動変換を見せている）
    case typing
    /// 文節選択
    case selecting
    /// ▽ ▼
    case manual
    /// 単語の登録
    case registering
}

extension InputMode: Codable {}

/// 入力メソッドが 1 つのキーを処理した前後。つまづきを見分けるのに使う
public struct Keystroke: Sendable {
    public var key: Key
    public var stageBefore: Stage
    public var stageAfter: Stage
    public var modeBefore: InputMode
    public var modeAfter: InputMode
    /// false ならキーをアプリに渡した
    public var handled: Bool
    /// このキーで確定した文字列
    public var committed: String
    /// キーを受ける前に見せていた未確定の文字列
    public var shown: String
    /// キーの処理にかかった時間
    public var milliseconds: Double
    /// 打った時刻（秒）。間隔だけを見るので、起点はどこでもよい
    public var time: Double

    public init(
        key: Key, stageBefore: Stage, stageAfter: Stage, modeBefore: InputMode, modeAfter: InputMode,
        handled: Bool, committed: String = "", shown: String = "", milliseconds: Double = 0, time: Double
    ) {
        self.key = key
        self.stageBefore = stageBefore
        self.stageAfter = stageAfter
        self.modeBefore = modeBefore
        self.modeAfter = modeAfter
        self.handled = handled
        self.committed = committed
        self.shown = shown
        self.milliseconds = milliseconds
        self.time = time
    }
}

/// 打っていてつまづいたところ 1 つ
public struct Stumble: Sendable, Equatable, Codable {
    public enum Kind: String, Sendable, Codable, CaseIterable {
        /// 確定した直後に、アプリで消した
        case deletedAfterCommit
        /// 確定した直後の ⌃/ で選び直した
        case undidCommit
        /// 打ちかけを Esc・⌃G で捨てた
        case cancelled
        /// 自動変換のままでは違ったので、候補や文節を直した
        case corrected
        /// 打ちかけを 3 回以上続けて消した
        case retyped
        /// 打ちかけを ⌃K・⌃Q・⌃L・⌃⇧L で別の文字種にした（日英の判定や字種が違った）
        case fixedForm
        /// 違うモードで打って消し、モードを替えた
        case wrongMode
        /// 今のモードに切り替えるキーを押した。モードを取り違えていたか、前の切り替えが効かなかった
        case modeKeyDidNothing
        /// キーの処理に時間がかかった
        case slow
        /// 利用者がメニューから印をつけた
        case marked

        public var title: String {
            switch self {
            case .deletedAfterCommit: "確定してすぐ消した"
            case .undidCommit: "確定を取り消した"
            case .cancelled: "打ちかけを捨てた"
            case .corrected: "自動変換を直した"
            case .retyped: "打ちかけを何度も消した"
            case .fixedForm: "字種を手で直した"
            case .wrongMode: "違うモードで打って打ち直した"
            case .modeKeyDidNothing: "今のモードへの切り替えキーを押した"
            case .slow: "変換が遅かった"
            case .marked: "自分で印をつけた"
            }
        }
    }

    public var kind: Kind
    /// つまづいたときのモード
    public var mode: InputMode
    /// 消した回数、候補を動かした回数、かかったミリ秒など。種類ごとの数
    public var count: Int?
    /// 補足（文節を伸び縮みさせた回数、元のモード、押したキーなど）
    public var note: String?
    /// 直前のキーの並び。文字は includesText のときだけそのまま、ほかは「字」にする
    public var keys: [String]
    /// 未確定の文字列と確定した文字列。includesText のときだけ
    public var text: String?

    public init(kind: Kind, mode: InputMode, count: Int? = nil, note: String? = nil, keys: [String] = [], text: String? = nil) {
        self.kind = kind
        self.mode = mode
        self.count = count
        self.note = note
        self.keys = keys
        self.text = text
    }
}

/// キーの流れから、打っていてつまづいたところを見分ける。入力欄ごとに 1 つ持つ
public struct StumbleDetector {
    /// 打った文字と未確定・確定の文字列も残す。既定は残さない
    public var includesText = false

    /// 確定のあと、消したら「確定してすぐ消した」とする秒数
    static let afterCommit = 3.0
    /// 消してからモードを替えたら「違うモードで打った」とする秒数
    static let afterDelete = 5.0
    /// これより長くかかったら遅いとする
    static let slowMilliseconds = 100.0
    /// 遅いことを続けて残さない秒数
    static let slowInterval = 10.0
    /// 残す直前のキーの数
    static let recentCount = 12

    /// 直前のキー。文字を隠すかは残すときの includesText で決める（途中で切り替えても、隠すべき文字を残さない）
    private var recent: [Key] = []
    private var lastCommit: (time: Double, text: String)?
    private var deletedSinceCommit = false
    private var deletesInRow = 0
    private var lastDelete: Double?
    private var lastSlow: Double?
    private var correcting: Correcting?

    /// 文節選択を始めてから、候補と文節を動かした回数
    private struct Correcting {
        var shown: String
        var steps = 0
        var resizes = 0
    }

    public init() {}

    /// キーを 1 つ見て、つまづいたところを返す
    public mutating func observe(_ stroke: Keystroke) -> [Stumble] {
        recent.append(stroke.key)
        if recent.count > Self.recentCount { recent.removeFirst(recent.count - Self.recentCount) }
        var found: [Stumble] = []
        func add(_ kind: Stumble.Kind, count: Int? = nil, note: String? = nil, text: String? = nil) {
            found.append(Stumble(
                kind: kind, mode: stroke.modeBefore, count: count, note: note, keys: recent.map { label($0) },
                text: includesText ? text : nil
            ))
        }
        let key = stroke.key
        let idleBefore = stroke.stageBefore == .idle

        if stroke.milliseconds >= Self.slowMilliseconds,
           lastSlow.map({ stroke.time - $0 >= Self.slowInterval }) ?? true {
            lastSlow = stroke.time
            add(.slow, count: Int(stroke.milliseconds), note: stroke.stageBefore.rawValue)
        }

        // 消す
        let deletes = key == .backspace || key == .control("h")
        if deletes {
            lastDelete = stroke.time
            if idleBefore, !stroke.handled {
                if let commit = lastCommit, stroke.time - commit.time <= Self.afterCommit, !deletedSinceCommit {
                    deletedSinceCommit = true
                    add(.deletedAfterCommit, count: commit.text.count, text: commit.text)
                }
            } else if stroke.stageBefore == .typing || stroke.stageBefore == .manual {
                deletesInRow += 1
                if deletesInRow == 3 { add(.retyped, text: stroke.shown) }
            }
        } else {
            deletesInRow = 0
        }

        if key == .control("/"), idleBefore, stroke.stageAfter != .idle {
            add(.undidCommit)
        }

        if key == .escape || key == .control("g"), !idleBefore, stroke.stageAfter == .idle, stroke.committed.isEmpty {
            add(.cancelled, note: stroke.stageBefore.rawValue, text: stroke.shown)
        }

        // 文節選択。入ったキーから、出るまでに動かした回数を数える
        if stroke.stageAfter == .selecting, stroke.stageBefore != .selecting, stroke.stageBefore != .registering {
            correcting = Correcting(shown: stroke.shown)
        }
        if stroke.stageAfter == .selecting || stroke.stageBefore == .selecting {
            switch key {
            case .left, .right, .control("b"), .control("f"):
                correcting?.resizes += 1
            case .space, .shiftSpace, .up, .down, .control("n"), .control("p"), .pageUp, .pageDown:
                correcting?.steps += 1
            case .character(let character) where stroke.stageBefore == .selecting && (Composer.labels.contains(character) || character == "x"):
                correcting?.steps += 1
            default:
                break
            }
        }
        if stroke.stageBefore == .selecting, stroke.stageAfter != .selecting, stroke.stageAfter != .registering,
           let correcting {
            self.correcting = nil
            let outcome = stroke.committed.isEmpty ? "戻した" : "確定"
            add(.corrected, count: correcting.steps, note: "文節 \(correcting.resizes) 回・\(outcome)",
                text: [correcting.shown, stroke.committed].filter { !$0.isEmpty }.joined(separator: " → "))
        }

        if case .control(let letter) = key, "kqlL".contains(letter), stroke.handled,
           stroke.stageBefore == .typing || stroke.stageBefore == .selecting {
            add(.fixedForm, note: "⌃\(letter)", text: stroke.shown)
        }

        // 何も打っていないときのモードのキー
        if idleBefore, case .control(let letter) = key, "jkqlL".contains(letter) {
            if stroke.modeAfter != stroke.modeBefore {
                if let delete = lastDelete, stroke.time - delete <= Self.afterDelete {
                    add(.wrongMode, note: "\(stroke.modeBefore.rawValue) → \(stroke.modeAfter.rawValue)")
                }
            } else if stroke.handled {
                add(.modeKeyDidNothing, note: "⌃\(letter)")
            }
        }
        if stroke.modeAfter != stroke.modeBefore { lastDelete = nil }

        // 確定のあとを見張る。打ち始めたか、ほかのキーをアプリに渡したら（カーソルが動いたかも）見張るのをやめる
        if !stroke.committed.isEmpty {
            lastCommit = (stroke.time, stroke.committed)
            deletedSinceCommit = false
        } else if !deletes, idleBefore {
            lastCommit = nil
        }
        return found
    }

    /// sokkou が見ないキー（⌘・⌥ 付きなど）をアプリに渡した。カーソルが動いたかもしれないので、確定のあとを見張るのをやめる
    public mutating func skipped() {
        lastCommit = nil
        deletesInRow = 0
    }

    /// 利用者が「いまつまづいた」を選んだ。直前のキーの並びを残す
    public func mark(mode: InputMode) -> Stumble {
        Stumble(kind: .marked, mode: mode, keys: recent.map { label($0) })
    }

    private func label(_ key: Key) -> String {
        switch key {
        case .character(let character):
            includesText || !(character.isLetter || character.isNumber) ? String(character) : "字"
        case .control(let letter): "⌃\(letter)"
        case .space: "␣"
        case .shiftSpace: "⇧␣"
        case .enter: "⏎"
        case .shiftEnter: "⇧⏎"
        case .backspace: "⌫"
        case .escape: "⎋"
        case .left: "←"
        case .right: "→"
        case .up: "↑"
        case .down: "↓"
        case .shiftLeft: "⇧←"
        case .shiftRight: "⇧→"
        case .tab: "⇥"
        case .eisu: "英数"
        case .kana: "かな"
        case .pageUp: "⇞"
        case .pageDown: "⇟"
        }
    }
}
