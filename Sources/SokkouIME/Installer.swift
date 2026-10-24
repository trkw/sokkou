import AppKit
import Carbon

/// dmg などから開かれたときに、自分を ~/Library/Input Methods に入れて入力ソースとして登録する
enum Installer {
    static let inputMethods = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Input Methods", isDirectory: true)

    /// 入力メソッドの置き場所から起動したか。そこ以外（dmg、ダウンロード、dist）から開かれたらインストールする
    static var isInstalled: Bool {
        let folder = Bundle.main.bundleURL.resolvingSymlinksInPath().deletingLastPathComponent().path
        let places = [inputMethods, URL(fileURLWithPath: "/Library/Input Methods")]
        return places.contains { $0.resolvingSymlinksInPath().path == folder }
    }

    /// 入れて、次にすることを伝える。interactive でなければ結果を標準出力に書くだけにする
    static func run(interactive: Bool) -> Int32 {
        let source = Bundle.main.bundleURL
        let destination = inputMethods.appendingPathComponent(source.lastPathComponent)
        do {
            try install(from: source, to: destination)
        } catch {
            if interactive {
                alert("sokkou を入れられませんでした", "\(error.localizedDescription)")
            } else {
                print("インストールに失敗: \(error)")
            }
            return 1
        }
        print("== 配置 \(destination.path)")
        guard interactive else { return 0 }
        let open = alert(
            "sokkou を入れました",
            """
            初めて入れたときは、いったんログアウトしてログインし直してください。

            そのあと、システム設定 → キーボード → 入力ソース → 編集 → 「+」→ 日本語 から「\(name)」を追加すると使えます。前の版の「\(name) (英数)」「\(name) (日本語)」が残っていたら、外してから追加し直してください。

            新しい版に入れ替えたときは、そのまま使えます。
            """,
            buttons: ["入力ソースの設定を開く", "閉じる"]
        )
        if open == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!)
        }
        return 0
    }

    private static var name: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "sokkou"
    }

    private static func install(from source: URL, to destination: URL) throws {
        try FileManager.default.createDirectory(at: inputMethods, withIntermediateDirectories: true)
        // 動いている古い版を止める。次に入力ソースが選ばれたときに新しい版が起動する
        if let id = Bundle.main.bundleIdentifier {
            for app in NSRunningApplication.runningApplications(withBundleIdentifier: id) where app != .current {
                app.forceTerminate()
            }
        }
        // バンドルを消さずに中身を入れ替える。バンドルが無い瞬間に macOS が入力ソースの一覧を作り直すと登録が消えるため
        try run("/usr/bin/rsync", ["-a", "--delete", source.path + "/", destination.path + "/"])
        // ダウンロードした dmg から入れたときの隔離の属性を外す。ad-hoc 署名なので、付いたままだと入力メソッドとして起動できない
        try? run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", destination.path])
        try run(
            "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister",
            ["-f", destination.path]
        )
        let status = TISRegisterInputSource(destination as CFURL)
        guard status == noErr else {
            throw InstallError("入力ソースとして登録できない（\(status)）")
        }
        disableRetiredSources()
    }

    /// 前の版にあった英数の入力ソース（接尾辞 .Roman）が有効のまま残っていたら外す。いまは入力ソースを 1 つにまとめている
    private static func disableRetiredSources() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let filter = [kTISPropertyBundleID as String: bundleID] as CFDictionary
        guard let list = TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource] else { return }
        for source in list {
            guard let raw = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { continue }
            let id = Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
            if id.hasSuffix(".Roman") {
                TISDisableInputSource(source)
            }
        }
    }

    private static func run(_ tool: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw InstallError("\((tool as NSString).lastPathComponent) が失敗した（\(process.terminationStatus)）")
        }
    }

    @discardableResult
    private static func alert(_ title: String, _ message: String, buttons: [String] = ["閉じる"]) -> NSApplication.ModalResponse {
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
}

struct InstallError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}
