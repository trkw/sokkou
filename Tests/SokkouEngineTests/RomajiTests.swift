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
    @Test(arguments: [
        "iikanzini", "iikanjini", "sushiwotabeta", "tsunamigakita", "fujisanwomita",
        // 子音を重ねた促音。先頭の子音が英字の 1 文字に割れない
        "kitte", "zettai", "sekkaku", "hakkiri", "kekkou", "tyotto", "seppaku",
    ])
    func readsToTheEndAsJapanese(input: String) throws {
        let spans = try Shared.engine.get().live(input, leading: .start)
        #expect(spans.allSatisfy { $0.kind == .japanese }, "\(spans)")
        #expect(!spans.map(\.text).joined().contains { $0.isASCII })
    }

    @Test func englishStaysEnglish() throws {
        let spans = try Shared.engine.get().live("she", leading: .start)
        #expect(spans.map(\.text).joined() == "she")
    }

    /// かなに続く - は、入力の最後でも途中でも長音の ー にする。ハイフンを残さない
    @Test(arguments: ["so-su-", "ko-hi-", "sa-ba-", "konnnitiha-", "su-pa-"])
    func longVowelMarkStaysJapanese(input: String) throws {
        let engine = try Shared.engine.get()
        let spans = engine.live(input, leading: .start)
        #expect(spans.allSatisfy { $0.kind == .japanese }, "\(spans)")
        #expect(!spans.map(\.text).joined().contains("-"), "\(spans)")
        #expect(spans.map(\.reading).joined().hasSuffix("ー"), "\(spans)")
        let clauses = engine.clauses(input, leading: .start).clauses
        #expect(!clauses.map { $0.candidates.first ?? "" }.joined().contains("-"), "\(clauses)")
    }

    /// Space・句読点で確定するときや、日本語に挟まれた - も ー にする。Space の空白はそのまま残す
    @Test(arguments: [("so-su- ", " "), ("so-su-.", "。"), ("ko-hi-wonomu", "む"), ("ko-hi-ha", "は")])
    func longVowelMarkBeforeSpaceOrKana(input: String, suffix: String) throws {
        let text = try Shared.engine.get().live(input, leading: .start).map(\.text).joined()
        #expect(!text.contains("-"), "\(text)")
        #expect(text.contains("ー"), "\(text)")
        #expect(text.hasSuffix(suffix), "\(text)")
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
        // Meltype 1.3.1-pre の判定の直しと同じ入力。英単語の最後の d・t に続く わ行、子音 2 つで始まる語の後の to、母音に挟まれた略語（e2e）も英語のまま
        ("androidwatukaeru", "android"), ("ffmpegtopythonwotukau", "ffmpeg"), ("pptwotukuru", "ppt"), ("e2etesutowokaku", "e2e"),
    ])
    func commonEnglishWordsStayEnglish(input: String, word: String) throws {
        let spans = try Shared.engine.get().live(input, leading: .start)
        #expect(spans.contains { $0.kind == .english && $0.text.contains(word) }, "\(spans)")
    }

    /// 4 かなより短い日本語も、かなのまま確定せずに変換して見せる（kidoku → 既読）
    @Test func shortJapaneseIsConverted() throws {
        let spans = try Shared.engine.get().live("kidoku", leading: .start)
        #expect(spans.map(\.kind) == [.japanese])
        #expect(spans.map(\.text).joined() != "きどく", "\(spans)")
    }

    /// 日本語の途中に英字のかけらを残さない（思わなかったnode にしない）
    @Test func noEnglishFragmentInsideJapanese() throws {
        let spans = try Shared.engine.get().live("omowanakattanode", leading: .start)
        #expect(spans.allSatisfy { $0.kind == .japanese }, "\(spans)")
    }

    /// 日本語に読んだ英単語は 1 つ下で打った綴りに戻せる（gun → 軍 → gun）。英語にならない綴りは最後に置き、変換の候補を先に出す
    @Test func typedSpellingComesSecondOnlyForEnglishWords() throws {
        let engine = try Shared.engine.get()
        let gun = try #require(engine.clauses("gun", leading: .start).clauses.first)
        if gun.candidates.first != "gun" {
            #expect(gun.candidates.dropFirst().first == "gun", "\(gun.candidates)")
        }
        let yuusenn = try #require(engine.clauses("yuusenn", leading: .start).clauses.first)
        #expect(yuusenn.candidates.last == "yuusenn", "\(yuusenn.candidates)")
        #expect(yuusenn.candidates.dropFirst().first != "yuusenn", "\(yuusenn.candidates)")
    }

    /// 入力欄のカーソルの前が半角数字なら、続く日本語は助数詞として読む（3 の後に ninn → 人）
    @Test func readsCountersAfterDigitsBeforeTheCaret() throws {
        let spans = try Shared.engine.get().live("ninn", leading: .afterNumber("3"))
        #expect(spans.map(\.text).joined() == "人", "\(spans)")
    }
}
