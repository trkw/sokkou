import AppKit

/// 入力メニューと自動の更新から新しい版に入れ替える。中身は .app に入れた install.sh（Resources/update.sh）で、
/// 取ってきた版の --install がこのプロセスを止めて、入れた版を起動し直す。
/// 入れ替わったら新しい版が、しくじったら残っているこの版が、窓で知らせる
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

    /// 取っておいた 1 つ前の版のビルド。無ければ nil
    static var previousBuild: String? {
        guard let info = NSDictionary(contentsOf: Installer.previous.appendingPathComponent("Contents/Info.plist")) else { return nil }
        return info["SokkouBuild"] as? String ?? info["CFBundleShortVersionString"] as? String
    }

    static let log = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/sokkou-update.log")

    /// 最新のリリースか、pr を渡したらその PR の CI のビルドを入れる
    static func install(pr: Int? = nil) {
        var arguments = ["--notify"]
        if let pr {
            arguments += ["--pr", String(pr)]
        }
        runScript(arguments, reason: pr.map { "PR #\($0) の版を入れる" } ?? "最新版に更新")
    }

    /// 取っておいた 1 つ前の版に戻す。戻した版は、自動の更新でもう一度入れない
    static func rollback() {
        if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String, build.hasPrefix("v") {
            Settings.skippedRelease = version
        }
        runScript(["--notify", Installer.previous.path], reason: "前の版に戻す")
    }

    /// quiet なら、しくじっても窓を出さない（自動の更新。ログには残り、次に確かめたときにまた試す）
    private static func runScript(_ arguments: [String], reason: String, quiet: Bool = false) {
        guard let script = Bundle.main.url(forResource: "update", withExtension: "sh") else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script.path] + arguments
        if let handle = openLog() {
            handle.write(Data("\n==== \(Date().formatted(.iso8601)) \(reason)（\(build) から）\n".utf8))
            process.standardOutput = handle
            process.standardError = handle
        }
        // 入れ替えられたらこのプロセスは止められ、新しい版が updated.txt を読んで知らせる。
        // 入れられなかったときはこのプロセスが残るので、ここで知らせる（通知は許可が無いと出ないため）
        process.terminationHandler = { finished in
            guard finished.terminationStatus != 0, !quiet else { return }
            Task { @MainActor in reportFailure() }
        }
        do {
            try process.run()
        } catch {
            alert("更新を始められませんでした", error.localizedDescription)
        }
    }

    /// 更新のたびに書き足す。512 KB を超えたら古いほうの半分を捨てる
    private static func openLog() -> FileHandle? {
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: log.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let size = (try? fileManager.attributesOfItem(atPath: log.path))?[.size] as? Int, size > 512 * 1024,
           let data = try? Data(contentsOf: log) {
            try? data.suffix(256 * 1024).write(to: log)
        }
        if !fileManager.fileExists(atPath: log.path) {
            fileManager.createFile(atPath: log.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: log) else { return nil }
        handle.seekToEndOfFile()
        return handle
    }

    /// install.sh が入れ替える直前に書く。起動し直した新しい版が読んで、入れ替わったことを知らせる
    static let updatedNote = Installer.support.appendingPathComponent("updated.txt")

    /// 入れ替わった直後の起動なら、どの版になったかを知らせる
    static func reportUpdate() {
        let path = updatedNote.path
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let written = attributes[.modificationDate] as? Date,
              let note = try? String(contentsOfFile: path, encoding: .utf8)
        else { return }
        try? FileManager.default.removeItem(atPath: path)
        // 古いものは、入れ替えの途中で止まった跡なので知らせない
        guard Date().timeIntervalSince(written) < 5 * 60 else { return }
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                alert(note.trimmingCharacters(in: .whitespacesAndNewlines), "入力メニューにも、いま動いているビルドが出ます。")
            }
        }
    }

    /// ログの最後の「失敗: 」の行を出す。無ければ最後の 3 行
    private static func reportFailure() {
        let text = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
        let lines = text.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
        let reason = lines.last { $0.contains("失敗: ") }.map { String($0[$0.range(of: "失敗: ")!.upperBound...]) }
            ?? lines.suffix(3).joined(separator: "\n")
        alert("更新できませんでした", "\(reason)\n\n今の版（\(build)）のまま使えます。詳しくは ~/Library/Logs/sokkou-update.log")
    }

    private static func alert(_ title: String, _ message: String) {
        Installer.alert(title, message)
        Installer.stepBack()
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
        Installer.stepBack()
        let text = field.stringValue.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard response == .alertFirstButtonReturn, let pr = Int(text), pr > 0 else { return }
        install(pr: pr)
    }

    /// 確かめてから取り除く。取り除いたらこのプロセスも終える
    static func askAndUninstall() {
        NSApplication.shared.setActivationPolicy(.accessory)
        NSApplication.shared.activate(ignoringOtherApps: true)
        let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "sokkou"
        let alert = NSAlert()
        alert.messageText = "\(name) を取り除きますか？"
        alert.informativeText = "入力ソースから外し、~/Library/Input Methods の \(name) と取っておいた前の版を消します。"
        let purge = NSButton(checkboxWithTitle: "覚えた候補と設定も消す", target: nil, action: nil)
        alert.accessoryView = purge
        alert.addButton(withTitle: "取り除く")
        alert.addButton(withTitle: "やめる")
        alert.alertStyle = .warning
        let response = alert.runModal()
        Installer.stepBack()
        guard response == .alertFirstButtonReturn else { return }
        exit(Installer.uninstall(purge: purge.state == .on))
    }

    // MARK: 自動の更新

    /// 最後にキーを受けた時刻。打っている途中で入れ替えて、未確定の文字列を失わないようにする
    private static var lastKey = Date()
    /// 見つけた新しいリリースのタグ。打たない時間が続いたら入れる
    private static var pending: String?
    private static var lastCheck = Date.distantPast
    private static var timer: Timer?

    /// 1 時間ごとに確かめる。GitHub の API は認証なしだと 1 時間に 60 回まで
    private static let checkInterval: TimeInterval = 60 * 60
    /// これだけ打たなければ入れ替える
    private static let idleInterval: TimeInterval = 2 * 60

    static func noteKey() {
        lastKey = Date()
    }

    /// リリースの版（v0.1.7 など）で動いているときだけ自動で更新する。
    /// PR の版や手元の版を試している途中に、最新のリリースへ戻してしまわないため
    private static var releaseVersion: [Int]? {
        guard isAvailable, build.hasPrefix("v"),
              let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        else { return nil }
        return numbers(version)
    }

    static func startAutoUpdate() {
        guard releaseVersion != nil, timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            MainActor.assumeIsolated { tick() }
        }
        tick()
    }

    private static func tick() {
        guard Settings.autoUpdates else { return }
        if let tag = pending {
            if Date().timeIntervalSince(lastKey) >= idleInterval {
                pending = nil
                runScript(["--notify"], reason: "自動で \(tag) に更新", quiet: true)
            }
        } else if Date().timeIntervalSince(lastCheck) >= checkInterval {
            lastCheck = Date()
            Task { await check() }
        }
    }

    private static func check() async {
        guard let current = releaseVersion else { return }
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/trkw/sokkou/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let fetched = try? await URLSession.shared.data(for: request),
              (fetched.1 as? HTTPURLResponse)?.statusCode == 200,
              let release = (try? JSONSerialization.jsonObject(with: fetched.0)) as? [String: Any],
              let tag = release["tag_name"] as? String
        else { return }
        let version = String(tag.drop { $0 == "v" })
        // 前の版に戻したときの版は、もう一度は入れない。それより新しい版が出たら入れる
        guard version != Settings.skippedRelease else { return }
        guard current.lexicographicallyPrecedes(numbers(version)) else { return }
        pending = tag
    }

    private static func numbers(_ version: String) -> [Int] {
        version.split(separator: ".").map { Int($0) ?? 0 }
    }
}
