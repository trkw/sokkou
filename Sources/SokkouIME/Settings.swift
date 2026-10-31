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

    /// 前に起動したときのビルド。違うビルドで起動したら、入れ替わったことを知らせる
    static var lastBuild: String? {
        get { defaults.string(forKey: "lastBuild") }
        set { defaults.set(newValue, forKey: "lastBuild") }
    }

    /// 打っていてつまづいたところを記録するか。既定は記録しない
    static var recordsStumbles: Bool {
        get { defaults.bool(forKey: "recordsStumbles") }
        set { defaults.set(newValue, forKey: "recordsStumbles") }
    }

    /// つまづきの記録に、読みと候補も残すか。既定は残さない
    static var stumblesIncludeText: Bool {
        get { defaults.bool(forKey: "stumblesIncludeText") }
        set { defaults.set(newValue, forKey: "stumblesIncludeText") }
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
    case eraseClause
    case katakanaWithQ
    case candidateKeys
    case commitAtPunctuation
    case completionHint
    case annotations

    var id: Self { self }

    var title: String {
        switch self {
        case .undoCommit: "確定を取り消す"
        case .eraseClause: "確定した語をまとめて消す"
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
        case .eraseClause: "確定した直後の ⌫ で、変換した語を 1 文字ずつでなく語ごと消す"
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

/// 候補の窓の形。設定の「見た目」で選ぶ。既定は縦に並べる A
enum CandidateStyle: String, CaseIterable, Identifiable {
    /// 案A 縦に並べ、選んでいる候補に差し色の印をつける
    case list
    /// 案B 横一行に並べ、選んでいる候補に差し色の下線を引く。いちばん場所を取らない
    case strip
    /// 案C 明朝で縦に並べ、右に選んでいる候補と注釈を大きく出す
    case card

    var id: Self { self }

    var title: String {
        switch self {
        case .list: "A　縦に並べる"
        case .strip: "B　横一行"
        case .card: "C　札（明朝と注釈）"
        }
    }

    var detail: String {
        switch self {
        case .list: "選んでいる候補に印をつける。いつもの形"
        case .strip: "入力欄のすぐ下に細く出る。場所を取らない"
        case .card: "選んだ字と注釈を大きく見せる。辞書を引くように"
        }
    }

    static var current: CandidateStyle {
        get { UserDefaults.standard.string(forKey: "candidateStyle").flatMap(CandidateStyle.init(rawValue:)) ?? .list }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "candidateStyle") }
    }
}
