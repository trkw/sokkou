import Testing
@testable import SokkouCore

@MainActor
struct ComposerTests {
    let engine = FakeEngine()

    func composer(learning: (any Learning)? = nil) -> Composer {
        Composer(engine: engine, learning: learning)
    }

    /// キーを順に送り、最後のキーを受け取ったかを返す
    @discardableResult
    func type(_ composer: Composer, _ keys: [Key]) -> Bool {
        var handled = false
        for key in keys {
            handled = composer.handle(key, leading: { .start })
        }
        return handled
    }

    func characters(_ text: String) -> [Key] {
        text.map { $0 == " " ? .space : .character($0) }
    }

    // MARK: 打っている途中

    @Test func typingShowsAutoConversionAndEnterCommitsIt() {
        let composer = composer()
        type(composer, characters("kaku"))
        #expect(composer.presentation.segments == [MarkedSegment(text: "書く", style: .japanese)])
        type(composer, [.enter])
        #expect(composer.takeCommitted() == "書く")
        #expect(!composer.isComposing)
    }

    @Test func englishSpansAreMarkedSeparately() {
        let composer = composer()
        type(composer, characters("dark kaku"))
        #expect(composer.presentation.segments.map(\.style) == [.english, .english, .japanese])
        #expect(composer.presentation.text == "dark 書く")
    }

    @Test func controlGShowsTheRawReadingThenClears() {
        let composer = composer()
        type(composer, characters("kaku") + [.control("g")])
        #expect(composer.presentation.segments == [MarkedSegment(text: "かく", style: .raw)])
        type(composer, [.control("g")])
        #expect(!composer.isComposing)
        #expect(composer.takeCommitted() == "")
    }

    @Test func backspaceToEmptyEndsComposition() {
        let composer = composer()
        type(composer, characters("ka") + [.control("h"), .backspace])
        #expect(!composer.isComposing)
    }

    @Test func controlKTurnsTheWholeInputIntoKatakana() {
        let composer = composer()
        type(composer, characters("kaku") + [.control("k")])
        #expect(composer.presentation.text == "カク")
        type(composer, [.control("m")])
        #expect(composer.takeCommitted() == "カク")
    }

    @Test func unassignedControlKeyCommitsAndPassesThrough() {
        let composer = composer()
        let handled = type(composer, characters("kaku") + [.control("a")])
        #expect(!handled)
        #expect(composer.takeCommitted() == "書く")
    }

    // MARK: 文節選択と候補の窓

    @Test func controlNSelectsThenOpensTheWindowOnTheSecondStep() {
        let composer = composer()
        type(composer, characters("kaku") + [.control("n")])
        #expect(composer.presentation.segments == [MarkedSegment(text: "書く", style: .focused)])
        type(composer, [.control("n")])
        #expect(composer.presentation.text == "描く")
        #expect(composer.presentation.window == nil)
        type(composer, [.control("n")])
        let window = composer.presentation.window
        #expect(window?.items.first == "書く")
        #expect(window?.highlighted == 2)
        #expect(window?.labels == ["a", "s", "d", "f", "j", "k", "l"])
        #expect(window?.pageCount == 2)
    }

    @Test func labelKeyPicksFromTheWindowAndCommitsTheLastClause() {
        let composer = composer()
        type(composer, characters("kaku") + [.control("n"), .control("n"), .control("n"), .character("d")])
        #expect(composer.takeCommitted() == "核")
        #expect(!composer.isComposing)
    }

    @Test func controlFAndBResizeTheFocusedClause() {
        let composer = composer()
        type(composer, characters("kaku") + [.control("f"), .control("b")])
        #expect(engine.resizeCalls == 2)
    }

    @Test func controlGClosesTheWindowThenReturnsToTyping() {
        let composer = composer()
        type(composer, characters("kaku") + [.control("n"), .control("n"), .control("n"), .control("g")])
        #expect(composer.presentation.window == nil)
        #expect(composer.presentation.segments.first?.style == .focused)
        type(composer, [.control("g")])
        #expect(composer.presentation.segments == [MarkedSegment(text: "書く", style: .japanese)])
    }

    @Test func shiftEnterCommitsThroughTheFocusedClause() {
        let composer = composer()
        type(composer, characters("kaku kami") + [.control("n"), .shiftEnter])
        #expect(composer.takeCommitted() == "書く")
        #expect(composer.presentation.text == " 紙")
    }

    @Test func typingAfterSelectingCommitsFirst() {
        let composer = composer()
        type(composer, characters("kaku") + [.control("n"), .control("n"), .character("k")])
        #expect(composer.takeCommitted() == "描く")
        #expect(composer.isComposing)
    }

    @Test func chosenCandidateIsLearnedAndOfferedNextTime() {
        let learning = MemoryLearning()
        let composer = composer(learning: learning)
        type(composer, characters("kaku") + [.control("n"), .control("n"), .control("n"), .enter])
        #expect(composer.takeCommitted() == "核")
        #expect(learning.preferred(for: "かく") == "核")
        type(composer, characters("kaku") + [.control("n"), .control("n")])
        #expect(composer.presentation.text == "核")
    }

    @Test func privateModeDoesNotLearn() {
        let learning = MemoryLearning()
        let composer = composer(learning: learning)
        composer.learns = false
        type(composer, characters("kaku") + [.control("n"), .control("n"), .enter])
        #expect(learning.preferred(for: "かく") == nil)
    }

    // MARK: ▽ ▼

    @Test func semicolonStartsAManualReading() {
        let composer = composer()
        type(composer, [.character(";"), .character("k")])
        #expect(composer.presentation.text == "▽k")
        type(composer, characters("ami"))
        #expect(composer.presentation.text == "▽かみ")
        type(composer, [.space])
        #expect(composer.presentation.text == "▼紙")
        type(composer, [.space])
        #expect(composer.presentation.text == "▼神")
        type(composer, [.enter])
        #expect(composer.takeCommitted() == "神")
    }

    @Test func okuriganaConvertsAsSoonAsItIsRead() {
        let composer = composer()
        type(composer, characters(";ka;k"))
        #expect(composer.presentation.text == "▽か*k")
        type(composer, [.character("u")])
        #expect(composer.presentation.text == "▼書く")
        type(composer, [.control("j")])
        #expect(composer.takeCommitted() == "書く")
    }

    @Test func uppercaseLetterAlsoStartsOkurigana() {
        let composer = composer()
        type(composer, characters(";kaKu"))
        #expect(composer.presentation.text == "▼書く")
    }

    @Test func controlGFromChosenGoesBackToTheReading() {
        let composer = composer()
        type(composer, characters(";ka;ku") + [.control("g")])
        #expect(composer.presentation.text == "▽か")
        type(composer, [.control("g")])
        #expect(!composer.isComposing)
    }

    @Test func controlKCommitsTheReadingAsKatakana() {
        let composer = composer()
        type(composer, characters(";kami") + [.control("k")])
        #expect(composer.takeCommitted() == "カミ")
    }

    @Test func doubleSemicolonTypesASemicolon() {
        let composer = composer()
        type(composer, characters("kaku;;"))
        #expect(composer.presentation.text.hasSuffix(";"))
    }

    @Test func semicolonAfterTypingCommitsTheAutoConversionFirst() {
        let composer = composer()
        type(composer, characters("kaku;ka"))
        #expect(composer.takeCommitted() == "書く")
        #expect(composer.presentation.text == "▽か")
    }

    @Test func typingAfterChosenCommitsIt() {
        let composer = composer()
        type(composer, characters(";kami") + [.space, .character("k")])
        #expect(composer.takeCommitted() == "紙")
        #expect(composer.isComposing)
    }

    @Test func manualChoiceIsLearnedAndComesFirst() {
        let learning = MemoryLearning()
        let composer = composer(learning: learning)
        type(composer, characters(";kami") + [.space, .space, .enter])
        #expect(composer.takeCommitted() == "神")
        type(composer, characters(";kami") + [.space])
        #expect(composer.presentation.text == "▼神")
    }

    // MARK: モード

    @Test func idleModeKeys() {
        let composer = composer()
        type(composer, [.control("q")])
        #expect(composer.mode == .halfwidthKatakana)
        type(composer, [.control("l")])
        #expect(composer.mode == .ascii)
        #expect(!composer.handle(.character("a"), leading: { .start }))
        type(composer, [.control("j")])
        #expect(composer.mode == .hiragana)
        type(composer, [.control("L")])
        #expect(composer.mode == .fullwidthRoman)
        type(composer, [.character("a")])
        #expect(composer.takeCommitted() == "ａ")
        type(composer, [.control("l")])
        #expect(composer.mode == .ascii)
    }

    @Test func controlLWhileTypingCommitsLettersAndEntersAscii() {
        let composer = composer()
        type(composer, characters("kaku") + [.control("l")])
        #expect(composer.takeCommitted() == "kaku")
        #expect(!composer.isComposing)
        #expect(composer.mode == .ascii)
        #expect(!composer.handle(.character("a"), leading: { .start }))
    }

    @Test func idleControlKPassesThroughByDefault() {
        let composer = composer()
        #expect(!composer.handle(.control("k"), leading: { .start }))
        #expect(composer.mode == .hiragana)
        composer.passesIdleControlK = false
        #expect(composer.handle(.control("k"), leading: { .start }))
        #expect(composer.mode == .katakana)
    }

    @Test func idleEmacsKeysPassThrough() {
        let composer = composer()
        for letter in ["n", "p", "f", "b", "a", "e", "h", "m", "g", "d"] as [Character] {
            #expect(!composer.handle(.control(letter), leading: { .start }))
        }
    }

    @Test func katakanaModeShowsTheReadingInKatakana() {
        let composer = composer()
        composer.passesIdleControlK = false
        type(composer, [.control("k")] + characters("kami") + [.enter])
        #expect(composer.takeCommitted() == "カミ")
    }

    @Test func eisuCommitsAndSwitchesToASCII() {
        let composer = composer()
        type(composer, characters("kaku") + [.eisu])
        #expect(composer.takeCommitted() == "書く")
        #expect(composer.mode == .ascii)
        type(composer, [.kana])
        #expect(composer.mode == .hiragana)
    }
}
