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

    /// 打ったままの英語の区間のカタカナ読み。1 語のときだけ引き、前後の空白は付け直す
    public func katakana(of source: String) -> [String] {
        let head = String(source.prefix { $0 == " " })
        let tail = String(source.reversed().prefix { $0 == " " })
        let word = source.trimmingCharacters(in: .init(charactersIn: " "))
        guard !word.isEmpty, !word.contains(" ") else { return [] }
        return (readings[word.lowercased()] ?? []).map { head + $0 + tail }
    }
}
