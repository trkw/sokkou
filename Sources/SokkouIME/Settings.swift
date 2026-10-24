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
