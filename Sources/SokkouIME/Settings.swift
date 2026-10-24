import Foundation

/// 利用者が入力メニューから変える設定
enum Settings {
    private static let defaults = UserDefaults.standard

    /// 選んだ候補を覚えるか。既定は覚える
    static var learns: Bool {
        get { defaults.object(forKey: "learns") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "learns") }
    }
}

/// 入力ソースを替えるとカーソルの下に出る青い札
enum SystemIndicator {
    /// `defaults write -g TSMLanguageIndicatorEnabled -bool false` で消える。キーがなければ出る
    static var isEnabled: Bool {
        let value = CFPreferencesCopyValue(
            "TSMLanguageIndicatorEnabled" as CFString,
            kCFPreferencesAnyApplication,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        )
        return (value as? Bool) ?? true
    }
}
