import Testing
import SokkouConverter
@testable import SokkouEngine

/// 辞書に語の無い読みに、かなを 1 つ替えた読みの語を出す（もしかして）
@Suite(.serialized) struct ReadingGuessesTests {
    /// 変換器は同時に使えないので、テストごとに作る
    let guesses = ReadingGuesses(converter: ConversionMethod.azooKey.make())

    /// 切迫 は せっぱく と読む。きっぱく と読み違えても候補に出る
    @Test func guessesSeppakuForKippaku() {
        let words = guesses.words(for: "きっぱく")
        #expect(words.prefix(2).contains("切迫"), "\(words)")
    }

    /// 語のある読みには何も足さない
    @Test(arguments: ["せっぱく", "きっぱり", "がっこう", "きって", "せっぱつまる", "にほんご"])
    func leavesWordsAlone(reading: String) {
        #expect(guesses.words(for: reading).isEmpty, "\(reading)")
    }

    /// ▽ で ;kippaku と打って変換すると、第 1 候補のすぐ後ろに 切迫 が出る
    @Test func manualReadingOffersTheGuess() throws {
        let words = try Shared.engine.get().words(reading: "きっぱく", okurigana: "")
        let index = try #require(words.firstIndex(of: "切迫"), "\(words)")
        #expect(index <= 5, "\(words)")
        #expect(words.contains("きっぱく"), "\(words)")
    }
}
