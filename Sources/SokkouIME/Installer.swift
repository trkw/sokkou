import AppKit

/// sokkou の .app に入れた、入れ替えを受け持つアプリ（Contents/Helpers/sokkou-installer.app）を動かす。
/// sokkou は ~/Library/Input Methods に自分で書かず、入れる・更新する・取り除くはそちらに頼む
enum Installer {
    static let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/sokkou-installer.app", isDirectory: true)
    private static var helperBinary: URL { helper.appendingPathComponent("Contents/MacOS/sokkou-installer") }

    static var hasHelper: Bool { FileManager.default.isExecutableFile(atPath: helperBinary.path) }

    /// 入力メソッドの置き場所から起動したか。そこ以外（dmg、ダウンロード、dist）から開かれたらインストールする
    static var isInstalled: Bool {
        let folder = Bundle.main.bundleURL.resolvingSymlinksInPath().deletingLastPathComponent().path
        let places = [home.appendingPathComponent("Library/Input Methods"), URL(fileURLWithPath: "/Library/Input Methods")]
        return places.contains { $0.resolvingSymlinksInPath().path == folder }
    }

    /// 1 つ前の版のビルド。ここから読めなければ nil（「前の版に戻す」はインストーラーが確かめる）
    static var previousBuild: String? {
        let previous = home.appendingPathComponent("Library/Application Support/sokkou/previous")
            .appendingPathComponent(Bundle.main.bundleURL.lastPathComponent)
        guard let info = NSDictionary(contentsOf: previous.appendingPathComponent("Contents/Info.plist")) else { return nil }
        return info["SokkouBuild"] as? String ?? info["CFBundleShortVersionString"] as? String
    }

    /// インストーラーを別のアプリとして起こし、終わりを待たない。sokkou を止めて入れ替えるので、sokkou の子のプロセスにしない。
    /// launched は起こせたかどうかにかかわらず、起こし終えたあとに呼ぶ
    static func launch(_ arguments: [String], launched: (@MainActor () -> Void)? = nil) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = arguments
        configuration.createsNewApplicationInstance = true
        configuration.addsToRecentItems = false
        NSWorkspace.shared.openApplication(at: helper, configuration: configuration) { _, error in
            let message = error?.localizedDescription
            Task { @MainActor in
                if let message {
                    alert("sokkou のインストーラーを起動できませんでした", message)
                    stepBack()
                }
                launched?()
            }
        }
    }

    /// 端末から動かしたとき（--install、--uninstall）。インストーラーを動かして終わりを待ち、その終わりの状態を返す
    static func run(_ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = helperBinary
        process.arguments = arguments
        do {
            try process.run()
        } catch {
            print("インストーラーを動かせない: \(error.localizedDescription)")
            return 1
        }
        process.waitUntilExit()
        return process.terminationStatus
    }

    @discardableResult
    static func alert(_ title: String, _ message: String, buttons: [String] = ["閉じる"]) -> NSApplication.ModalResponse {
        // 入力メソッドは裏で動くアプリなので、窓を出す間だけ前に出られるようにする
        NSApplication.shared.setActivationPolicy(.accessory)
        NSApplication.shared.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        for button in buttons {
            alert.addButton(withTitle: button)
        }
        return alert.runModal()
    }

    /// 窓を閉じたあと、前に出ていたのをやめる。設定の窓が開いている間は、窓が消えないよう前に出たままにする
    static func stepBack() {
        guard !SettingsWindow.shared.isOpen else { return }
        NSApplication.shared.setActivationPolicy(.prohibited)
    }
}

/// 本当のホームフォルダ。App Sandbox の中でも、入れ物（~/Library/Containers）ではなくこちらを指す
let home = URL(fileURLWithPath: String(cString: getpwuid(getuid())!.pointee.pw_dir), isDirectory: true)

struct InstallError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}
