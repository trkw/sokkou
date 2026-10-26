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
    /// sokkou はサンドボックスの中で、入れ物の外に書くインストーラーを自分では起こせないので、.app に入れた XPC サービス（SokkouLauncher）に頼む。
    /// launched は起こせたかどうかにかかわらず、起こし終えたあとに呼ぶ
    static func launch(_ arguments: [String], launched: (@MainActor () -> Void)? = nil) {
        call(arguments, wait: false) { status, message in
            Task { @MainActor in
                if status != 0 {
                    alert("sokkou のインストーラーを起動できませんでした", message ?? "終わりの状態 \(status)")
                    stepBack()
                }
                launched?()
            }
        }
    }

    /// 端末から動かしたとき（Homebrew、Nix、インストーラーを持たない前の版の install.sh が動かす --install・--uninstall）。
    /// XPC サービスがインストーラーを動かして終わるのを待ち、その終わりの状態を返す
    static func run(_ arguments: [String]) -> Int32 {
        nonisolated final class Result: @unchecked Sendable {
            let done = DispatchSemaphore(value: 0)
            var status: Int32 = 1
            var message: String?
        }
        let result = Result()
        call(arguments, wait: true) { status, message in
            result.status = status
            result.message = message
            result.done.signal()
        }
        guard result.done.wait(timeout: .now() + 10 * 60) == .success else {
            print("インストーラーが 10 分たっても終わらない")
            return 1
        }
        if let message = result.message {
            print(message)
        }
        return result.status
    }

    /// XPC サービスにインストーラーを動かすよう頼む。reply は裏のスレッドで 1 度だけ呼ばれる
    private static func call(_ arguments: [String], wait: Bool, reply: @escaping @Sendable (Int32, String?) -> Void) {
        nonisolated(unsafe) let connection = NSXPCConnection(serviceName: "\(Bundle.main.bundleIdentifier ?? "sokkou").launcher")
        connection.remoteObjectInterface = NSXPCInterface(with: Launcher.self)
        connection.resume()
        let proxy = connection.remoteObjectProxyWithErrorHandler { error in
            reply(1, "インストーラーを頼む XPC サービスにつながらない: \(error.localizedDescription)")
        } as? Launcher
        guard let proxy else {
            reply(1, "インストーラーを頼む XPC サービスが分からない")
            return
        }
        proxy.run(arguments, wait: wait) { status, message in
            reply(status, message)
            connection.invalidate()
        }
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

/// XPC サービス（Sources/SokkouLauncher）に頼むこと。向こうの宣言と同じ形にする
@objc nonisolated protocol Launcher {
    func run(_ arguments: [String], wait: Bool, reply: @escaping @Sendable (Int32, String?) -> Void)
}

/// 本当のホームフォルダ。App Sandbox の中でも、入れ物（~/Library/Containers）ではなくこちらを指す
let home = URL(fileURLWithPath: String(cString: getpwuid(getuid())!.pointee.pw_dir), isDirectory: true)

struct InstallError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}
