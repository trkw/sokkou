import Testing
import SokkouCore
@testable import SokkouEngine

@Suite struct LoanwordTests {
    @Test func readsTheTable() {
        let loanwords = Loanwords(contents: "# 見出し\ntest\tテスト\nvirus\tウイルス\tヴァイラス\n")
        #expect(loanwords.katakana(of: "test") == ["テスト"])
        #expect(loanwords.katakana(of: "Virus") == ["ウイルス", "ヴァイラス"])
        // 前後の空白は付け直し、2 語以上は引かない
        #expect(loanwords.katakana(of: " test ") == [" テスト "])
        #expect(loanwords.katakana(of: "test virus").isEmpty)
        #expect(loanwords.katakana(of: "sokkou").isEmpty)
    }

    @Test func bundledTableHasCommonWords() throws {
        let loanwords = try Loanwords.bundled()
        #expect(loanwords.katakana(of: "test").first == "テスト")
        #expect(loanwords.katakana(of: "update").first == "アップデート")
    }

    @Test func offersKatakanaRightAfterTheSpelling() {
        var clause = Clause(kind: .english, reading: "test", candidates: ["test", "tesuto"], selected: 1)
        TugimeEngine.offer(["テスト", "tesuto"], in: &clause)
        #expect(clause.candidates == ["test", "テスト", "tesuto"])
        #expect(clause.output == "tesuto")
    }

    /// 英語と判定した test を文節選択にすると、英語のままを先頭に、テスト を次の候補に出す
    @Test func englishClauseOffersKatakana() throws {
        let engine = try Shared.engine.get()
        let clauses = engine.clauses("test", leading: .start).clauses
        let english = try #require(clauses.first { $0.kind == .english }, "\(clauses)")
        #expect(english.candidates.prefix(2) == ["test", "テスト"], "\(english)")
    }
}
