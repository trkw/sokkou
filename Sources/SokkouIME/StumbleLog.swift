import AppKit
import SokkouCore

/// 打っていてつまづいたところの記録。設定でオンにしたときだけ、~/Library/Logs/sokkou-stumbles.jsonl に 1 行ずつ足す。
/// 打った文字は「読みと候補も残す」をオンにしたときだけ残す。記録は Mac の外には出さない
enum StumbleLog {
    struct Record: Codable {
        var at: Date
        var build: String
        /// 入力欄のアプリのバンドル ID
        var app: String?
        /// 賢い変換で選んでいるモデル。nil なら azooKey の辞書だけ。遅かったときに、どの変換で遅いのかを見分ける
        var model: String?
        var stumble: Stumble
    }

    static let file = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Logs/sokkou-stumbles.jsonl")
    /// これを超えたら古いほうを 1 つ取っておいて作り直す
    private static let limit = 2_000_000

    static var isOn: Bool { Settings.recordsStumbles }

    static func write(_ stumbles: [Stumble], app: String?) {
        guard isOn, !stumbles.isEmpty else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .sortedKeys
        let model = ConversionModel.selected?.id
        var lines = Data()
        for stumble in stumbles {
            guard let line = try? encoder.encode(Record(at: Date(), build: Updater.build, app: app, model: model, stumble: stumble)) else { continue }
            lines.append(line)
            lines.append(0x0A)
        }
        append(lines)
    }

    private static func append(_ data: Data) {
        let manager = FileManager.default
        try? manager.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let size = (try? manager.attributesOfItem(atPath: file.path))?[.size] as? Int, size > limit {
            let old = file.appendingPathExtension("1")
            try? manager.removeItem(at: old)
            try? manager.moveItem(at: file, to: old)
        }
        guard manager.fileExists(atPath: file.path) || manager.createFile(atPath: file.path, contents: nil),
              let handle = try? FileHandle(forWritingTo: file)
        else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
    }

    /// 残っている記録を古い順に。作り直す前の古いほう（.1）も読む
    static func records() -> [Record] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return [file.appendingPathExtension("1"), file].flatMap { url -> [Record] in
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
            return text.split(separator: "\n").compactMap { try? decoder.decode(Record.self, from: Data($0.utf8)) }
        }
    }

    static func clear() {
        try? FileManager.default.removeItem(at: file)
        try? FileManager.default.removeItem(at: file.appendingPathExtension("1"))
    }

    /// スレッドに貼れるまとめ。種類ごと・アプリごとの数と、新しいほうから 40 件
    static func summary() -> String {
        let records = records()
        guard let first = records.first, let last = records.last else { return "sokkou のつまづきの記録はまだありません（\(Updater.build)）" }
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        let format = ISO8601DateFormatter()
        var lines = [
            "## sokkou のつまづき",
            "",
            "- 版: \(Updater.build)",
            "- macOS: \(os)",
            "- 期間: \(format.string(from: first.at)) 〜 \(format.string(from: last.at))（\(records.count) 件）",
            "",
            "### 種類ごと",
        ]
        let byKind = Dictionary(grouping: records, by: \.stumble.kind)
        for kind in Stumble.Kind.allCases {
            guard let count = byKind[kind]?.count else { continue }
            lines.append("- \(kind.title)（\(kind.rawValue)）: \(count)")
        }
        lines += ["", "### アプリごと"]
        let byApp = Dictionary(grouping: records) { $0.app ?? "?" }.sorted { $0.value.count > $1.value.count }
        for (app, items) in byApp.prefix(10) {
            lines.append("- \(app): \(items.count)")
        }
        lines += ["", "### 新しいほうから", "", "```"]
        for record in records.suffix(40).reversed() {
            let stumble = record.stumble
            var fields = [format.string(from: record.at), record.build, record.app ?? "?", stumble.kind.rawValue, stumble.mode.rawValue]
            if let count = stumble.count { fields.append("n=\(count)") }
            if let note = stumble.note { fields.append(note) }
            if let text = stumble.text { fields.append("「\(text)」") }
            fields.append("keys: " + stumble.keys.joined(separator: " "))
            lines.append(fields.joined(separator: " | "))
        }
        lines.append("```")
        return lines.joined(separator: "\n")
    }

    /// まとめをクリップボードに入れ、記録のファイルを Finder で見せる
    static func copySummary() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(summary(), forType: .string)
        if FileManager.default.fileExists(atPath: file.path) {
            NSWorkspace.shared.activateFileViewerSelecting([file])
        }
    }
}
