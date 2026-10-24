import Testing
import SokkouCore
@testable import SokkouEngine

/// 区切りの結果から作る表示が、tugime の liveText と同じになること
@Suite struct LiveTextTests {
    @Test(arguments: [
        "kyouhagithubdekensakusitekara,pull requestwotukurimasu.",
        "asitanokaigidesiryouwosetumeisimasu.",
        "konosystemnoperformancewohakattemitaikedo,doudesyou?",
        "1500enno3konoringo",
        "ka",
        "kyo",
        "iikanzi",
    ])
    func readsTheSameAsTugime(input: String) throws {
        let engine = try Shared.engine.get()
        for leading in [Leading.start, .afterJapanese, .afterEnglish] {
            engine.endComposition()
            engine.readsDisplayFromSegments = true
            let fast = engine.live(input, leading: leading).map(\.text).joined()
            engine.endComposition()
            engine.readsDisplayFromSegments = false
            let slow = engine.live(input, leading: leading).map(\.text).joined()
            engine.readsDisplayFromSegments = true
            #expect(fast == slow, "\(input) \(leading)")
        }
        engine.endComposition()
    }
}
