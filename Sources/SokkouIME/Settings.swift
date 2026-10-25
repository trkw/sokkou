import Foundation

/// 利用者が入力メニューから変える設定
enum Settings {
    private static let defaults = UserDefaults.standard

    /// 選んだ候補を覚えるか。既定は覚える
    static var learns: Bool {
        get { defaults.object(forKey: "learns") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "learns") }
    }

    /// 新しいリリースが出たら、打っていないときに自動で入れ替えるか。既定は入れ替える
    static var autoUpdates: Bool {
        get { defaults.object(forKey: "autoUpdates") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "autoUpdates") }
    }

    /// 「前の版に戻す」で戻した版。自動の更新はこの版をもう一度は入れない
    static var skippedRelease: String? {
        get { defaults.string(forKey: "skippedRelease") }
        set { defaults.set(newValue, forKey: "skippedRelease") }
    }

    /// アプリごとに最後に使ったモード。バンドル ID とモードの生の値
    static var appModes: [String: String] {
        get { defaults.dictionary(forKey: "appModes") as? [String: String] ?? [:] }
        set { defaults.set(newValue, forKey: "appModes") }
    }
}

/// SKK の手触りの機能。設定の窓で 1 つずつ切り替える。既定はすべて使う
enum SKKFeature: String, CaseIterable, Identifiable {
    case undoCommit
    case katakanaWithQ
    case candidateKeys
    case commitAtPunctuation
    case completionHint
    case annotations

    var id: Self { self }

    var title: String {
        switch self {
        case .undoCommit: "確定を取り消す"
        case .katakanaWithQ: "▽ の q でカタカナ"
        case .candidateKeys: "x で前の候補"
        case .commitAtPunctuation: "句読点で確定"
        case .completionHint: "読みの続きを薄く見せる"
        case .annotations: "候補の注釈"
        }
    }

    var detail: String {
        switch self {
        case .undoCommit: "確定した直後の ⌃/ で、確定した語を選び直す"
        case .katakanaWithQ: "▽ で読みを打って q で、カタカナにして確定する"
        case .candidateKeys: "▼ の x で前の候補。窓では Space と x でページを送る"
        case .commitAtPunctuation: "打っている途中に 、。！？ を打ったら、そこまで確定する"
        case .completionHint: "▽ で、登録した読みの続きを出す。⇥ で採る"
        case .annotations: "SKK 辞書の注釈を候補の横に出す"
        }
    }

    private var key: String { "skk." + rawValue }

    var isOn: Bool {
        get { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
        nonmutating set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}
