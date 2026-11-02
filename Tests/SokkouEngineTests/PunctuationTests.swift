import Testing
import SokkouCore
import SokkouEngine

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
}
