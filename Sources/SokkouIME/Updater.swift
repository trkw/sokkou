import AppKit

/// 入力メニューから新しい版に入れ替える。中身は .app に入れた install.sh（Resources/update.sh）で、
/// 取ってきた版の --install がこのプロセスを止めて、入れた版を起動し直す。結果は通知で出る
enum Updater {
    /// 入力メニューに出す、どのビルドか（例: v0.1.7 · abc1234、PR #4 · abc1234）
    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "SokkouBuild") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "?"
    }

    /// 更新は普段使いの版だけにする。開発版を入れ替えると、普段使いの版を上書きしてしまう
    static var isAvailable: Bool {
        Bundle.main.bundleIdentifier?.hasSuffix(".dev") == false
            && Bundle.main.url(forResource: "update", withExtension: "sh") != nil
    }

    /// 最新のリリースか、pr を渡したらその PR の CI のビルドを入れる
    static func install(pr: Int? = nil) {
        guard let script = Bundle.main.url(forResource: "update", withExtension: "sh") else { return }
        var arguments = [script.path, "--notify"]
        if let pr {
            arguments += ["--pr", String(pr)]
        }
        let logs = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs", isDirectory: true)
        let log = logs.appendingPathComponent("sokkou-update.log")
        try? FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: log.path, contents: nil)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = arguments
        if let handle = try? FileHandle(forWritingTo: log) {
            process.standardOutput = handle
            process.standardError = handle
        }
        // 待たない。入れ替えの途中でこのプロセスは止められ、スクリプトはそのまま最後まで動く
        try? process.run()
    }

    /// PR の番号を尋ねてから入れる
    static func askAndInstallPR() {
        NSApplication.shared.setActivationPolicy(.accessory)
        NSApplication.shared.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "PR の版を入れる"
        alert.informativeText = "PR の番号を入れると、その PR の CI が組み立てた版に入れ替えます。最新のリリースに戻すときは「最新版に更新」を選びます。"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        field.placeholderString = "例: 4"
        alert.accessoryView = field
        alert.addButton(withTitle: "入れる")
        alert.addButton(withTitle: "やめる")
        alert.window.initialFirstResponder = field
        let response = alert.runModal()
        NSApplication.shared.setActivationPolicy(.prohibited)
        let text = field.stringValue.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard response == .alertFirstButtonReturn, let pr = Int(text), pr > 0 else { return }
        install(pr: pr)
    }
}
