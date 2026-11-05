import Testing
import SokkouCore
@testable import SokkouEngine
@testable import SokkouConverter

/// 変換が届く前に見せる、打っている途中の区間（tugime の ProvisionalReadingTests に合わせたもの）
@Suite struct ProvisionalTests {
    private func text(_ spans: [Span]) -> String {
        spans.map(\.text).joined()
    }

    @Test(arguments: [
        ("kar", true, "かr"),
        ("tyokk", true, "ちょkk"),
        ("seikakuni", true, "せいかくに"),
        // 句読点は直前が日本語なら日本語の記号、英字なら打ったまま
        ("nara,", true, "なら、"),
        (",", true, "、"),
        (",", false, ","),
        // 記号の打鍵は前によらず記号
        ("[", false, "「"),
        ("shsi", false, "shし"),
        // 綴りの表は末尾の単独の n を読まないので、打ったまま
        ("kon", true, "こn"),
        ("konn", true, "こん"),
    ])
    func readsKeysBeforeConversionArrives(keys: String, afterJapanese: Bool, expected: String) throws {
        let table = try Shared.table.get()
        let segments = Segmenter.provisionalSegments(of: keys, afterJapanese: afterJapanese, table: table)
        #expect(segments.map(\.output).joined() == expected)
        #expect(segments.map(\.source).joined() == keys)
    }

    @Test(arguments: [
        // 打ちかけの子音は表示から外して読み直す
        ("g", "g", "", 1),
        ("github", "github", "githu", 1),
        ("siteh", "して|h", "して", 1),
        ("python", "python", "pytho", 1),
        // 母音や nn で終われば外さない
        ("setteiwo", "設定を", "設定を", 0),
        ("honn", "本", "本", 0),
        ("kannk", "感|k", "感", 1),
    ])
    func splitsPending(keys: String, shown: String, kept: String, pending: Int) throws {
        let split = try #require(AzooKeyEngine.splitPending(Self.spans(shown), typed: keys))
        #expect(text(split.kept) == kept)
        #expect(split.pending == pending)
    }

    /// 打ちかけの子音が英語区間の末尾に打ったまま出ていなければ、分けられない
    @Test func cannotSplitWhenPendingIsNotShownAsTyped() {
        #expect(AzooKeyEngine.splitPending([Span(kind: .japanese, text: "感", reading: "かん")], typed: "kank") == nil)
    }

    @Test(arguments: [
        // 同じ打鍵列の変換が届いていればそれ
        ("githubni", [("githubni", "github|に")], Leading.start, "githubに"),
        // 先頭に当たる最新の変換から打ちかけを外し、後の打鍵とまとめて読む
        ("githubni", [("github", "github")], .start, "githubに"),
        ("gi", [("g", "g")], .start, "ぎ"),
        ("teno", [("te", "て"), ("ten", "て|n")], .start, "ての"),
        // 打ちかけの子音で英語と見た語の切れ端も、後の打鍵とかなだけで読めるならまとめて読む。英字とかなを混ぜない
        ("katta", [("ka", "か"), ("kat", "kat")], .start, "かった"),
        ("mitemo", [("mit", "mit")], .start, "みても"),
        ("hosii", [("hos", "hos")], .start, "ほしい"),
        ("kanoyouni", [("kan", "kan")], .start, "かのように"),
        // かなだけで読めなければ英語のまま
        ("world", [("wor", "wor")], .start, "world"),
        ("hello world", [("hello wor", "hello wor")], .start, "hello world"),
        // Backspace で前の打鍵列に戻ったときも、届いている変換を使う
        ("make", [("make", "make"), ("makes", "makes")], .start, "make"),
        // 届いていなければ打鍵列全体を読む。先頭の句読点は入力欄の直前で決める
        (",", [], .afterJapanese, "、"),
        (",", [], .afterEnglish, ","),
    ])
    func showsTheLatestConversionWithTheKeysAfterIt(keys: String, converted: [(String, String)], leading: Leading, expected: String) throws {
        let table = try Shared.table.get()
        let shown = AzooKeyEngine.provisional(keys, leading: leading, converted: converted.map { ($0.0, Self.spans($0.1)) }, table: table)
        #expect(text(shown) == expected)
    }

    /// | で区切った区間。ASCII だけの区間は英語、それ以外は日本語（読みは表示と同じものとして扱う）
    private static func spans(_ shown: String) -> [Span] {
        shown.split(separator: "|").map { part in
            let text = String(part)
            return Span(kind: text.allSatisfy(\.isASCII) ? .english : .japanese, text: text, reading: text)
        }
    }
}
