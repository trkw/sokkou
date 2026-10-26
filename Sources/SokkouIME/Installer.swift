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
        // 起こし終えた知らせは裏のスレッドに届く。端末から動かしたときはメインの run loop に入力が無く、メインに渡すと届かないので、鍵をかけた箱で受ける
        nonisolated final class Launch: @unchecked Sendable {
            private let lock = NSLock()
            private var result: (pid: pid_t?, failure: String?)?
            func finish(pid: pid_t?, failure: String?) { lock.withLock { result = (pid, failure) } }
            var finished: (pid: pid_t?, failure: String?)? { lock.withLock { result } }
        }
        let launch = Launch()
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = arguments
        configuration.createsNewApplicationInstance = true
        configuration.addsToRecentItems = false
        configuration.activates = false
        NSWorkspace.shared.openApplication(at: helper, configuration: configuration) { app, error in
            launch.finish(pid: app?.processIdentifier, failure: error?.localizedDescription)
        }
        let deadline = Date().addingTimeInterval(60)
        while launch.finished == nil {
            guard Date() < deadline else {
                print("インストーラーを起動できない: 60 秒待っても起動しなかった")
                return 1
            }
            usleep(100_000)
        }
        if let failure = launch.finished?.failure {
            print("インストーラーを起動できない: \(failure)")
            return 1
        }
        // インストーラーが終わるのを待つ。入れ替えは長くても数十秒
        guard let pid = launch.finished?.pid else {
            print("インストーラーを起動したが、プロセスが分からない")
            return 1
        }
        print("== インストーラーを起動した（pid \(pid)）")
        do {
            let deadline = Date().addingTimeInterval(10 * 60)
            // プロセスが無くなれば ESRCH が返る。サンドボックスの中からは、生きているほかのプロセスには EPERM が返る
            while kill(pid, 0) == 0 || errno != ESRCH {
                guard Date() < deadline else {
                    print("インストーラーが 10 分たっても終わらない")
                    return 1
                }
                usleep(200_000)
            }
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
