import Testing
import SokkouConverter
@testable import SokkouEngine

/// 辞書に語の無い読みに、かなを 1 つ替えた読みの語を出す（もしかして）
@Suite struct ReadingGuessesTests {
    static let guesses = ReadingGuesses(converter: ConversionMethod.azooKey.make())

    /// 切迫 は せっぱく と読む。きっぱく と読み違えても候補に出る
    @Test func guessesSeppakuForKippaku() async throws {
        let clock = ContinuousClock()
        var words: [String] = []
        let elapsed = clock.measure { words = Self.guesses.words(for: "きっぱく") }
        // 一時的な診断: 変換エンジンの出力に埋もれないよう、ほかのテストの後に結果を出す
        let converter = ConversionMethod.azooKey.make()
        let original = converter.convert(kana: "きっぱく", context: .start)
        let variant = converter.convert(kana: "せっぱく", context: .start)
        try await Task.sleep(for: .seconds(100))
        Issue.record("DIAG \(words) \(elapsed) \(String(describing: original)) \(String(describing: variant))")
        #expect(words.contains("切迫"), "\(words)")
        #expect(elapsed < .seconds(1), "\(elapsed)")
    }

    /// 語のある読みには何も足さない
    @Test(arguments: ["せっぱく", "きっぱり", "がっこう", "きって", "せっぱつまる", "にほんご"])
    func leavesWordsAlone(reading: String) {
        #expect(Self.guesses.words(for: reading).isEmpty, "\(reading)")
    }

    /// ▽ で ;kippaku と打って変換すると、第 1 候補のすぐ後ろに 切迫 が出る
    @Test func manualReadingOffersTheGuess() throws {
        let words = try Shared.engine.get().words(reading: "きっぱく", okurigana: "")
        let index = try #require(words.firstIndex(of: "切迫"), "\(words)")
        #expect(index <= 3, "\(words)")
        #expect(words.contains("きっぱく"), "\(words)")
    }
}
