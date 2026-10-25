import Foundation
import Testing
import SokkouCore
@testable import SokkouEngine

@Suite struct DateWordsTests {
    /// 2026-10-25（日）17:05 JST
    static let tokyo = TimeZone(identifier: "Asia/Tokyo")!
    static let words = DateWords(now: { Date(timeIntervalSince1970: 1_792_915_500) }, timeZone: tokyo)

    @Test func today() {
        #expect(Self.words.candidates(for: "きょう") == [
            "2026年10月25日", "2026年10月25日(日)", "10月25日(日)", "2026/10/25", "2026-10-25", "日曜日",
        ])
    }

    @Test func otherDays() {
        #expect(Self.words.candidates(for: "あした").first == "2026年10月26日")
        #expect(Self.words.candidates(for: "きのう").last == "土曜日")
        #expect(Self.words.candidates(for: "おととい").first == "2026年10月23日")
    }

    @Test func now() {
        #expect(Self.words.candidates(for: "いま") == [
            "17:05", "17時5分", "午後5時5分", "2026年10月25日(日) 17時5分", "10月25日(日) 17時5分", "2026/10/25 17:05",
        ])
        #expect(Self.words.candidates(for: "なう") == Self.words.candidates(for: "いま"))
    }

    @Test func noonAndMidnight() {
        let noon = DateWords(now: { Date(timeIntervalSince1970: 1_792_897_200) }, timeZone: Self.tokyo)
        #expect(noon.candidates(for: "いま")[2] == "午後0時0分")
        let midnight = DateWords(now: { Date(timeIntervalSince1970: 1_792_854_000) }, timeZone: Self.tokyo)
        #expect(midnight.candidates(for: "いま")[2] == "午前0時0分")
    }

    @Test func otherReadingsGetNothing() {
        #expect(Self.words.candidates(for: "きょうは").isEmpty)
        #expect(Self.words.candidates(for: "あめ").isEmpty)
    }

    @Test func appendsAfterTheDictionaryCandidates() {
        var clause = Clause(kind: .japanese, reading: "きょう", candidates: ["今日", "きょう"], selected: 0)
        TugimeEngine.append(["今日", "2026年10月25日"], to: &clause)
        #expect(clause.candidates == ["今日", "きょう", "2026年10月25日"])
        #expect(clause.output == "今日")
    }

    /// 本物のエンジンで kyou だけを文節選択にすると、辞書の候補の後ろに今日の日付が出る
    @Test func engineOffersToday() throws {
        let engine = try Shared.engine.get()
        let clause = try #require(engine.clauses("kyou", leading: .start).clauses.first)
        #expect(clause.candidates.contains { $0.hasSuffix("曜日") }, "\(clause)")
    }
}
