import Testing
import SokkouCore
import SokkouEngine
import TugimeCore

/// 本物の綴りの表と変換エンジン。作るたびに辞書と語表を読むので、全テストで共有する
private enum Shared {
    static let table = Result { try TugimeEngine.romajiTable() }
    static let engine = Result { try TugimeEngine() }
}

@Suite struct RomajiTests {
    @Test(arguments: [
        // tugime の綴り
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

    @Test func iikanziBecomesIiKanzi() throws {
        let spans = try Shared.engine.get().live("iikanzi", leading: .start)
        #expect(spans.map(\.text).joined() == "いい感じ")
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
}
