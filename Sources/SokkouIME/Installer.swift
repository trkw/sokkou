import AppKit
import Carbon

/// dmg などから開かれたときに、自分を ~/Library/Input Methods に入れて入力ソースとして登録し、有効にする。
/// 入れ替える前の版は ~/Library/Application Support/sokkou/previous に取っておき、入れ替えや起動でしくじったらそれに戻す
enum Installer {
    static let inputMethods = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Input Methods", isDirectory: true)
    static let support = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/sokkou", isDirectory: true)
    /// 1 つ前の版。入力メニューの「前の版に戻す」はこれを入れる
    static var previous: URL {
        support.appendingPathComponent("previous", isDirectory: true).appendingPathComponent(Bundle.main.bundleURL.lastPathComponent)
    }
    private static var staging: URL {
        support.appendingPathComponent("previous-staging", isDirectory: true).appendingPathComponent(Bundle.main.bundleURL.lastPathComponent)
    }

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
        let firstTime = !FileManager.default.fileExists(atPath: destination.path)
        do {
            try install(from: source, to: destination)
        } catch {
            if interactive {
                alert("\(name) を入れられませんでした", "\(error.localizedDescription)")
            } else {
                print("インストールに失敗: \(error.localizedDescription)")
            }
            return 1
        }
        print("== 配置 \(destination.path)")
        // 初めて入れたときと、dmg から開いて入れたときは、入力ソースの一覧に足す。
        // 更新のたびには足さない。利用者が外したものを勝手に戻さないため
        let selectable = firstTime || interactive ? enableInputSources() : nil
        guard interactive else { return 0 }
        if let selectable {
            let choice = alert(
                "\(name) を入れました",
                """
                入力ソースに \(name) を足しました。メニューバーの入力メニューからいつでも選べます。

                新しい版が出ると、打っていないときに自動で入れ替わります。入力メニューから止められます。
                """,
                buttons: ["\(name) に切り替える", "閉じる"]
            )
            if choice == .alertFirstButtonReturn {
                TISSelectInputSource(selectable)
            }
        } else {
            // macOS がまだ入力ソースの一覧に載せていない（入れた直後に一覧が作り直されていない）とき
            let choice = alert(
                "\(name) を入れました",
                """
                システム設定 → キーボード → 入力ソース → 編集 → 「+」→ 日本語 から「\(name)」を足すと使えます。

                一覧に見当たらないときは、いったんログアウトしてログインし直してください。
                """,
                buttons: ["入力ソースの設定を開く", "閉じる"]
            )
            if choice == .alertFirstButtonReturn {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!)
            }
        }
        return 0
    }

    /// 入力ソースから外し、~/Library/Input Methods と取っておいた前の版を消す。purge なら覚えた候補と設定も消す
    static func uninstall(purge: Bool) -> Int32 {
        guard let id = Bundle.main.bundleIdentifier else { return 1 }
        let destination = inputMethods.appendingPathComponent(Bundle.main.bundleURL.lastPathComponent)
        selectOther(than: id)
        for source in inputSources(id) {
            TISDisableInputSource(source)
        }
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: id) where app != .current {
            app.forceTerminate()
        }
        let fileManager = FileManager.default
        var removed = [destination, previous.deletingLastPathComponent(), staging.deletingLastPathComponent()]
        if purge {
            removed.append(support)
            UserDefaults.standard.removePersistentDomain(forName: id)
        }
        for url in removed where fileManager.fileExists(atPath: url.path) {
            do {
                try fileManager.removeItem(at: url)
                print("== 削除 \(url.path)")
            } catch {
                print("消せない: \(url.path) \(error.localizedDescription)")
                return 1
            }
        }
        try? run(lsregister, ["-u", destination.path])
        print(purge ? "== \(name) を取り除いた" : "== \(name) を取り除いた。覚えた候補は \(support.path) に残した")
        return 0
    }

    private static var name: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "sokkou"
    }

    private static let lsregister =
        "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

    private static func install(from source: URL, to destination: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: inputMethods, withIntermediateDirectories: true)
        // 今の版を取っておく。入れ替えに成功したら「前の版」にする
        let hadPrevious = fileManager.fileExists(atPath: destination.path)
        if hadPrevious {
            try? fileManager.removeItem(at: staging)
            try fileManager.createDirectory(at: staging.deletingLastPathComponent(), withIntermediateDirectories: true)
            try run("/usr/bin/ditto", [destination.path, staging.path])
        }
        // 動いている古い版を止める。止めたら、入れ終えたあとに新しい版を起動し直す
        var stopped: [pid_t] = []
        if let id = Bundle.main.bundleIdentifier {
            for app in NSRunningApplication.runningApplications(withBundleIdentifier: id) where app != .current {
                app.forceTerminate()
                stopped.append(app.processIdentifier)
            }
        }
        waitUntilExited(stopped)

        do {
            try place(source, at: destination)
        } catch {
            if hadPrevious {
                print("== 入れ替えに失敗したので戻す: \(error.localizedDescription)")
                try? place(staging, at: destination)
                if !stopped.isEmpty {
                    try? run("/usr/bin/open", ["-g", destination.path])
                }
            }
            throw error
        }

        // 使っていた版を止めたときだけ起こす。ログインし直さなくても、次の打鍵から新しい版が受ける
        if !stopped.isEmpty {
            let launched = (try? run("/usr/bin/open", ["-g", destination.path])) != nil
            reselectIfCurrent()
            // 起こせたのにすぐ落ちる版なら、取っておいた版に戻す
            if launched, hadPrevious, !staysRunning(destination) {
                print("== 新しい版が起動しないので戻す")
                try? place(staging, at: destination)
                try? run("/usr/bin/open", ["-g", destination.path])
                reselectIfCurrent()
                throw InstallError("新しい版が起動しなかったので、前の版に戻しました")
            }
            print("== 起動 \(destination.path)")
        }

        if hadPrevious {
            // 前の版から戻したときは、取っておいた版がその前の版と入れ替わる
            let folder = previous.deletingLastPathComponent()
            try? fileManager.removeItem(at: folder)
            try? fileManager.moveItem(at: staging.deletingLastPathComponent(), to: folder)
        }
    }

    /// source の中身を destination に置いて、入力ソースとして登録する
    private static func place(_ source: URL, at destination: URL) throws {
        // バンドルを消さずに中身を入れ替える。バンドルが無い瞬間に macOS が入力ソースの一覧を作り直すと登録が消えるため
        try run("/usr/bin/rsync", ["-a", "--delete", source.path + "/", destination.path + "/"])
        // ダウンロードした dmg から入れたときの隔離の属性を外す。ad-hoc 署名なので、付いたままだと入力メソッドとして起動できない
        try? run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", destination.path])
        try run(lsregister, ["-f", destination.path])
        let status = TISRegisterInputSource(destination as CFURL)
        guard status == noErr else {
            throw InstallError("入力ソースとして登録できない（\(status)）")
        }
    }

    /// 起動した版が 5 秒のうちに現れ、さらに 2 秒動き続けるか。辞書を読めずに落ちる版を見つける
    private static func staysRunning(_ app: URL) -> Bool {
        let binary = app.appendingPathComponent("Contents/MacOS/sokkou").path
        func running() -> Bool { (try? run("/usr/bin/pgrep", ["-f", binary])) != nil }
        let deadline = Date().addingTimeInterval(5)
        while !running() {
            guard Date() < deadline else { return false }
            usleep(200_000)
        }
        sleep(2)
        return running()
    }

    /// このバンドルの入力ソースを有効にし、選べるものを返す
    private static func enableInputSources() -> TISInputSource? {
        guard let id = Bundle.main.bundleIdentifier else { return nil }
        var selectable: TISInputSource?
        for source in inputSources(id) {
            if property(source, kTISPropertyInputSourceIsEnableCapable) as? Bool == true,
               property(source, kTISPropertyInputSourceIsEnabled) as? Bool != true {
                let status = TISEnableInputSource(source)
                print("== 有効にする \(property(source, kTISPropertyInputSourceID) as? String ?? "?") -> \(status)")
            }
            if selectable == nil, property(source, kTISPropertyInputSourceIsSelectCapable) as? Bool == true {
                selectable = source
            }
        }
        return selectable
    }

    /// このバンドルの入力ソース。有効にしていないものも含める
    private static func inputSources(_ id: String) -> [TISInputSource] {
        let filter = [kTISPropertyBundleID as String: id] as CFDictionary
        return TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource] ?? []
    }

    /// 選んでいる入力ソースが sokkou なら、いったん別のものにしてから選び直す。
    /// 止めた版につながったままのアプリは、そのままだと入力ソースを切り替えるまで何も打てないため
    private static func reselectIfCurrent() {
        guard let id = Bundle.main.bundleIdentifier,
              let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              property(current, kTISPropertyBundleID) as? String == id,
              let sourceID = property(current, kTISPropertyInputSourceID) as? String
        else { return }
        guard selectOther(than: id) else { return }
        usleep(300_000)
        let again = TISCreateInputSourceList([kTISPropertyInputSourceID as String: sourceID] as CFDictionary, false)?
            .takeRetainedValue() as? [TISInputSource]
        TISSelectInputSource(again?.first ?? current)
        print("== 選び直し \(sourceID)")
    }

    /// 選んでいる入力ソースが id のものなら、ほかのキーボードの入力ソースを選ぶ。選び替えたら true
    @discardableResult
    private static func selectOther(than id: String) -> Bool {
        guard let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              property(current, kTISPropertyBundleID) as? String == id
        else { return false }
        let filter = [
            kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource as String,
            kTISPropertyInputSourceIsSelectCapable as String: true,
        ] as CFDictionary
        let sources = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource] ?? []
        guard let other = sources.first(where: { property($0, kTISPropertyBundleID) as? String != id }) else { return false }
        return TISSelectInputSource(other) == noErr
    }

    private static func property(_ source: TISInputSource, _ key: CFString) -> Any? {
        guard let raw = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<AnyObject>.fromOpaque(raw).takeUnretainedValue()
    }

    /// 止めたプロセスが消えるのを 3 秒まで待つ。残っているうちに起動すると、LaunchServices が古いほうを使おうとする
    private static func waitUntilExited(_ pids: [pid_t]) {
        let deadline = Date().addingTimeInterval(3)
        while pids.contains(where: { kill($0, 0) == 0 }), Date() < deadline {
            usleep(50_000)
        }
    }

    private static func run(_ tool: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw InstallError("\((tool as NSString).lastPathComponent) が失敗した（\(process.terminationStatus)）")
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
}

struct InstallError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}
