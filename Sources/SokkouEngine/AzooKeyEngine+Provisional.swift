import Foundation
import SokkouCore
import SokkouConverter

/// 変換が届く前に見せる、打っている途中の区間（tugime の Segmenter.liveDisplay(of:converted:)）
extension AzooKeyEngine {
    /// 打鍵列 keys の打っている途中の区間を、届いた変換 converted（届いた順）から作る。
    /// keys と同じ打鍵列の変換が届いていればそれを出す。届いていなければ、keys の先頭に当たる最新の変換から末尾の打ちかけの部分を外し、
    /// 外した打鍵とその後に打った打鍵の読み（Segmenter.provisionalSegments）をつなぐ。打ちかけの部分を外せない変換は飛ばして、
    /// その前の変換を使う。どれも使えなければ keys 全体を読む。綴りの表しか使わないので、変換と別のスレッドから呼んでよい
    public static func provisional(_ keys: String, leading: Leading, converted: [(keys: String, spans: [Span])], table: RomajiTable) -> [Span] {
        if let same = converted.last(where: { $0.keys == keys }) { return same.spans }
        for base in converted.reversed() where keys.hasPrefix(base.keys) {
            guard var split = splitPending(base.spans, typed: base.keys) else { continue }
            split = rereadingWord(split, after: keys.dropFirst(base.keys.count - split.pending), table: table)
            let rest = keys.dropFirst(base.keys.count - split.pending)
            return joined(split.kept, read(rest, afterJapanese: afterJapanese(split.kept, leading: leading), table: table))
        }
        return read(keys[...], afterJapanese: afterJapanese([], leading: leading), table: table)
    }

    /// 区間 spans の後ろの句読点を日本語の記号にするか。区切りと同じく、未確定の文字列の中では直前が日本語か、先頭では入力欄の直前（leading）で決める
    static func afterJapanese(_ spans: [Span], leading: Leading) -> Bool {
        guard let last = spans.last?.text.last else { return leading == .start || leading == .afterJapanese }
        return !last.isASCII
    }

    /// 打鍵列 keys の変換の区間 spans を、後ろに読みをつないでも崩れない部分と、末尾の打ちかけの打鍵の数に分ける。
    /// 打ちかけは、最後の母音より後ろの子音（英語区間に打ったまま出ている。読み終えた nn を除く）。綴りの表は末尾の単独の n を読まないので、
    /// その n も打ちかけに入る。打ちかけの打鍵は、後から打った打鍵とまとめて読み直す（g の後の i は「ぎ」、n の後の o は「の」）。
    /// 打ちかけの部分が最後の英語区間の末尾にそのまま出ていなければ、分けられないので nil
    static func splitPending(_ spans: [Span], typed keys: String) -> (kept: [Span], pending: Int)? {
        let letters = keys.reversed().prefix { $0.isASCII && $0.isLetter }
        var consonants = String(letters.prefix { !"aiueo".contains($0) }.reversed())
        // 母音の直後の nn は読み終えた「ん」
        if consonants.hasPrefix("nn") { consonants.removeFirst(2) }
        guard !consonants.isEmpty else { return (spans, 0) }
        guard var last = spans.last, last.kind == .english, last.text.hasSuffix(consonants), last.reading.hasSuffix(consonants) else { return nil }
        var kept = Array(spans.dropLast())
        last.text.removeLast(consonants.count)
        last.reading.removeLast(consonants.count)
        if !last.text.isEmpty { kept.append(last) }
        return (kept, consonants.count)
    }

    /// 打ちかけを外した後に英語区間の末尾に残る語の切れ端（kat の ka）も、後の打鍵 rest とつないでかなだけで読めるなら、打ちかけに入れて読み直す（katta は かった）。
    /// 打ちかけの子音があったから英語と見た語なので、残したままだと ka った のように英字とかなが混ざる。かなだけで読めないとき（wor の後の ld）や、
    /// 打ちかけが無いときは今までどおり英語のまま残す
    static func rereadingWord(_ split: (kept: [Span], pending: Int), after rest: Substring, table: RomajiTable) -> (kept: [Span], pending: Int) {
        guard split.pending > 0, !rest.isEmpty, var last = split.kept.last, last.kind == .english else { return split }
        let word = String(last.text.reversed().prefix { $0.isASCII && $0.isLetter }.reversed())
        guard !word.isEmpty, last.reading.hasSuffix(word) else { return split }
        let joined = word + rest
        guard Segmenter.provisionalSegments(of: joined, afterJapanese: false, table: table).allSatisfy({ $0.kind == .japanese }) else { return split }
        var kept = Array(split.kept.dropLast())
        last.text.removeLast(word.count)
        last.reading.removeLast(word.count)
        if !last.text.isEmpty { kept.append(last) }
        return (kept, split.pending + word.count)
    }

    /// 変換が届く前の打鍵の読みを、打っている途中の区間にする
    private static func read(_ keys: Substring, afterJapanese: Bool, table: RomajiTable) -> [Span] {
        Segmenter.provisionalSegments(of: keys, afterJapanese: afterJapanese, table: table).map { segment in
            switch segment.kind {
            case .japanese: Span(kind: .japanese, text: segment.output, reading: segment.reading)
            case .english: Span(kind: .english, text: segment.output, reading: segment.source)
            case .punctuation: Span(kind: .punctuation, text: segment.output, reading: segment.source)
            }
        }
    }

    /// 区間をつなぐ。境目の英語区間どうしは 1 つにまとめる
    private static func joined(_ kept: [Span], _ rest: [Span]) -> [Span] {
        guard var last = kept.last, let first = rest.first, last.kind == .english, first.kind == .english else { return kept + rest }
        last.text += first.text
        last.reading += first.reading
        return kept.dropLast() + [last] + rest.dropFirst()
    }
}
