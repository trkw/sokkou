import Foundation

/// 英単語のカタカナ読みの表。英語と判定した test にも テスト を候補として出すのに使う。
/// 表は scripts/make-loanwords.py が azooKey の辞書から作る（読み テスト → 語 test の語を逆に引いたもの）
public struct Loanwords: Sendable {
    private let readings: [String: [String]]

    public init(contents: String) {
        var readings: [String: [String]] = [:]
        for line in contents.split(separator: "\n") where !line.hasPrefix("#") {
            let fields = line.split(separator: "\t").map(String.init)
            guard fields.count >= 2 else { continue }
            readings[fields[0]] = Array(fields.dropFirst())
        }
        self.readings = readings
    }

    public static func bundled() throws -> Loanwords {
        guard let url = Bundle.module.url(forResource: "loanwords", withExtension: "tsv", subdirectory: "Resources") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return Loanwords(contents: try String(contentsOf: url, encoding: .utf8))
    }

    /// 打ったままの英語の区間のカタカナ読み。前後の空白は付け直す。
    /// 2 語以上なら、どの語も表にあるときだけ、それぞれのよく使う読みを空白を詰めてつなぐ（online game → オンラインゲーム）
    public func katakana(of source: String) -> [String] {
        let head = String(source.prefix { $0 == " " })
        let tail = String(source.reversed().prefix { $0 == " " })
        let words = source.split(separator: " ")
        guard let first = words.first else { return [] }
        guard words.count > 1 else {
            return (readings[first.lowercased()] ?? []).map { head + $0 + tail }
        }
        var joined = ""
        for word in words {
            guard let reading = readings[word.lowercased()]?.first else { return [] }
            joined += reading
        }
        return [head + joined + tail]
    }
}
