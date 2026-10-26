import AppKit

/// sokkou の .app に入れた、入れ替えを受け持つアプリ（Contents/Helpers/sokkou-installer.app）を動かす。
/// sokkou は ~/Library/Input Methods に自分で書かず、入れる・更新する・取り除くはそちらに頼む
enum Installer {
    static let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/sokkou-installer.app", isDirectory: true)
    static var hasHelper: Bool {
        FileManager.default.isExecutableFile(atPath: helper.appendingPathComponent("Contents/MacOS/sokkou-installer").path)
    }

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

    /// 端末から動かしたとき（前の版の install.sh、Homebrew、Nix の --install・--uninstall）。インストーラーを起こして終わるのを待つ。
    /// sokkou は App Sandbox の中なので、子のプロセスにするとインストーラーもサンドボックスに入って入れ物の外に書けない。
    /// そこで別のアプリとして起こす。終わりの状態は受け取れないので、結果が要るときはインストーラーを直に動かす
    static func run(_ arguments: [String]) -> Int32 {
        final class Launch {
            var done = false
            var pid: pid_t?
            var failure: String?
        }
        let launch = Launch()
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = arguments
        configuration.createsNewApplicationInstance = true
        configuration.addsToRecentItems = false
        configuration.activates = false
        NSWorkspace.shared.openApplication(at: helper, configuration: configuration) { app, error in
            let pid = app?.processIdentifier
            let failure = error?.localizedDescription
            Task { @MainActor in
                launch.pid = pid
                launch.failure = failure
                launch.done = true
            }
        }
        while !launch.done || launch.pid.map({ kill($0, 0) == 0 }) == true {
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        }
        if let failure = launch.failure {
            print("インストーラーを起動できない: \(failure)")
            return 1
        }
        print("== インストーラーが終わった。結果は \(helper.path)/Contents/MacOS/sokkou-installer を直に動かすと受け取れる")
        return 0
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
