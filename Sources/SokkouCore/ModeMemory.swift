/// sokkou の 2 つの入力ソース。英数とそれ以外の行き来は入力ソースの切り替えにするので、
/// Ctrl-Space でも切り替わり、macOS が自分の札とメニューバーのアイコンで見せる
public enum InputSourceKind: Sendable, Equatable {
    case japanese
    case roman

    /// そのモードで選ばれている入力ソース。カタカナ・半角カナ・全角英数は日本語の入力ソースの中のモード
    public init(_ mode: InputMode) {
        self = mode == .ascii ? .roman : .japanese
    }

    /// 入力ソースに切り替わったときのモード
    public var mode: InputMode {
        self == .roman ? .ascii : .hiragana
    }
}

/// モードが変わったときに、入力メソッドがすること
public enum ModeChangeReaction: Sendable, Equatable {
    /// 入力ソースを切り替える。表示は macOS に任せる
    case selectSource(InputSourceKind)
    /// 入力ソースは変わらず macOS は何も出さないので、sokkou の札で見せる
    case showBadge

    public init(from before: InputMode, to after: InputMode) {
        let source = InputSourceKind(after)
        self = source == InputSourceKind(before) ? .showBadge : .selectSource(source)
    }
}

/// アプリごとに最後のモードを覚える。macOS は入力欄ごとに入力コントローラを作るので、
/// 覚えておかないと別のウィンドウや欄に移るたびにひらがなに戻ってしまう
public final class ModeMemory {
    /// 最初から英数で始めるアプリ。コマンドを打つことが多く、日本語を書くときだけ `C-j` を押す
    public static let terminals: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "com.github.wez.wezterm",
        "com.mitchellh.ghostty",
        "net.kovidgoyal.kitty",
        "org.alacritty",
        "dev.warp.Warp-Stable",
    ]

    private var modes: [String: InputMode] = [:]
    /// 最後に入力欄に入ったアプリ
    private var lastApp: String?

    public init() {}

    public static func isTerminal(_ app: String?) -> Bool {
        app.map(terminals.contains) ?? false
    }

    public func mode(for app: String?) -> InputMode {
        guard let app else { return .hiragana }
        return modes[app] ?? (Self.isTerminal(app) ? .ascii : .hiragana)
    }

    public func remember(_ mode: InputMode, for app: String?) {
        guard let app else { return }
        modes[app] = mode
    }

    /// 入力欄に入ったときのモード。アプリを移ったときは、そのアプリで最後に使ったモードにする。
    /// 同じアプリの中では、いま選ばれている入力ソースに従う（ABC などから sokkou の日本語に切り替えたときに、覚えた英数に戻さない）。
    /// source は sokkou の入力ソースが選ばれていなければ nil。決めたモードは覚える
    public func activate(_ app: String?, current: InputMode, source: InputSourceKind?) -> InputMode {
        defer { lastApp = app }
        let mode: InputMode
        if app != lastApp {
            mode = self.mode(for: app)
        } else if let source, source != InputSourceKind(current) {
            mode = source.mode
        } else {
            mode = current
        }
        remember(mode, for: app)
        return mode
    }
}
