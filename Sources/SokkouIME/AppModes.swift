import SokkouCore

/// アプリごとに最後のモードを覚える。macOS は入力欄ごとに入力コントローラを作るので、
/// 覚えておかないと別のウィンドウや欄に移るたびにひらがなに戻ってしまう
enum AppModes {
    /// 最初から英数で始めるアプリ。コマンドを打つことが多く、日本語を書くときだけ `C-j` を押す
    static let terminals: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "com.github.wez.wezterm",
        "com.mitchellh.ghostty",
        "net.kovidgoyal.kitty",
        "org.alacritty",
        "dev.warp.Warp-Stable",
    ]

    private static var modes: [String: InputMode] = [:]

    static func mode(for app: String?) -> InputMode {
        guard let app else { return .hiragana }
        return modes[app] ?? (isTerminal(app) ? .ascii : .hiragana)
    }

    static func remember(_ mode: InputMode, for app: String?) {
        guard let app else { return }
        modes[app] = mode
    }

    static func isTerminal(_ app: String?) -> Bool {
        app.map(terminals.contains) ?? false
    }
}
