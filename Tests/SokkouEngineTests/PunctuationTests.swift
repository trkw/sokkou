import Testing
import SokkouCore
import SokkouEngine
@testable import SokkouConverter

@Suite struct PunctuationTests {
    private func text(_ input: String, leading: Leading = .start) throws -> String {
        let engine = try Shared.engine.get()
        engine.endComposition()
        return engine.live(input, leading: leading).map(\.text).joined()
    }

    /// 丸括弧・コロン・等号も句読点と同じく、直前が日本語なら全角、英語なら打ったまま（tugime の 07a4077・38ff323）
    @Test func bracketsColonAndEqualsFollowTheSpanBefore() throws {
        #expect(try text("kore(sore)") == "これ（それ）")
        #expect(try text("kore:sore") == "これ：それ")
        #expect(try text("https:") == "https:")
        #expect(try text("kore=sore") == "これ＝それ")
        #expect(try text("x=1") == "x=1")
        #expect(try text("(", leading: .afterJapanese) == "（")
        #expect(try text("(", leading: .afterEnglish) == "(")
    }

    /// 閉じ括弧は、入れ子を数えて組になる開き括弧の形にそろえる（tugime の 92d96dd）
    @Test func closingBracketsFollowTheirOpeners() throws {
        #expect(try text("kore(github)") == "これ（github）")
        #expect(try text("(kore(sore),f(x))") == "（これ（それ）、f(x)）")
    }

    /// 閉じ括弧の後ろは、そろえた形の後として区切る。全角の後は文の頭、半角の後は英語の後（tugime の d5038a0・c87b52c）
    @Test func punctuationAfterAClosingBracketFollowsItsForm() throws {
        #expect(try text("kore(github).") == "これ（github）。")
        // 文節の伸縮が後ろの文節の文脈を決め直すときも、区切りと同じ続き方にする
        #expect(Segmenter.leading(after: ")", mark: ")") == .afterEnglish)
        #expect(Segmenter.leading(after: ")", mark: "）") == .start)
        #expect(Segmenter.leading(after: "/", mark: "・") == .afterJapanese)
    }

    /// 英語の区間の末尾で打ったままにした句読点は、日本語の記号を候補で選べる。途中の句読点は変えない
    @Test func punctuationAfterEnglishOffersTheJapaneseMark() throws {
        let engine = try Shared.engine.get()
        engine.endComposition()
        let period = engine.clauses(".", leading: .afterEnglish).clauses
        #expect(period.map(\.output) == ["."])
        #expect(period[0].candidates.contains("。"))
        let english = engine.clauses("node.js", leading: .start).clauses
        #expect(english.map(\.output) == ["node.js"])
        #expect(!english[0].candidates.contains("node。js"))
    }

    /// 日本語の後で全角にした括弧は、候補で打ったままの形も選べる
    @Test func bracketsOfferTheTypedForm() throws {
        let engine = try Shared.engine.get()
        engine.endComposition()
        let clauses = engine.clauses("kore(sore)", leading: .start).clauses
        let open = try #require(clauses.first { $0.output == "（" })
        let close = try #require(clauses.first { $0.output == "）" })
        #expect(open.candidates.contains("("))
        #expect(close.candidates.contains(")"))
    }
}
