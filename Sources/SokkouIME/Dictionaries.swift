import AppKit
import CryptoKit
import SokkouCore

/// 辞書のファイルの置き場所と、入力メニューからの辞書の出し入れ。
/// ユーザー辞書は Application Support/sokkou/skk-jisyo.utf8（SKK 形式）、
/// 追加の SKK 辞書は同じところの Dictionaries フォルダに置き、中のファイルをすべて読む。
/// sokkou は App Sandbox で動くので、Application Support は入れ物の中（~/Library/Containers/<bundle id>/Data/Library）を指す
enum Dictionaries {
    static let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("sokkou", isDirectory: true)
    /// 設定の窓に出す置き場所。ホームフォルダは ~ と書く
    static var folderForDisplay: String {
        folder.path.replacingOccurrences(of: home.path, with: "~", options: .anchored)
    }
    static let userURL = folder.appendingPathComponent("skk-jisyo.utf8")
    static let directory = folder.appendingPathComponent("Dictionaries", isDirectory: true)
    /// skk-dev の SKK-JISYO.L（EUC-JP のまま置く）。取る版をコミットで固定し、中身を SHA-256 で確かめる。
    /// 変換の候補にそのまま出る語なので、書き換えられたものや壊れたものは入れない。
    /// 新しい版は upstream-watch が知らせる。上げるときは largeRevision と largeSHA256 を一緒に書き換える
    static let largeRevision = "0a164e6b990c5eb5b59eb7d8789f08865dc2f644"
    private static let largeSHA256 = "c791f578d1b4040fce282db29bc22b2cc7ea46f83e269fab2e0fa779e2967e40"
    private static let largeURL = URL(string: "https://raw.githubusercontent.com/skk-dev/dict/\(largeRevision)/SKK-JISYO.L")!

    /// 追加の SKK 辞書を別のスレッドで読み直す。読み終えるまでは前の辞書のまま変換する
    static func reload() {
        let directory = directory
        Task.detached(priority: .utility) {
            let systems = SKKDictionary.load(directory: directory)
            await MainActor.run { sharedLexicon.systems = systems }
        }
    }

    /// Dictionaries フォルダに置いてある辞書のファイルの名前。設定の「辞書」に並べる
    static func installed() -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.filter { !$0.hasPrefix(".") }.sorted()
    }

    static let largeName = "SKK-JISYO.L"

    static func downloadLarge() {
        let destination = directory.appendingPathComponent(largeName)
        Task {
            do {
                let (file, response) = try await URLSession.shared.download(from: largeURL)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
                let digest = SHA256.hash(data: try Data(contentsOf: file)).map { String(format: "%02x", $0) }.joined()
                guard digest == largeSHA256 else {
                    try? FileManager.default.removeItem(at: file)
                    throw InstallError("取ってきた SKK-JISYO.L の SHA-256 が合いません。途中で書き換えられたか壊れています。")
                }
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.moveItem(at: file, to: destination)
                reload()
                alert("SKK-JISYO.L を入れました", "変換の候補に SKK-JISYO.L の語が加わります（▽ の候補と、文節選択の候補の後ろ）。")
            } catch {
                alert("SKK-JISYO.L を入れられませんでした", error.localizedDescription)
            }
        }
    }

    static func add() {
        guard let urls = choose("追加する SKK 辞書を選んでください（SKK-JISYO.L、SKK-JISYO.jinmei など）", multiple: true) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var added: [String] = []
        for url in urls {
            guard let dictionary = SKKDictionary(url: url), !dictionary.isEmpty else { continue }
            let destination = directory.appendingPathComponent(url.lastPathComponent)
            // もう入っている辞書を選んだら、消してしまわずにそのまま読み直す
            if url.standardizedFileURL.resolvingSymlinksInPath() == destination.standardizedFileURL.resolvingSymlinksInPath() {
                added.append(url.lastPathComponent)
                continue
            }
            try? FileManager.default.removeItem(at: destination)
            if (try? FileManager.default.copyItem(at: url, to: destination)) != nil {
                added.append(url.lastPathComponent)
            }
        }
        reload()
        if added.isEmpty {
            alert("SKK 辞書を追加できませんでした", "SKK 形式（UTF-8 か EUC-JP）の辞書を選んでください。")
        } else {
            alert("SKK 辞書を追加しました", added.joined(separator: "、"))
        }
    }

    /// ほかの SKK のユーザー辞書の語を、sokkou のユーザー辞書に足す
    static func importUserDictionary() {
        let macSKK = home.appendingPathComponent("Library/Containers/net.mtgto.inputmethod.macSKK/Data/Documents/Dictionaries", isDirectory: true)
        let start = FileManager.default.fileExists(atPath: macSKK.path) ? macSKK : home
        guard let url = choose("取り込む SKK のユーザー辞書を選んでください（~/.skk-jisyo、macSKK の skk-jisyo.utf8 など）", multiple: false, in: start)?.first
        else { return }
        guard let added = sharedLexicon.user.merge(contentsOf: url) else {
            alert("取り込めませんでした", "\(url.lastPathComponent) を SKK 形式の辞書として読めませんでした。")
            return
        }
        alert("ユーザー辞書を取り込みました", "\(url.lastPathComponent) から \(added) 語を足しました。")
    }

    static func openFolder() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(folder)
    }

    // MARK: 窓

    private static func choose(_ message: String, multiple: Bool, in start: URL? = nil) -> [URL]? {
        NSApplication.shared.setActivationPolicy(.accessory)
        NSApplication.shared.activate(ignoringOtherApps: true)
        defer { Installer.stepBack() }
        let panel = NSOpenPanel()
        panel.message = message
        panel.allowsMultipleSelection = multiple
        panel.canChooseDirectories = false
        // ~/.skk-jisyo は隠しファイルなので見せる
        panel.showsHiddenFiles = true
        panel.directoryURL = start
        return panel.runModal() == .OK ? panel.urls : nil
    }

    private static func alert(_ title: String, _ text: String) {
        NSApplication.shared.setActivationPolicy(.accessory)
        NSApplication.shared.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.runModal()
        Installer.stepBack()
    }
}
