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
