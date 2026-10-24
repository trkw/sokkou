import Foundation
import SokkouCore
import TugimeCore

/// tugime の日英判定と、tugime が使う azooKey のかな漢字変換を sokkou につなぐ
public final class TugimeEngine: Engine {
    private let table: RomajiTable
    private let converter: any JapaneseConverting
    private let segmenter: Segmenter

    /// method は既定で azooKey の辞書だけを使う。Zenzai（言語モデル）は軽さを測ってから入れる
    public init(method: ConversionMethod = .azooKey) throws {
        table = try Self.romajiTable()
        converter = method.make()
        segmenter = Segmenter(table: table, english: try .bundled(), japanese: converter)
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
        Self.list(segmenter.clauses(keys, leading: leading.tugime))
    }

    public func resize(_ list: ClauseList, at index: Int, by delta: Int, leading: Leading) -> ClauseList {
        Self.list(segmenter.resize(Self.tugime(list), at: index, by: delta, leading: leading.tugime))
    }

    public func commit(_ list: ClauseList, through index: Int) -> (text: String, rest: ClauseList, keys: String)? {
        guard let result = segmenter.commit(Self.tugime(list), through: index) else { return nil }
        return (result.text, Self.list(result.rest), result.keys)
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
