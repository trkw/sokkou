import AppKit
import SokkouCore

/// 辞書のファイルの置き場所と、入力メニューからの辞書の出し入れ。
/// ユーザー辞書は ~/Library/Application Support/sokkou/skk-jisyo.utf8（SKK 形式）、
/// 追加の SKK 辞書は同じところの Dictionaries フォルダに置き、中のファイルをすべて読む
enum Dictionaries {
    private static let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("sokkou", isDirectory: true)
    static let userURL = folder.appendingPathComponent("skk-jisyo.utf8")
    static let directory = folder.appendingPathComponent("Dictionaries", isDirectory: true)
    /// skk-dev の SKK-JISYO.L（EUC-JP のまま置く）
    private static let largeURL = URL(string: "https://raw.githubusercontent.com/skk-dev/dict/master/SKK-JISYO.L")!

    /// 追加の SKK 辞書を別のスレッドで読み直す。読み終えるまでは前の辞書のまま変換する
    static func reload() {
        let directory = directory
        Task.detached(priority: .utility) {
            let systems = SKKDictionary.load(directory: directory)
            await MainActor.run { sharedLexicon.systems = systems }
        }
    }

    static func downloadLarge() {
        let destination = directory.appendingPathComponent("SKK-JISYO.L")
        Task {
            do {
                let (file, response) = try await URLSession.shared.download(from: largeURL)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
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
        let home = FileManager.default.homeDirectoryForCurrentUser
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
        defer { NSApplication.shared.setActivationPolicy(.prohibited) }
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
        NSApplication.shared.setActivationPolicy(.prohibited)
    }
}
