import Foundation

/// 変換エンジンの外にある辞書。自分で登録した語（ユーザー辞書）と、追加した SKK 辞書（SKK-JISYO.L など）。
/// 送りありの語は SKK と同じく、読みの語幹と送り仮名の頭のローマ字（書く なら「か」と k）で引き、語幹だけを返す
public protocol Lexicon: AnyObject {
    /// 自分で登録した語。新しいものから
    func userWords(reading: String, okuri: Character?) -> [String]
    /// 追加した SKK 辞書の語
    func systemWords(reading: String, okuri: Character?) -> [String]
    /// `X` で消した語か。消した語は変換エンジンの候補からも外す
    func isIgnored(_ word: String, reading: String, okuri: Character?) -> Bool
    func register(_ word: String, reading: String, okuri: Character?)
    /// ユーザー辞書から消し、以後どの辞書の候補にも出さない
    func remove(_ word: String, reading: String, okuri: Character?)
    /// prefix で始まる送りなしの読み。新しく使ったものから
    func completions(of prefix: String) -> [String]
}

// MARK: SKK 辞書

/// SKK 形式の辞書を 1 つ読んだもの。読みごとに候補の欄（/書く/描く;注釈/）を、ファイルの文字列を切り出したまま持ち、
/// 引いたときに候補へ分ける。SKK-JISYO.L（約 17 万語）でも読み込みが軽い
public struct SKKDictionary: Sendable {
    private var okuriAri: [String: Substring] = [:]
    private var okuriNasi: [String: Substring] = [:]

    public init(contents: String) {
        for line in contents.split(whereSeparator: \.isNewline) {
            guard let entry = Self.entry(line) else { continue }
            if Self.isOkuriAri(entry.key) {
                if okuriAri[entry.key] == nil { okuriAri[entry.key] = entry.field }
            } else if okuriNasi[entry.key] == nil {
                okuriNasi[entry.key] = entry.field
            }
        }
    }

    /// UTF-8 でも EUC-JP（skk-dev/dict の辞書）でも読む。読めなければ nil
    public init?(url: URL) {
        guard let data = try? Data(contentsOf: url),
              let contents = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .japaneseEUC)
        else { return nil }
        self.init(contents: contents)
    }

    /// directory の中の辞書をファイル名の順にすべて読む
    public static func load(directory: URL) -> [SKKDictionary] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { !$0.lastPathComponent.hasPrefix(".") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap(SKKDictionary.init(url:))
    }

    public var isEmpty: Bool { okuriAri.isEmpty && okuriNasi.isEmpty }

    public func words(reading: String, okuri: Character?) -> [String] {
        let field = okuri.map { okuriAri[reading + String($0)] } ?? okuriNasi[reading]
        return field.map(Self.candidates) ?? []
    }

    /// 1 行を見出しと候補の欄に分ける。; で始まる行（コメント）と、形の合わない行は nil
    static func entry(_ line: Substring) -> (key: String, field: Substring)? {
        guard !line.hasPrefix(";"), let space = line.firstIndex(of: " ") else { return nil }
        let field = line[line.index(after: space)...].drop { $0 == " " }
        guard field.hasPrefix("/"), space > line.startIndex else { return nil }
        return (String(line[..<space]), field)
    }

    /// 送りありの見出しは、かなの語幹のあとに送り仮名の頭のローマ字が 1 つ付く（かk）
    static func isOkuriAri(_ key: String) -> Bool {
        guard let first = key.unicodeScalars.first, let last = key.unicodeScalars.last, key.unicodeScalars.count > 1 else { return false }
        return !first.isASCII && first != "#" && last.isASCII && ("a"..."z").contains(last)
    }

    /// 候補の欄を候補に分ける。注釈（; のあと）と、送り仮名ごとの候補の塊（[く/書/]）と、Lisp の式は外す
    static func candidates(_ field: Substring) -> [String] {
        var words: [String] = []
        var inBlock = false
        for part in field.split(separator: "/") {
            if part.hasPrefix("[") {
                inBlock = true
                continue
            }
            if inBlock {
                if part == "]" { inBlock = false }
                continue
            }
            let word = part.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false).first.map { String($0) } ?? ""
            guard !word.isEmpty, !word.hasPrefix("("), !words.contains(word) else { continue }
            words.append(word)
        }
        return words
    }

    /// 候補を SKK の候補の欄の文字列にする。/ と ; を含む候補は書けないので外す
    static func field(_ words: [String]) -> String {
        "/" + words.filter { !$0.contains("/") && !$0.contains(";") }.map { $0 + "/" }.joined()
    }
}

// MARK: ユーザー辞書

/// 自分で登録した語を SKK 形式のファイル（UTF-8）に持つ。ほかの SKK とファイルをやりとりできる。
/// `X` で消した語は、SKK の形式では書けないので、隣の ignored.tsv に「見出し<TAB>語」で持つ
public final class UserDictionary {
    private let url: URL
    private let ignoredURL: URL
    private var okuriAri: [String: [String]] = [:]
    private var okuriNasi: [String: [String]] = [:]
    /// 見出しの並び。新しく登録したものから
    private var okuriAriOrder: [String] = []
    private var okuriNasiOrder: [String] = []
    private var ignored: Set<String> = []

    /// ファイルが無いか読めなければ、空で始める
    public init(url: URL) {
        self.url = url
        ignoredURL = url.deletingLastPathComponent().appendingPathComponent("ignored.tsv")
        if let contents = try? String(contentsOf: url, encoding: .utf8) {
            merge(contents)
        }
        if let contents = try? String(contentsOf: ignoredURL, encoding: .utf8) {
            ignored = Set(contents.split(whereSeparator: \.isNewline).map(String.init))
        }
    }

    public func words(reading: String, okuri: Character?) -> [String] {
        okuri == nil ? okuriNasi[reading] ?? [] : okuriAri[Self.key(reading, okuri)] ?? []
    }

    public func register(_ word: String, reading: String, okuri: Character?) {
        let key = Self.key(reading, okuri)
        ignored.remove(Self.ignoredLine(key, word))
        if okuri == nil {
            Self.put(word, key, &okuriNasi, &okuriNasiOrder)
        } else {
            Self.put(word, key, &okuriAri, &okuriAriOrder)
        }
        save()
        saveIgnored()
    }

    public func remove(_ word: String, reading: String, okuri: Character?) {
        let key = Self.key(reading, okuri)
        if okuri == nil {
            Self.drop(word, key, &okuriNasi, &okuriNasiOrder)
        } else {
            Self.drop(word, key, &okuriAri, &okuriAriOrder)
        }
        ignored.insert(Self.ignoredLine(key, word))
        save()
        saveIgnored()
    }

    public func isIgnored(_ word: String, reading: String, okuri: Character?) -> Bool {
        !ignored.isEmpty && ignored.contains(Self.ignoredLine(Self.key(reading, okuri), word))
    }

    /// prefix で始まり、prefix より長い送りなしの読み。新しく登録したものから
    public func completions(of prefix: String) -> [String] {
        guard !prefix.isEmpty else { return [] }
        return okuriNasiOrder.filter { $0.hasPrefix(prefix) && $0 != prefix }
    }

    /// ほかの SKK のユーザー辞書（~/.skk-jisyo など）を取り込む。今ある語は動かさず、無い語を後ろに足す。足した語の数を返す
    @discardableResult
    public func merge(contentsOf other: URL) -> Int? {
        guard let data = try? Data(contentsOf: other),
              let contents = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .japaneseEUC)
        else { return nil }
        let added = merge(contents)
        save()
        return added
    }

    @discardableResult
    private func merge(_ contents: String) -> Int {
        var added = 0
        for line in contents.split(whereSeparator: \.isNewline) {
            guard let entry = SKKDictionary.entry(line) else { continue }
            let words = SKKDictionary.candidates(entry.field)
            if SKKDictionary.isOkuriAri(entry.key) {
                added += Self.append(words, entry.key, &okuriAri, &okuriAriOrder)
            } else {
                added += Self.append(words, entry.key, &okuriNasi, &okuriNasiOrder)
            }
        }
        return added
    }

    private static func key(_ reading: String, _ okuri: Character?) -> String {
        okuri.map { reading + String($0) } ?? reading
    }

    private static func ignoredLine(_ key: String, _ word: String) -> String {
        key + "\t" + word
    }

    private static func put(_ word: String, _ key: String, _ entries: inout [String: [String]], _ order: inout [String]) {
        var words = entries[key] ?? []
        words.removeAll { $0 == word }
        words.insert(word, at: 0)
        entries[key] = words
        order.removeAll { $0 == key }
        order.insert(key, at: 0)
    }

    private static func drop(_ word: String, _ key: String, _ entries: inout [String: [String]], _ order: inout [String]) {
        guard var words = entries[key] else { return }
        words.removeAll { $0 == word }
        if words.isEmpty {
            entries[key] = nil
            order.removeAll { $0 == key }
        } else {
            entries[key] = words
        }
    }

    private static func append(_ words: [String], _ key: String, _ entries: inout [String: [String]], _ order: inout [String]) -> Int {
        guard !words.isEmpty else { return 0 }
        var current = entries[key] ?? []
        if current.isEmpty { order.append(key) }
        let new = words.filter { !current.contains($0) }
        current += new
        entries[key] = current
        return new.count
    }

    private func save() {
        var text = ";; -*- coding: utf-8 -*-\n;; sokkou のユーザー辞書（SKK 形式）\n;; okuri-ari entries.\n"
        for key in okuriAriOrder {
            text += key + " " + SKKDictionary.field(okuriAri[key] ?? []) + "\n"
        }
        text += ";; okuri-nasi entries.\n"
        for key in okuriNasiOrder {
            text += key + " " + SKKDictionary.field(okuriNasi[key] ?? []) + "\n"
        }
        write(text, to: url)
    }

    private func saveIgnored() {
        write(ignored.sorted().map { $0 + "\n" }.joined(), to: ignoredURL)
    }

    private func write(_ text: String, to url: URL) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url, options: .atomic)
        } catch {
            // 書けなくても入力は止めない。次に登録したときにまた書く
        }
    }
}

// MARK: まとめたもの

/// ユーザー辞書と追加の SKK 辞書をまとめて引く。読みに数字があれば、SKK と同じく # の見出し（#がつ /#1月/）でも引く
public final class SKKLexicon: Lexicon {
    public let user: UserDictionary
    /// 追加の SKK 辞書。大きいので、入力メソッドは別のスレッドで読んでから入れる
    public var systems: [SKKDictionary]

    public init(user: UserDictionary, systems: [SKKDictionary] = []) {
        self.user = user
        self.systems = systems
    }

    public func userWords(reading: String, okuri: Character?) -> [String] {
        Self.lookup(reading, okuri, user.words)
    }

    public func systemWords(reading: String, okuri: Character?) -> [String] {
        var words: [String] = []
        for system in systems {
            for word in Self.lookup(reading, okuri, system.words) where !words.contains(word) {
                words.append(word)
            }
        }
        return words
    }

    public func isIgnored(_ word: String, reading: String, okuri: Character?) -> Bool {
        user.isIgnored(word, reading: reading, okuri: okuri)
    }

    public func register(_ word: String, reading: String, okuri: Character?) {
        user.register(word, reading: reading, okuri: okuri)
    }

    public func remove(_ word: String, reading: String, okuri: Character?) {
        user.remove(word, reading: reading, okuri: okuri)
    }

    public func completions(of prefix: String) -> [String] {
        user.completions(of: prefix)
    }

    private static func lookup(_ reading: String, _ okuri: Character?, _ find: (String, Character?) -> [String]) -> [String] {
        var words = find(reading, okuri)
        if let template = Numeric.template(reading) {
            for candidate in find(template.key, okuri) {
                if let word = Numeric.expand(candidate, numbers: template.numbers), !words.contains(word) {
                    words.append(word)
                }
            }
        }
        return words
    }
}
