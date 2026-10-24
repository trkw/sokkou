import Foundation
import SokkouCore
import TugimeCore

/// tugime の日英判定と、tugime が使う azooKey のかな漢字変換を sokkou につなぐ
public final class TugimeEngine: Engine {
    private let table: RomajiTable
    private let converter: any JapaneseConverting
    private let segmenter: Segmenter
    private let loanwords: Loanwords

    /// method は既定で azooKey の辞書だけを使う。Zenzai（言語モデル）は軽さを測ってから入れる
    public init(method: ConversionMethod = .azooKey) throws {
        table = try Self.romajiTable()
        converter = method.make()
        segmenter = Segmenter(table: table, english: try Self.englishModel(table: table), japanese: converter)
        loanwords = try Loanwords.bundled()
    }

    /// 英語として扱う語の頻度の下限。これより少なく、ローマ字で読める短い綴り（nai ine uso iku など）は、
    /// tugime の語表ではローマ字書きの日本語が拾われたもので、英語の語として扱わない
    static let minShortReadableZipf = 3.0
    /// 「短い綴り」の長さ。2 文字以下は tugime が元から日本語を優先する
    static let maxShortReadableLength = 3

    /// tugime の英語の語表から、ローマ字で読める短くて少ない語を除いたもの。
    /// 除かないと、naine の ine が英語の語として残り「なってなine」になる
    public static func englishModel(table: RomajiTable) throws -> EnglishModel {
        let resources = try tugimeResources()
        let spellings = try String(contentsOf: resources.appendingPathComponent("english-words.txt"), encoding: .utf8)
        var zipf: [String: Double] = [:]
        let frequency = try String(contentsOf: resources.appendingPathComponent("english-frequency.tsv"), encoding: .utf8)
        for (index, line) in frequency.split(separator: "\n").enumerated() {
            let fields = line.split(separator: "\t")
            guard fields.count == 2, let value = Double(fields[1]) else {
                throw EnglishModel.LoadError.malformedLine("english-frequency.tsv", index + 1, String(line))
            }
            let word = String(fields[0])
            if value < minShortReadableZipf, word.count <= maxShortReadableLength, table.reading(of: word) != nil { continue }
            zipf[word] = value
        }
        return EnglishModel(spellings: spellings.split(separator: "\n"), zipf: zipf)
    }

    /// tugime の語表がある Resources。tugime のリソースのバンドルは、sokkou のリソースのバンドルと同じところに置かれる
    /// （.app では Contents/Resources、swift test では組み立てたディレクトリ）
    private static func tugimeResources() throws -> URL {
        let directory = Bundle.module.bundleURL.deletingLastPathComponent()
        let bundles = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for url in bundles where url.pathExtension == "bundle" {
            if let file = Bundle(url: url)?.url(forResource: "english-frequency", withExtension: "tsv", subdirectory: "Resources") {
                return file.deletingLastPathComponent()
            }
        }
        throw EnglishModel.LoadError.missingResource("english-frequency.tsv")
    }

    /// sokkou の綴りの表。tugime の既定の表は使わない（zi や shi を読まないので、その綴りから先が英語になる）
    public static func romajiTable() throws -> RomajiTable {
        guard let url = Bundle.module.url(forResource: "romaji", withExtension: "tsv", subdirectory: "Resources") else {
            throw RomajiTable.ParseError.missingResource
        }
        return try RomajiTable(contents: String(contentsOf: url, encoding: .utf8))
    }

    public func live(_ keys: String, leading: Leading) -> [Span] {
        let segments = segmenter.segment(keys, leading: leading.tugime)
        let text = segmenter.liveText(keys, leading: leading.tugime)
        return Self.spans(of: segments, in: text)
    }

    public func clauses(_ keys: String, leading: Leading) -> ClauseList {
        withLoanwords(segmenter.clauses(keys, leading: leading.tugime))
    }

    public func resize(_ list: ClauseList, at index: Int, by delta: Int, leading: Leading) -> ClauseList {
        withLoanwords(segmenter.resize(Self.tugime(list), at: index, by: delta, leading: leading.tugime))
    }

    public func commit(_ list: ClauseList, through index: Int) -> (text: String, rest: ClauseList, keys: String)? {
        guard let result = segmenter.commit(Self.tugime(list), through: index) else { return nil }
        return (result.text, withLoanwords(result.rest), result.keys)
    }

    public func whole(_ keys: String, form: SokkouCore.CharacterForm, leading: Leading) -> ClauseList {
        Self.list([segmenter.wholeClause(keys, to: form.tugime, leading: leading.tugime)])
    }

    public func form(_ list: ClauseList, at index: Int, to form: SokkouCore.CharacterForm) -> String? {
        segmenter.convertClause(Self.tugime(list), at: index, to: form.tugime)
    }

    public func kana(_ romaji: String) -> (kana: String, rest: String) {
        let characters = Array(romaji)
        var kana = ""
        var position = 0
        // 綴りの表で、前から最も長く読めるところまで読む
        while position < characters.count, let longest = table.readings(from: position, in: characters).last {
            kana += longest.kana
            position = longest.end
        }
        return (kana, String(characters[position...]))
    }

    public func convert(kana: String, to form: SokkouCore.CharacterForm) -> String {
        switch form {
        case .hiragana, .roman:
            kana
        case .katakana:
            kana.applyingTransform(.hiraganaToKatakana, reverse: false) ?? kana
        case .halfwidthKatakana:
            convert(kana: kana, to: .katakana).applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? kana
        case .fullwidthRoman:
            kana.applyingTransform(.fullwidthToHalfwidth, reverse: true) ?? kana
        }
    }

    public func words(reading: String, okurigana: String) -> [String] {
        let whole = reading + okurigana
        var words = converter.alternatives(kana: whole, context: .start)
        if !okurigana.isEmpty {
            words = words.filter { $0.hasSuffix(okurigana) }
        }
        // 辞書に無い語も、ひらがなとカタカナでは確定できるようにする
        for fallback in [whole, convert(kana: whole, to: .katakana)] where !words.contains(fallback) {
            words.append(fallback)
        }
        return words
    }

    public func endComposition() {
        segmenter.endComposition()
    }

    // MARK: 英単語のカタカナ読み

    /// 英語の文節に、test → テスト のようなカタカナ読みを候補として足す
    private func withLoanwords(_ clauses: [TugimeCore.Clause]) -> ClauseList {
        var list = Self.list(clauses)
        for index in list.clauses.indices where list.clauses[index].kind == .english {
            Self.offer(loanwords.katakana(of: list.clauses[index].reading), in: &list.clauses[index])
        }
        return list
    }

    /// 英語の綴りのすぐ次に、よく使う読みから置く。すでにある候補は足さず、選んでいる候補は変えない
    static func offer(_ words: [String], in clause: inout SokkouCore.Clause) {
        var position = min(1, clause.candidates.count)
        for word in words where !clause.candidates.contains(word) {
            clause.candidates.insert(word, at: position)
            if position <= clause.selected { clause.selected += 1 }
            position += 1
        }
    }

    // MARK: 型の付け替え

    /// 打っている途中の表示を区間ごとに分ける。英語と句読点の区間は打ったまま表示されるので、
    /// その文字列が現れるところまでを、前に続く日本語区間の表示とする。分けられなければ全体を 1 つの日本語区間にする
    static func spans(of segments: [Segment], in text: String) -> [Span] {
        var spans: [Span] = []
        var rest = Substring(text)
        var japaneseReading = ""
        func closeJapanese(before end: Substring.Index) {
            guard !japaneseReading.isEmpty else { return }
            spans.append(Span(kind: .japanese, text: String(rest[..<end]), reading: japaneseReading))
            rest = rest[end...]
            japaneseReading = ""
        }
        for segment in segments {
            switch segment.kind {
            case .japanese:
                japaneseReading += segment.reading
            case .english, .punctuation:
                if japaneseReading.isEmpty {
                    guard rest.hasPrefix(segment.output) else { return fallback(segments, text) }
                } else {
                    guard let range = rest.range(of: segment.output) else { return fallback(segments, text) }
                    closeJapanese(before: range.lowerBound)
                }
                spans.append(Span(kind: segment.kind == .english ? .english : .punctuation, text: segment.output, reading: segment.source))
                rest = rest.dropFirst(segment.output.count)
            }
        }
        closeJapanese(before: rest.endIndex)
        return spans
    }

    private static func fallback(_ segments: [Segment], _ text: String) -> [Span] {
        [Span(kind: .japanese, text: text, reading: segments.map(\.reading).joined())]
    }

    private static func list(_ clauses: [TugimeCore.Clause]) -> ClauseList {
        ClauseList(clauses: clauses.map(clause), payload: clauses)
    }

    private static func clause(_ clause: TugimeCore.Clause) -> SokkouCore.Clause {
        let kind: SokkouCore.Clause.Kind = switch clause.kind {
        case .japanese: .japanese
        case .english: .english
        case .punctuation: .punctuation
        case .whole: .whole
        }
        return SokkouCore.Clause(kind: kind, reading: clause.reading, candidates: clause.candidates, selected: clause.selected)
    }

    /// sokkou が選び直した候補を、tugime の文節に書き戻す
    private static func tugime(_ list: ClauseList) -> [TugimeCore.Clause] {
        guard var clauses = list.payload as? [TugimeCore.Clause], clauses.count == list.clauses.count else {
            preconditionFailure("tugime の文節と sokkou の文節の数が合わない")
        }
        for index in clauses.indices {
            clauses[index].candidates = list.clauses[index].candidates
            clauses[index].selected = list.clauses[index].selected
        }
        return clauses
    }
}

extension Leading {
    var tugime: Segmenter.Leading {
        switch self {
        case .start: .start
        case .afterJapanese: .afterJapanese
        case .afterEnglish: .afterEnglish
        }
    }
}

extension SokkouCore.CharacterForm {
    var tugime: TugimeCore.CharacterForm {
        switch self {
        case .hiragana: .hiragana
        case .katakana: .katakana
        case .halfwidthKatakana: .halfwidthKatakana
        case .fullwidthRoman: .fullwidthRoman
        case .roman: .roman
        }
    }
}
