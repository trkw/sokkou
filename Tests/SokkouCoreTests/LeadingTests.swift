import Testing
import SokkouCore

/// 入力欄のカーソルの前から決める打ち始めの形
struct LeadingTests {
    @Test(arguments: [
        ("", Leading.start), ("今日は ", .start), ("終わり。", .start), ("改行\n", .start),
        ("今日は", .afterJapanese), ("GitHub", .afterEnglish), ("3", .afterNumber("3")), ("合計1500", .afterNumber("1500")),
    ])
    func readsTheTextBeforeTheCaret(text: String, leading: Leading) {
        #expect(Leading(before: text) == leading)
    }

    @Test func endingKeepsSpacesAsEnglish() {
        #expect(Leading(ending: "") == nil)
        #expect(Leading(ending: "foo ") == .afterEnglish)
        #expect(Leading(ending: "第3") == .afterNumber("3"))
        #expect(Leading(ending: "書く") == .afterJapanese)
    }
}
