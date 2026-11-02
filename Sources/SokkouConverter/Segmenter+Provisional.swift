import Foundation

/// 変換が届く前に、打った文字をすぐ見せるための読み（tugime の Segmenter+Provisional）
extension Segmenter {
    /// 変換が届く前に見せる keys の区間。区切りと同じく、記号の打鍵は記号にし、句読点は直前が日本語なら日本語の記号にする。
    /// それ以外は前から、読める所は最も長く読んでかなの日本語区間にし、読めない打鍵は打ったまま英語区間に残す（kar → か r）。
    /// 綴りの表は末尾の単独の n を読まないので、打ったまま残る。afterJapanese は keys の前が日本語か。隣り合う日本語区間と英語区間はまとめる
    public static func provisionalSegments(of keys: some StringProtocol, afterJapanese startsAfterJapanese: Bool, table: RomajiTable) -> [Segment] {
        let input = Array(keys)
        var segments: [Segment] = []
        func add(_ kind: Segment.Kind, source: String, output: String) {
            let reading = kind == .japanese ? output : source
            if kind != .punctuation, let last = segments.last, last.kind == kind {
                segments[segments.count - 1].source += source
                segments[segments.count - 1].reading += reading
                segments[segments.count - 1].output += output
            } else {
                segments.append(Segment(kind: kind, source: source, reading: kind == .punctuation ? output : reading, output: output, score: 0, context: .start))
            }
        }
        var afterJapanese = startsAfterJapanese
        var position = 0
        while position < input.count {
            if let symbol = symbol(at: position, in: input) {
                add(.punctuation, source: symbol.key, output: symbol.mark)
                afterJapanese = true
                position += symbol.key.count
            } else if afterJapanese, let mark = punctuation[input[position]] {
                add(.punctuation, source: String(input[position]), output: mark)
                position += 1
            } else if let longest = table.readings(from: position, in: input).last {
                add(.japanese, source: String(input[position..<longest.end]), output: longest.kana)
                afterJapanese = true
                position = longest.end
            } else {
                add(.english, source: String(input[position]), output: String(input[position]))
                afterJapanese = false
                position += 1
            }
        }
        return segments
    }
}
