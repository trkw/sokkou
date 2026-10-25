import Testing
@testable import SokkouCore

/// ユーザー辞書・SKK 辞書・単語の登録・X・abbrev・補完・数値変換
@MainActor
struct ComposerLexiconTests {
    let engine = FakeEngine()
    let lexicon = SKKLexicon(
        user: UserDictionary(url: temporaryURL()),
        systems: [SKKDictionary(contents: "かみ /加味/\n#かい /#1回/#3回/\nhoge /ほげ/\n")]
    )

    func composer(learning: (any Learning)? = nil) -> Composer {
        Composer(engine: engine, learning: learning, lexicon: lexicon)
    }

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

    // MARK: 文節選択

    @Test func registeredWordIsTheNextCandidateAndDictionaryWordsFollow() {
        lexicon.register("華美", reading: "かみ", okuri: nil)
        let composer = composer()
        type(composer, characters("kami") + [.control("n"), .control("n")])
        #expect(composer.presentation.text == "華美")
        type(composer, [.control("n")])
        let items = composer.presentation.window?.items ?? []
        #expect(items == ["紙", "華美", "神", "髪", "かみ", "加味", Composer.registerItem])
    }

    @Test func registerFromTheWindow() {
        let composer = composer()
        // 紙 神 髪 かみ 加味 登録…（最初の C-n は文節選択に入るだけ）
        type(composer, characters("kami") + Array(repeating: .control("n"), count: 6))
        #expect(composer.presentation.text == Composer.registerItem)
        type(composer, [.enter])
        #expect(composer.isComposing)
        #expect(composer.presentation.segments.first?.text == "［登録 かみ］")
        // 英数にして打つ
        type(composer, [.control("l")] + characters("Kami") + [.enter])
        #expect(composer.takeCommitted() == "Kami")
        #expect(!composer.isComposing)
        #expect(lexicon.userWords(reading: "かみ", okuri: nil) == ["Kami"])
    }

    @Test func registeringTypesJapaneseWithAutoConversion() {
        let composer = composer()
        type(composer, characters("kami") + Array(repeating: .control("n"), count: 6) + [.enter])
        type(composer, characters("kaku") + [.enter])
        #expect(composer.presentation.segments.map(\.text) == ["［登録 かみ］", "書く"])
        type(composer, [.enter])
        #expect(composer.takeCommitted() == "書く")
        #expect(lexicon.userWords(reading: "かみ", okuri: nil) == ["書く"])
    }

    @Test func controlGCancelsRegistering() {
        let composer = composer()
        type(composer, characters("kami") + Array(repeating: .control("n"), count: 6) + [.enter, .control("g")])
        #expect(composer.presentation.text == "紙")
        type(composer, [.enter])
        #expect(composer.takeCommitted() == "紙")
        #expect(lexicon.userWords(reading: "かみ", okuri: nil).isEmpty)
    }

    @Test func registerItemIsNeverCommitted() {
        let composer = composer()
        type(composer, characters("kami") + Array(repeating: .control("n"), count: 6))
        composer.commitAll()
        #expect(composer.takeCommitted() == "かみ")
    }

    @Test func capitalXRemovesTheCandidate() {
        let learning = MemoryLearning()
        let composer = composer(learning: learning)
        // 書く 描く 核 … の 描く を窓で選んで X
        type(composer, characters("kaku") + [.control("n"), .control("n"), .control("n"), .control("p")])
        #expect(composer.presentation.text == "描く")
        type(composer, [.character("X")])
        #expect(composer.presentation.text == "核")
        #expect(lexicon.isIgnored("描く", reading: "かく", okuri: nil))
        composer.cancel()
        type(composer, characters("kaku") + [.control("n"), .control("n")])
        #expect(composer.presentation.text == "核")
    }

    @Test func numberVariantsInTheWindow() {
        let composer = composer()
        type(composer, characters("3") + [.control("n"), .control("n"), .control("n")])
        #expect(composer.presentation.window?.items.contains("三") == true)
    }

    // MARK: ▽ ▼

    @Test func manualReadingOffersUserWordsFirst() {
        lexicon.register("華美", reading: "かみ", okuri: nil)
        let composer = composer()
        type(composer, characters(";kami") + [.space])
        #expect(composer.presentation.text == "▼華美")
    }

    @Test func okuriAriRegistrationStoresTheStem() {
        let composer = composer()
        // ▼書く 描く 欠く かく 登録…
        type(composer, characters(";kaKu"))
        #expect(composer.presentation.text == "▼書く")
        type(composer, Array(repeating: .space, count: 4))
        #expect(composer.presentation.text == "▼" + Composer.registerItem)
        type(composer, [.enter, .control("l")] + characters("X") + [.control("j")] + characters("ku") + [.enter, .enter])
        #expect(composer.takeCommitted() == "Xく")
        #expect(lexicon.userWords(reading: "か", okuri: "k") == ["X"])
        type(composer, characters(";kaKu"))
        #expect(composer.presentation.text == "▼Xく")
    }

    @Test func capitalXInChosenRemovesTheWord() {
        lexicon.register("華美", reading: "かみ", okuri: nil)
        let composer = composer()
        type(composer, characters(";kami") + [.space, .character("X")])
        #expect(composer.presentation.text == "▼紙")
        #expect(lexicon.userWords(reading: "かみ", okuri: nil).isEmpty)
    }

    @Test func numericConversion() {
        let composer = composer()
        type(composer, characters(";3kai") + [.space])
        #expect(composer.presentation.text == "▼3かい")
        type(composer, [.space, .space])
        let items = composer.presentation.window?.items ?? []
        #expect(items.contains("３回"))
        #expect(items.contains("三回"))
    }

    @Test func removedNumberVariantStaysRemoved() {
        let composer = composer()
        // ▼3かい ３回 三回 ３かい
        type(composer, characters(";3kai") + [.space, .space, .space, .space])
        #expect(composer.presentation.text == "▼３かい")
        type(composer, [.character("X")])
        composer.cancel()
        type(composer, characters(";3kai") + [.space, .space, .space])
        #expect(composer.presentation.window?.items.contains("３かい") == false)
    }

    // MARK: abbrev

    @Test func abbrevLooksUpTheDictionary() {
        let composer = composer()
        type(composer, characters("/hoge"))
        #expect(composer.presentation.text == "/hoge")
        type(composer, [.space])
        #expect(composer.presentation.text == "▼ほげ")
        type(composer, [.enter])
        #expect(composer.takeCommitted() == "ほげ")
    }

    @Test func abbrevWithoutDictionaryWordsStaysLiteral() {
        let composer = composer()
        let handled = type(composer, characters("/remind") + [.space])
        #expect(!handled)
        #expect(composer.takeCommitted() == "/remind")
        type(composer, characters("/usr") + [.enter])
        #expect(composer.takeCommitted() == "/usr")
    }

    @Test func abbrevSlashEscapes() {
        let composer = composer()
        type(composer, characters("//"))
        #expect(composer.takeCommitted() == "/")
        #expect(!composer.isComposing)
        type(composer, characters("/."))
        #expect(composer.takeCommitted() == "/")
        #expect(composer.isComposing)
    }

    @Test func abbrevRegistration() {
        let composer = composer()
        // ▼github ｇｉｔｈｕｂ 登録…
        type(composer, characters("/github") + [.control("n"), .space, .space, .enter, .control("l")] + characters("GitHub") + [.enter])
        #expect(composer.takeCommitted() == "GitHub")
        type(composer, characters("/github") + [.space])
        #expect(composer.presentation.text == "▼GitHub")
    }

    // MARK: 補完

    @Test func tabCompletesTheManualReading() {
        lexicon.register("確認", reading: "かくにん", okuri: nil)
        lexicon.register("核心", reading: "かくしん", okuri: nil)
        let composer = composer()
        type(composer, characters(";kaku") + [.tab])
        #expect(composer.presentation.text == "▽かくしん")
        type(composer, [.tab])
        #expect(composer.presentation.text == "▽かくにん")
        type(composer, [.space])
        #expect(composer.presentation.text == "▼確認")
    }

    @Test func tabWhileTypingStartsACompletedReading() {
        lexicon.register("確認", reading: "かくにん", okuri: nil)
        let composer = composer()
        type(composer, characters("kaku") + [.tab])
        #expect(composer.presentation.text == "▽かくにん")
        type(composer, [.backspace, .backspace])
        #expect(composer.presentation.text == "▽かく")
    }

    @Test func tabWithoutCompletionsCommitsAndPasses() {
        let composer = composer()
        let handled = type(composer, characters("kami") + [.tab])
        #expect(!handled)
        #expect(composer.takeCommitted() == "紙")
    }

    // MARK: でたらめなキー

    /// 登録・X・abbrev・補完を混ぜても止まらず、表示が崩れない
    @Test(arguments: 0..<4)
    func randomKeysWithTheLexiconNeverBreak(seed: UInt64) {
        var random = ComposerFuzzTests.Generator(state: seed &+ 100)
        let keys = ComposerFuzzTests.keys + "/X3".map { .character($0) } + [.tab, .tab, .enter]
        lexicon.register("確認", reading: "かくにん", okuri: nil)
        for _ in 0..<300 {
            let composer = composer(learning: MemoryLearning())
            var typed: [Key] = []
            for _ in 0..<Int.random(in: 1...60, using: &random) {
                let key = keys.randomElement(using: &random)!
                typed.append(key)
                _ = composer.handle(key, leading: { .start })
                let presentation = composer.presentation
                if !composer.isComposing {
                    #expect(presentation.segments.isEmpty, "\(typed)")
                }
                if let window = presentation.window {
                    #expect(window.items.count == window.labels.count, "\(typed)")
                    #expect(window.items.indices.contains(window.highlighted), "\(typed)")
                }
                #expect(!composer.takeCommitted().contains(Composer.registerItem), "\(typed)")
            }
            composer.commitAll()
            #expect(!composer.takeCommitted().contains(Composer.registerItem), "\(typed)")
            #expect(composer.presentation == .empty, "\(typed)")
        }
    }
}
