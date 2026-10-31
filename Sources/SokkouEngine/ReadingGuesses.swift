import Foundation
import SokkouConverter

/// 辞書に語の無い読みに、かなを 1 つ替えた読みの語を「もしかして」の候補として出す（きっぱく → 切迫）。
/// 漢字の読み違い（切 を き と読む）や打ち間違いで、語にならない読みを打ったときに、近い読みの語を選べるようにする
struct ReadingGuesses {
    let converter: any JapaneseConverting

    /// 替える先と替える元にするかな。拗音・小書きのかな・長音は、前後のかなと組で読むので替えない
    static let kana: [Character] = Array(
        "あいうえおかきくけこさしすせそたちつてとなにぬねのはひふへほまみむめもやゆよらりるれろわをん"
            + "がぎぐげござじずぜぞだぢづでどばびぶべぼぱぴぷぺぽ"
    )

    /// これより短い読みは、1 かな替えると別の語がいくらでも作れるので推さない
    static let minLength = 3
    /// 1 かなあたりの評価値がこれより低い読みを、辞書に語の無い読みとみなす。
    /// 語のある読みは 1 かなあたり -5 前後（きっぱり -3.7、切羽詰まる -3.1）、語の無い読みは -7 より低い（きっパク -8.6）
    static let maxValuePerKana = -7.0
    /// 替えた読みの評価値が、元の読みよりこれだけ高い語だけを出す
    static let minGain = 10.0
    /// 出す語の数。読み違いの語（きっぱく → 切迫）は、打ち間違いの語（あっぱく → 圧迫、いっぱく → 1泊）より低いことがあるので多めに出す
    static let maxCount = 5

    /// reading に語が無ければ、近い読みの語。語があるか、近い読みにも語が無ければ空。
    /// 元の読みの候補にある漢字を含む語（きっぱく の候補「切っ泊」の 切 を含む 切迫）を先に、それぞれ評価値の高い順に並べる。
    /// 読み違いはその漢字を別の読みで読んだものなので、評価値だけで並べると、打ち間違いで近い語（圧迫・逼迫・潔白）より後ろになる
    func words(for reading: String) -> [String] {
        let chars = Array(reading)
        guard chars.count >= Self.minLength,
              let original = converter.convert(kana: reading, context: .start),
              original.value < Self.maxValuePerKana * Double(chars.count)
        else { return [] }
        var best: [String: Double] = [:]
        for index in chars.indices where Self.kana.contains(chars[index]) {
            for replacement in Self.kana where replacement != chars[index] {
                var variant = chars
                variant[index] = replacement
                guard let reading = converter.convert(kana: String(variant), context: .start),
                      reading.value >= original.value + Self.minGain,
                      reading.text != original.text
                else { continue }
                best[reading.text] = max(best[reading.text] ?? -.infinity, reading.value)
            }
        }
        let kanji = Set(converter.alternatives(kana: reading, context: .start).joined().filter(Self.isKanji))
        func sharesKanji(_ word: String) -> Bool { word.contains { kanji.contains($0) } }
        return best
            .sorted { a, b in
                let (sharedA, sharedB) = (sharesKanji(a.key), sharesKanji(b.key))
                return sharedA == sharedB ? a.value > b.value : sharedA
            }
            .prefix(Self.maxCount)
            .map(\.key)
    }

    private static func isKanji(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { $0.properties.isIdeographic }
    }
}
