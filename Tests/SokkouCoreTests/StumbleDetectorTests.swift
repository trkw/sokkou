import Testing
@testable import SokkouCore

@MainActor
struct StumbleDetectorTests {
    /// Composer にキーを送り、入力メソッドと同じように前後を StumbleDetector に見せる
    final class Driver {
        let composer = Composer(engine: FakeEngine())
        var detector = StumbleDetector()
        var time = 0.0
        var found: [Stumble] = []

        init(includesText: Bool = false) {
            detector.includesText = includesText
        }

        func type(_ keys: [Key], every interval: Double = 0.1) {
            for key in keys {
                let stageBefore = composer.stage
                let modeBefore = composer.mode
                let shown = composer.presentation.text
                let handled = composer.handle(key, leading: { .start })
                time += interval
                found += detector.observe(Keystroke(
                    key: key, stageBefore: stageBefore, stageAfter: composer.stage,
                    modeBefore: modeBefore, modeAfter: composer.mode, handled: handled,
                    committed: composer.takeCommitted(), shown: shown, time: time
                ))
            }
        }

        func characters(_ text: String) -> [Key] {
            text.map { $0 == " " ? .space : .character($0) }
        }

        var kinds: [Stumble.Kind] { found.map(\.kind) }
    }

    @Test func plainTypingFindsNothing() {
        let driver = Driver()
        driver.type(driver.characters("kaku") + [.enter])
        driver.type(driver.characters("kami") + [.enter])
        #expect(driver.found.isEmpty)
    }

    @Test func deletingRightAfterCommitIsAStumble() {
        let driver = Driver(includesText: true)
        driver.type(driver.characters("kaku") + [.enter, .backspace, .backspace])
        #expect(driver.kinds == [.deletedAfterCommit])
        #expect(driver.found.first?.text == "書く")
        #expect(driver.found.first?.count == 2)
    }

    @Test func deletingLaterIsNot() {
        let driver = Driver()
        driver.type(driver.characters("kaku") + [.enter])
        driver.type([.backspace], every: 5)
        #expect(driver.found.isEmpty)
    }

    @Test func openingCandidatesAndCommittingIsACorrection() {
        let driver = Driver(includesText: true)
        driver.type(driver.characters("kaku") + [.shiftSpace, .shiftSpace, .enter])
        #expect(driver.kinds == [.corrected])
        #expect(driver.found.first?.count == 2)
        #expect(driver.found.first?.text == "書く → 描く")
    }

    @Test func cancellingTypingIsRecorded() {
        let driver = Driver()
        driver.type(driver.characters("kaku") + [.control("g"), .control("g")])
        #expect(driver.kinds.contains(.cancelled))
    }

    @Test func manyDeletesWhileTypingIsRetyping() {
        let driver = Driver()
        driver.type(driver.characters("kakuka") + [.backspace, .backspace, .backspace, .backspace])
        #expect(driver.kinds == [.retyped])
    }

    @Test func modeKeyForTheCurrentModeIsRecorded() {
        let driver = Driver()
        driver.type([.control("j")])
        #expect(driver.kinds == [.modeKeyDidNothing])
    }

    @Test func typingInTheWrongModeThenSwitching() {
        let driver = Driver()
        driver.type([.control("l")])
        // 英数ではキーはアプリに渡る
        driver.type(driver.characters("kaku") + [.backspace, .backspace, .backspace, .backspace, .control("j")])
        #expect(driver.kinds == [.wrongMode])
        #expect(driver.found.first?.note == "ascii → hiragana")
    }

    @Test func textIsHiddenUnlessAsked() {
        let driver = Driver()
        driver.type(driver.characters("kaku") + [.enter, .backspace])
        #expect(driver.found.first?.text == nil)
        #expect(driver.found.first?.keys == ["字", "字", "字", "字", "⏎", "⌫"])
    }

    @Test func slowKeysAreRecordedAtMostEveryTenSeconds() {
        var detector = StumbleDetector()
        func stroke(_ time: Double, _ milliseconds: Double) -> Keystroke {
            Keystroke(key: .character("k"), stageBefore: .typing, stageAfter: .typing, modeBefore: .hiragana,
                      modeAfter: .hiragana, handled: true, milliseconds: milliseconds, time: time)
        }
        #expect(detector.observe(stroke(1, 150)).map(\.kind) == [.slow])
        #expect(detector.observe(stroke(2, 150)).isEmpty)
        #expect(detector.observe(stroke(3, 20)).isEmpty)
        #expect(detector.observe(stroke(12, 150)).first?.count == 150)
    }
}
