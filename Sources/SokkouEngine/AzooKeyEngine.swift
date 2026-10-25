import Foundation
import SokkouCore
import SokkouConverter

/// SokkouConverter の日英判定と azooKey のかな漢字変換を sokkou につなぐ
public final class AzooKeyEngine: Engine {
    private let table: RomajiTable
    private let converter: any JapaneseConverting
    private let segmenter: Segmenter
    private let loanwords: Loanwords
    private let dateWords: DateWords

    /// method は既定で azooKey の辞書だけを使う。Zenzai（言語モデル）は軽さを測ってから入れる
    public init(method: ConversionMethod = .azooKey) throws {
        readsDisplayFromSegments = method.weight == nil
        table = try Self.romajiTable()
        converter = method.make()
        segmenter = Segmenter(table: table, english: try Self.englishModel(table: table), japanese: converter)
        loanwords = try Loanwords.bundled()
        dateWords = DateWords()
    }

    /// 英語として扱う語の頻度の下限。これより少なく、ローマ字で読める短い綴り（nai ine uso iku など）は、
    /// 語表ではローマ字書きの日本語が拾われたもので、英語の語として扱わない
    static let minShortReadableZipf = 3.0
    /// 「短い綴り」の長さ。2 文字以下は Segmenter が元から日本語を優先する
    static let maxShortReadableLength = 3

    /// 英語の語表から、ローマ字で読める短くて少ない語を除いたもの。
    /// 除かないと、naine の ine が英語の語として残り「なってなine」になる
    public static func englishModel(table: RomajiTable) throws -> EnglishModel {
        let spellings = try EnglishModel.resource("english-words", "txt")
        var zipf: [String: Double] = [:]
        let frequency = try EnglishModel.resource("english-frequency", "tsv")
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

    /// sokkou の綴りの表
    public static func romajiTable() throws -> RomajiTable {
        guard let url = Bundle.module.url(forResource: "romaji", withExtension: "tsv", subdirectory: "Resources") else {
            throw RomajiTable.ParseError.missingResource
        }
        return try RomajiTable(contents: String(contentsOf: url, encoding: .utf8))
    }

    public func live(_ keys: String, leading: Leading) -> [Span] {
        // 表示と確定で同じ打鍵列を続けて読むので、最後の 1 つを覚えておく
        if let last = lastLive, last.keys == keys, last.leading == leading { return last.spans }
        let segments = segmenter.segment(keys, leading: leading.forConverter)
        let text = readsDisplayFromSegments ? Self.liveText(of: segments) : segmenter.liveText(keys, leading: leading.forConverter)
        let spans = Self.spans(of: segments, in: text)
        lastLive = (keys, leading, spans)
        return spans
    }

    private var lastLive: (keys: String, leading: Leading, spans: [Span])?

    /// Zenzai を使わないときは、表示の変換は区切りの採点の変換と同じになる。そのときは Segmenter の liveText に
    /// 区切りをもう一度作らせず、区切りの結果から表示を作る。区切りは打鍵列の長さの 2 乗で重くなるので、長く打つほど効く
    var readsDisplayFromSegments: Bool

    /// Segmenter.liveConversionMinLength。これより短い日本語区間はかなのまま見せる
    static let liveConversionMinLength = 4

    /// Segmenter.liveText と同じ文字列を、区切りの結果から作る。Zenzai を使わないときだけ同じになる
    static func liveText(of segments: [Segment]) -> String {
        segments.map { segment in
            segment.kind == .japanese && segment.reading.count < liveConversionMinLength ? segment.reading : segment.output
        }.joined()
    }

    public func clauses(_ keys: String, leading: Leading) -> ClauseList {
        withExtraCandidates(segmenter.clauses(keys, leading: leading.forConverter))
    }

    public func resize(_ list: ClauseList, at index: Int, by delta: Int, leading: Leading) -> ClauseList {
        withExtraCandidates(segmenter.resize(Self.converted(list), at: index, by: delta, leading: leading.forConverter))
    }

    public func commit(_ list: ClauseList, through index: Int) -> (text: String, rest: ClauseList, keys: String)? {
        guard let result = segmenter.commit(Self.converted(list), through: index) else { return nil }
        return (result.text, withExtraCandidates(result.rest), result.keys)
    }

    public func whole(_ keys: String, form: SokkouCore.CharacterForm, leading: Leading) -> ClauseList {
        guard form == .katakana || form == .halfwidthKatakana else {
            return Self.list([segmenter.wholeClause(keys, to: form.forConverter, leading: leading.forConverter)])
        }
        return Self.list([katakanaWhole(keys, form: form, leading: leading)])
    }

    public func form(_ list: ClauseList, at index: Int, to form: SokkouCore.CharacterForm) -> String? {
        let clause = list.clauses[index]
        if form == .katakana || form == .halfwidthKatakana, clause.kind == .english,
           let katakana = loanwords.katakana(of: clause.reading).first {
            return convert(kana: katakana, to: form)
        }
        return segmenter.convertClause(Self.converted(list), at: index, to: form.forConverter)
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
        lastLive = nil
        segmenter.endComposition()
    }

    // MARK: 足す候補

    /// 英語の文節に test → テスト のようなカタカナ読みを、きょう・いま の文節に日付と時刻を候補として足す
    private func withExtraCandidates(_ clauses: [SokkouConverter.Clause]) -> ClauseList {
        var list = Self.list(clauses)
        for index in list.clauses.indices {
            switch list.clauses[index].kind {
            case .english:
                Self.offer(loanwords.katakana(of: list.clauses[index].reading), in: &list.clauses[index])
            case .japanese:
                Self.append(dateWords.candidates(for: list.clauses[index].reading), to: &list.clauses[index])
            default:
                break
            }
        }
        return list
    }

    /// 全体をカタカナ・半角カナにした 1 文節。Segmenter の `wholeClause` と同じく日本語区間は読み、
    /// 英語区間は綴りの表で読めた読みにするが、表にある英単語は先にその読みにする（test → テスト）。
    /// 表を使わない形も、違えば次の候補に置く
    private func katakanaWhole(_ keys: String, form: SokkouCore.CharacterForm, leading: Leading) -> SokkouConverter.Clause {
        let segments = segmenter.segment(keys, leading: leading.forConverter)
        let parts = segments.map { segment in
            segment.kind == .english ? englishReading(of: segment.source) ?? segment.source : segment.reading
        }
        let reading = parts.joined()
        let withLoanwords = zip(segments, parts).map { segment, part in
            segment.kind == .english ? loanwords.katakana(of: segment.source).first ?? part : part
        }.joined()
        var candidates = [convert(kana: withLoanwords, to: form)]
        let plain = convert(kana: reading, to: form)
        if plain != candidates[0] { candidates.append(plain) }
        let span = ClauseSpan(index: 0, source: keys, reading: reading, context: leading == .start ? .start : .afterCaret)
        return SokkouConverter.Clause(kind: .whole, reading: reading, candidates: candidates, selected: 0, span: span)
    }

    /// Segmenter の `englishReading` と同じく、英語区間を空白で区切った語ごとに綴りの表で読む。1 語も読めなければ nil
    private func englishReading(of source: String) -> String? {
        var readAny = false
        let words = source.split(separator: " ", omittingEmptySubsequences: false).map { word in
            guard let kana = table.reading(of: String(word)) else { return String(word) }
            readAny = true
            return kana
        }
        return readAny ? words.joined(separator: " ") : nil
    }

    /// 候補の一覧の後ろに足す。すでにある候補は足さない
    static func append(_ words: [String], to clause: inout SokkouCore.Clause) {
        for word in words where !clause.candidates.contains(word) {
            clause.candidates.append(word)
        }
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

    private static func list(_ clauses: [SokkouConverter.Clause]) -> ClauseList {
        ClauseList(clauses: clauses.map(clause), payload: clauses)
    }

    private static func clause(_ clause: SokkouConverter.Clause) -> SokkouCore.Clause {
        let kind: SokkouCore.Clause.Kind = switch clause.kind {
        case .japanese: .japanese
        case .english: .english
        case .punctuation: .punctuation
        case .whole: .whole
        }
        return SokkouCore.Clause(kind: kind, reading: clause.reading, candidates: clause.candidates, selected: clause.selected)
    }

    /// sokkou が選び直した候補を、SokkouConverter の文節に書き戻す
    private static func converted(_ list: ClauseList) -> [SokkouConverter.Clause] {
        guard var clauses = list.payload as? [SokkouConverter.Clause], clauses.count == list.clauses.count else {
            preconditionFailure("SokkouConverter の文節と sokkou の文節の数が合わない")
        }
        for index in clauses.indices {
            clauses[index].candidates = list.clauses[index].candidates
            clauses[index].selected = list.clauses[index].selected
        }
        return clauses
    }
}

extension Leading {
    var forConverter: Segmenter.Leading {
        switch self {
        case .start: .start
        case .afterJapanese: .afterJapanese
        case .afterEnglish: .afterEnglish
        }
    }
}

extension SokkouCore.CharacterForm {
    var forConverter: SokkouConverter.CharacterForm {
        switch self {
        case .hiragana: .hiragana
        case .katakana: .katakana
        case .halfwidthKatakana: .halfwidthKatakana
        case .fullwidthRoman: .fullwidthRoman
        case .roman: .roman
        }
    }
}
