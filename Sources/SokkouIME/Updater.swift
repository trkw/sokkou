import AppKit

/// 入力メニューと自動の更新から新しい版に入れ替える。入れ替えは .app に入れたインストーラー（Installer.helper）に頼む。
/// インストーラーが取ってきた版を確かめてこのプロセスを止め、入れた版を起動し直す。
/// 入れ替わったら新しい版が、しくじったらインストーラーが、窓で知らせる
enum Updater {
    /// 入力メニューに出す、どのビルドか（例: v0.1.7 · abc1234、PR #4 · abc1234）
    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "SokkouBuild") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "?"
    }

    /// 更新は普段使いの版だけにする。開発版を入れ替えると、普段使いの版を上書きしてしまう
    static var isAvailable: Bool {
        Bundle.main.bundleIdentifier?.hasSuffix(".dev") == false && Installer.hasHelper
    }

    /// 最新のリリースか、pr を渡したらその PR の CI のビルドを入れる
    static func install(pr: Int? = nil) {
        Installer.launch(["--update"] + (pr.map { ["--pr", String($0)] } ?? []))
    }

    /// 取っておいた 1 つ前の版に戻す。戻した版は、自動の更新でもう一度入れない
    static func rollback() {
        if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String, build.hasPrefix("v") {
            Settings.skippedRelease = version
        }
        Installer.launch(["--update", "--rollback"])
    }

    /// 前に動いたのと違うビルドで起動したら、どの版になったかを知らせる。初めて入れたときは知らせない
    static func reportUpdate() {
        let last = Settings.lastBuild
        Settings.lastBuild = build
        guard let last, last != build else { return }
        let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "sokkou"
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                alert("\(name) を \(build) にしました", "入力メニューにも、いま動いているビルドが出ます。")
            }
        }
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
        if purge.state == .on {
            Settings.purge(support: Dictionaries.folder)
        }
        Installer.launch(["--uninstall"] + (purge.state == .on ? ["--purge"] : []))
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
                Installer.launch(["--update", "--quiet", "--reason", "自動で \(tag) に更新"])
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
