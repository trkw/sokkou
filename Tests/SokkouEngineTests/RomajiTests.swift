import Testing
import SokkouCore
import SokkouEngine
import SokkouConverter

/// 本物の綴りの表と変換エンジン。作るたびに辞書と語表を読むので、全テストで共有する
enum Shared {
    static let table = Result { try AzooKeyEngine.romajiTable() }
    static let engine = Result { try AzooKeyEngine() }
}

@Suite struct RomajiTests {
    @Test(arguments: [
        // 元からの綴り
        ("sitituhuji", "しちつふじ"),
        ("syatyaja", "しゃちゃじゃ"),
        // 訓令式とヘボン式の別の綴り
        ("iikanzi", "いいかんじ"),
        ("shichitsufuzi", "しちつふじ"),
        ("shachachu", "しゃちゃちゅ"),
        ("zyazyuzyo", "じゃじゅじょ"),
        ("jyajyujyo", "じゃじゅじょ"),
        ("kanchi", "かんち"),
        ("icchi", "いっち"),
    ])
    func readsCommonSpellings(input: String, kana: String) throws {
        #expect(try Shared.table.get().reading(of: input) == kana)
    }

    @Test(arguments: ["she", "che", "la", "ca", "qa", "main"])
    func leavesTheseToEnglish(input: String) throws {
        #expect(try Shared.table.get().reading(of: input) == nil)
    }

    /// azooKey の第 1 候補は「良い感じ」なので、読みが最後まで「いいかんじ」になり、「いい感じ」を候補から選べることを確かめる
    @Test func iikanziReadsAsIiKanzi() throws {
        let engine = try Shared.engine.get()
        let spans = engine.live("iikanzi", leading: .start)
        #expect(spans.map(\.kind) == [.japanese])
        #expect(spans.map(\.reading).joined() == "いいかんじ")
        #expect(spans.map(\.text).joined().hasSuffix("感じ"))
        let clauses = engine.clauses("iikanzi", leading: .start).clauses
        #expect(clauses.contains { $0.candidates.contains("いい感じ") || $0.candidates.contains("いい") }, "\(clauses)")
    }

    /// 途中から英語にならず、最後まで日本語として読む
    @Test(arguments: ["iikanzini", "iikanjini", "sushiwotabeta", "tsunamigakita", "fujisanwomita"])
    func readsToTheEndAsJapanese(input: String) throws {
        let spans = try Shared.engine.get().live(input, leading: .start)
        #expect(spans.allSatisfy { $0.kind == .japanese }, "\(spans)")
        #expect(!spans.map(\.text).joined().contains { $0.isASCII })
    }

    @Test func englishStaysEnglish() throws {
        let spans = try Shared.engine.get().live("she", leading: .start)
        #expect(spans.map(\.text).joined() == "she")
    }

    /// ローマ字で読める短い綴りが英語の語表にあっても、日本語の途中で英語にしない
    @Test(arguments: ["madahitotuninattenaine", "sounanda", "usodesyo", "ikuyo", "orehaikanai"])
    func shortRomajiWordsStayJapanese(input: String) throws {
        let spans = try Shared.engine.get().live(input, leading: .start)
        #expect(spans.allSatisfy { $0.kind == .japanese }, "\(spans)")
    }

    /// よく使う英語の語は、日本語の中でも英語のまま。1 文字の英字とかなに割らない（vnode → vので、state → s縦 にしない）
    @Test(arguments: [
        ("kyouhagithubdekensaku", "github"), ("yahoodesirabeta", "yahoo"),
        ("vnodewotukuru", "vnode"), ("statewokaeru", "state"),
    ])
    func commonEnglishWordsStayEnglish(input: String, word: String) throws {
        let spans = try Shared.engine.get().live(input, leading: .start)
        #expect(spans.contains { $0.kind == .english && $0.text.contains(word) }, "\(spans)")
    }
}
