@testable import SokkouCore

/// 小さな綴りの表と辞書だけで動く変換エンジン。空白で区切った語ごとに、英語の語表にあれば英語、なければ日本語として読む
final class FakeEngine: Engine {
    static let romaji: [String: String] = [
        "a": "あ", "i": "い", "u": "う", "e": "え", "o": "お",
        "ka": "か", "ki": "き", "ku": "く", "ke": "け", "ko": "こ",
        "sa": "さ", "si": "し", "su": "す", "se": "せ", "so": "そ",
        "ta": "た", "ti": "ち", "tu": "つ", "te": "て", "to": "と",
        "na": "な", "ni": "に", "nu": "ぬ", "ne": "ね", "no": "の",
        "ha": "は", "hi": "ひ", "hu": "ふ", "he": "へ", "ho": "ほ",
        "ma": "ま", "mi": "み", "mu": "む", "me": "め", "mo": "も",
        "nn": "ん",
    ]
    static let dictionary: [String: [String]] = [
        "かく": ["書く", "描く", "核", "角", "格", "閣", "欠く", "画", "拡"],
        "の": ["の"],
        "かみ": ["紙", "神", "髪"],
    ]
    static let english: Set<String> = ["dark", "mode", "github"]

    var resizeCalls = 0
    var endCompositionCalls = 0

    func live(_ keys: String, leading: Leading) -> [Span] {
        tokens(keys).map { token in
            if token == " " || Self.english.contains(token) {
                return Span(kind: .english, text: token, reading: token)
            }
            let reading = kana(token).kana + kana(token).rest
            return Span(kind: .japanese, text: Self.dictionary[reading]?.first ?? reading, reading: reading)
        }
    }

    func clauses(_ keys: String, leading: Leading) -> ClauseList {
        let clauses = live(keys, leading: leading).map { span in
            span.kind == .english
                ? Clause(kind: .english, reading: span.reading, candidates: [span.text])
                : Clause(kind: .japanese, reading: span.reading, candidates: (Self.dictionary[span.reading] ?? []) + [span.reading])
        }
        return ClauseList(clauses: clauses, payload: tokens(keys))
    }

    func resize(_ list: ClauseList, at index: Int, by delta: Int, leading: Leading) -> ClauseList {
        resizeCalls += 1
        return list
    }

    func commit(_ list: ClauseList, through index: Int) -> (text: String, rest: ClauseList, keys: String)? {
        let tokens = list.payload as? [String] ?? []
        let text = list.clauses[...index].map(\.output).joined()
        let restTokens = Array(tokens.dropFirst(index + 1))
        return (text, ClauseList(clauses: Array(list.clauses.dropFirst(index + 1)), payload: restTokens), restTokens.joined())
    }

    func whole(_ keys: String, form: CharacterForm, leading: Leading) -> ClauseList {
        let reading = live(keys, leading: leading).map(\.reading).joined()
        let text: String
        switch form {
        case .roman: text = keys
        case .fullwidthRoman: text = keys.map(Composer.fullwidth).joined()
        default: text = convert(kana: reading, to: form)
        }
        return ClauseList(clauses: [Clause(kind: .whole, reading: reading, candidates: [text])])
    }

    func form(_ list: ClauseList, at index: Int, to form: CharacterForm) -> String? {
        convert(kana: list.clauses[index].reading, to: form)
    }

    func kana(_ romaji: String) -> (kana: String, rest: String) {
        var kana = ""
        var rest = Substring(romaji)
        while !rest.isEmpty {
            guard let length = (1...2).reversed().first(where: { rest.count >= $0 && Self.romaji[String(rest.prefix($0))] != nil }) else { break }
            kana += Self.romaji[String(rest.prefix(length))]!
            rest = rest.dropFirst(length)
        }
        return (kana, String(rest))
    }

    func convert(kana: String, to form: CharacterForm) -> String {
        switch form {
        case .hiragana, .roman, .fullwidthRoman:
            return kana
        case .katakana:
            return String(String.UnicodeScalarView(kana.unicodeScalars.map { scalar in
                (0x3041...0x3096).contains(scalar.value) ? Unicode.Scalar(scalar.value + 0x60)! : scalar
            }))
        case .halfwidthKatakana:
            return "半" + convert(kana: kana, to: .katakana)
        }
    }

    func words(reading: String, okurigana: String) -> [String] {
        let all = Self.dictionary[reading + okurigana] ?? []
        return all.filter { okurigana.isEmpty || $0.hasSuffix(okurigana) } + [reading + okurigana]
    }

    func endComposition() {
        endCompositionCalls += 1
    }

    /// 空白を 1 つの語として残して区切る
    private func tokens(_ keys: String) -> [String] {
        var tokens: [String] = []
        var word = ""
        for character in keys {
            if character == " " {
                if !word.isEmpty { tokens.append(word) }
                tokens.append(" ")
                word = ""
            } else {
                word.append(character)
            }
        }
        if !word.isEmpty { tokens.append(word) }
        return tokens
    }
}
