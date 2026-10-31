import Testing
@testable import SokkouCore

/// SKK の手触りの機能: 確定の取り消し・▽ の q・x とページ送り・句読点で確定・読みの続き・注釈
@MainActor
struct ComposerSKKFeelTests {
    let engine = FakeEngine()

    func composer(lexicon: (any Lexicon)? = nil) -> Composer {
        let composer = Composer(engine: engine, lexicon: lexicon)
        composer.undoesCommit = true
        composer.convertsWithQ = true
        composer.usesSKKCandidateKeys = true
        composer.commitsAtPunctuation = true
        composer.suggestsCompletion = true
        composer.showsAnnotations = true
        composer.erasesCommittedClauses = true
        composer.erasesConvertedCharacters = true
        return composer
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

    // MARK: 確定の取り消し

    @Test func undoReopensTheChosenWord() {
        let composer = composer()
        type(composer, characters(";kaku ") + [.space, .enter])
        #expect(composer.takeCommitted() == "描く")
        #expect(composer.undoableCommit == "描く")
        #expect(type(composer, [.control("/")]))
        #expect(composer.takeReplaced() == "描く")
        #expect(composer.takeReplaced() == nil)
        #expect(composer.presentation.text == "▼描く")
        // そのまま選び直せる
        type(composer, [.space, .enter])
        #expect(composer.takeCommitted() == "核")
    }

    @Test func undoReopensAutoConversionAsClauses() {
        let composer = composer()
        type(composer, characters("kaku") + [.enter])
        #expect(composer.takeCommitted() == "書く")
        type(composer, [.control("/")])
        #expect(composer.takeReplaced() == "書く")
        #expect(composer.presentation.segments == [MarkedSegment(text: "書く", style: .focused)])
        type(composer, [.space, .enter])
        #expect(composer.takeCommitted() == "描く")
    }

    @Test func undoReopensTheWordPickedFromTheWindow() {
        let composer = composer()
        // 窓で 核 を強調したまま a で 書く を選ぶ
        type(composer, characters(";kaku ") + [.space, .space, .character("a")])
        #expect(composer.takeCommitted() == "書く")
        type(composer, [.control("/")])
        #expect(composer.takeReplaced() == "書く")
        #expect(composer.presentation.text == "▼書く")
    }

    @Test func undoReopensTheClausePickedFromTheWindow() {
        let composer = composer()
        type(composer, characters("kaku") + [.control("n"), .control("n"), .control("n"), .character("s")])
        #expect(composer.takeCommitted() == "描く")
        type(composer, [.control("/")])
        #expect(composer.takeReplaced() == "描く")
        #expect(composer.presentation.text == "描く")
    }

    @Test func undoAfterAWordAndPunctuationTakesBackOnlyThePunctuation() {
        let composer = composer()
        type(composer, characters(";kaku ") + [.space, .character(".")])
        #expect(composer.takeCommitted() == "描く。")
        type(composer, [.control("/")])
        #expect(composer.takeReplaced() == "。")
        #expect(composer.presentation.text == "。")
    }

    @Test func undoOnlyRightAfterTheCommit() {
        let composer = composer()
        type(composer, characters("kaku") + [.enter])
        _ = composer.takeCommitted()
        type(composer, characters("a") + [.enter])
        _ = composer.takeCommitted()
        type(composer, [.backspace])
        #expect(composer.undoableCommit == nil)
        #expect(!type(composer, [.control("/")]))
        #expect(!composer.isComposing)
    }

    @Test func undoIsOffUnlessEnabled() {
        let composer = Composer(engine: engine)
        type(composer, characters("kaku") + [.enter])
        #expect(composer.undoableCommit == nil)
        #expect(!type(composer, [.control("/")]))
    }

    @Test func forgetCommitPassesTheKey() {
        let composer = composer()
        type(composer, characters("kaku") + [.enter])
        composer.forgetCommit()
        #expect(!type(composer, [.control("/")]))
    }

    // MARK: 確定した語をまとめて消す

    @Test func backspaceErasesCommittedClausesOneByOne() {
        let composer = composer()
        type(composer, characters("kaku no kami") + [.enter])
        #expect(composer.takeCommitted() == "書く の 紙")
        #expect(composer.erasableCommit == "書く の 紙")
        #expect(type(composer, [.backspace]))
        #expect(composer.takeErased() == "紙")
        #expect(composer.takeErased() == nil)
        #expect(composer.erasableCommit == "書く の ")
        // 英語の区間（空白）は 1 文字ずつ、変換した文節はまるごと
        var erased: [String] = []
        for _ in 0..<4 {
            #expect(type(composer, [.control("h")]))
            erased.append(composer.takeErased() ?? "")
        }
        #expect(erased == [" ", "の", " ", "書く"])
        // 消し終えたら、⌫ はアプリに渡す
        #expect(!type(composer, [.backspace]))
        #expect(composer.takeErased() == nil)
    }

    @Test func backspaceErasesTheChosenWordWhole() {
        let composer = composer()
        type(composer, characters(";kaku ") + [.space, .enter])
        #expect(composer.takeCommitted() == "描く")
        type(composer, [.backspace])
        #expect(composer.takeErased() == "描く")
        #expect(!type(composer, [.backspace]))
    }

    @Test func unconvertedReadingGoesOneAtATime() {
        let composer = composer()
        type(composer, characters(";kana") + [.enter])
        #expect(composer.takeCommitted() == "かな")
        type(composer, [.backspace])
        #expect(composer.takeErased() == "な")
        type(composer, [.backspace])
        #expect(composer.takeErased() == "か")
    }

    @Test func punctuationAfterTheWordGoesOneAtATime() {
        let composer = composer()
        type(composer, characters("kaku."))
        #expect(composer.takeCommitted() == "書く。")
        type(composer, [.backspace])
        #expect(composer.takeErased() == "。")
        type(composer, [.backspace])
        #expect(composer.takeErased() == "書く")
    }

    @Test func anotherKeyEndsErasing() {
        let composer = composer()
        type(composer, characters("kaku") + [.enter])
        _ = composer.takeCommitted()
        type(composer, [.left])
        #expect(composer.erasableCommit == nil)
        #expect(!type(composer, [.backspace]))
    }

    @Test func erasingIsOffWhenTurnedOff() {
        let composer = composer()
        composer.erasesCommittedClauses = false
        type(composer, characters("kaku") + [.enter])
        #expect(composer.takeCommitted() == "書く")
        #expect(composer.erasableCommit == nil)
        #expect(!type(composer, [.backspace]))
    }

    @Test func undoStillWorksAfterErasingIsReady() {
        let composer = composer()
        type(composer, characters("kaku") + [.enter])
        _ = composer.takeCommitted()
        type(composer, [.control("/")])
        #expect(composer.takeReplaced() == "書く")
        #expect(composer.erasableCommit == nil)
    }

    // MARK: 変換した字を 1 字ずつ消す

    @Test func backspaceWhileTypingErasesTheLastConvertedCharacter() {
        let composer = composer()
        type(composer, characters("kaku"))
        #expect(composer.presentation.text == "書く")
        #expect(type(composer, [.backspace]))
        #expect(composer.takeCommitted() == "書")
        #expect(!composer.isComposing)
        // C-/ で消す前に戻せる
        type(composer, [.control("/")])
        #expect(composer.takeReplaced() == "書")
        #expect(composer.presentation.text == "書く")
    }

    @Test func erasingTheOnlyConvertedCharacterLeavesNothing() {
        let composer = composer()
        type(composer, characters("kami") + [.control("h")])
        #expect(composer.takeCommitted() == "")
        #expect(!composer.isComposing)
    }

    @Test func unconvertedKanaStillDropsAKeystroke() {
        let composer = composer()
        type(composer, characters("kana") + [.backspace])
        #expect(composer.takeCommitted() == "")
        #expect(composer.isComposing)
    }

    @Test func erasingConvertedCharactersCanBeTurnedOff() {
        let composer = composer()
        composer.erasesConvertedCharacters = false
        type(composer, characters("kaku") + [.backspace])
        #expect(composer.takeCommitted() == "")
        #expect(composer.isComposing)
    }

    // MARK: ▽ の q

    @Test func qInManualCommitsKatakana() {
        let composer = composer()
        type(composer, characters(";kami") + [.character("q")])
        #expect(composer.takeCommitted() == "カミ")
        #expect(!composer.isComposing)
    }

    @Test func qIsALetterWithoutTheFeature() {
        let composer = Composer(engine: engine)
        type(composer, characters(";kamiq"))
        #expect(composer.isComposing)
        #expect(composer.takeCommitted() == "")
    }

    // MARK: x とページ送り

    @Test func xGoesBackAndThenToTheReading() {
        let composer = composer()
        type(composer, characters(";kaku ") + [.space])
        #expect(composer.presentation.text == "▼描く")
        type(composer, [.character("x")])
        #expect(composer.presentation.text == "▼書く")
        type(composer, [.character("x")])
        #expect(composer.presentation.text == "▽かく")
    }

    @Test func spaceAndXTurnWindowPages() {
        let composer = composer()
        // 書く 描く 核 角 格 閣 欠く | 画 拡 かく
        type(composer, characters(";kaku ") + [.space, .space])
        #expect(composer.presentation.window?.page == 0)
        type(composer, [.space])
        #expect(composer.presentation.window?.page == 1)
        #expect(composer.presentation.text == "▼画")
        // 最後のページの次は最初のページ
        type(composer, [.space])
        #expect(composer.presentation.window?.page == 0)
        type(composer, [.space, .character("x")])
        #expect(composer.presentation.window?.page == 0)
        type(composer, [.character("x")])
        #expect(composer.presentation.window == nil)
        #expect(composer.isComposing)
    }

    /// PageDown / PageUp で候補の窓のページを送る（Meltype と同じ）。変換していないときはアプリに渡す
    @Test func pageKeysTurnWindowPages() {
        let composer = composer()
        #expect(!type(composer, [.pageDown]))
        // 打っている途中の PageUp は、確定してからアプリに渡す
        type(composer, characters("kaku"))
        #expect(!type(composer, [.pageUp]))
        #expect(composer.takeCommitted() == "書く")
        #expect(!composer.isComposing)
        type(composer, characters("kaku") + [.pageDown])
        #expect(composer.presentation.window?.page == 0)
        type(composer, [.pageDown])
        #expect(composer.presentation.window?.page == 1)
        type(composer, [.pageUp])
        #expect(composer.presentation.window?.page == 0)
        type(composer, [.pageUp])
        #expect(composer.presentation.window?.page == 0)
        let manual = self.composer()
        type(manual, characters(";kaku ") + [.pageDown])
        #expect(manual.presentation.window?.page == 0)
        type(manual, [.pageDown])
        #expect(manual.presentation.window?.page == 1)
        #expect(manual.presentation.text == "▼画")
        type(manual, [.pageUp])
        #expect(manual.presentation.window?.page == 0)
    }

    @Test func spaceTurnsPagesInClauseSelection() {
        let composer = composer()
        type(composer, characters("kaku") + [.control("n"), .control("n"), .control("n")])
        #expect(composer.presentation.window?.page == 0)
        type(composer, [.space])
        #expect(composer.presentation.window?.page == 1)
        type(composer, [.character("x")])
        #expect(composer.presentation.window?.page == 0)
        type(composer, [.character("x")])
        #expect(composer.presentation.window == nil)
        #expect(composer.isComposing)
    }

    // MARK: 句読点で確定

    @Test func japanesePunctuationCommits() {
        let composer = composer()
        type(composer, characters("kaku."))
        #expect(composer.takeCommitted() == "書く。")
        #expect(!composer.isComposing)
        // 取り消すと句読点まで戻る
        type(composer, [.control("/")])
        #expect(composer.takeReplaced() == "書く。")
        #expect(composer.presentation.text == "書く。")
    }

    @Test func punctuationAfterEnglishStaysComposing() {
        let composer = composer()
        type(composer, characters("github."))
        #expect(composer.isComposing)
        #expect(composer.takeCommitted() == "")
    }

    @Test func punctuationWithoutTheFeatureStaysComposing() {
        let composer = Composer(engine: engine)
        type(composer, characters("kaku."))
        #expect(composer.isComposing)
        #expect(composer.presentation.text == "書く。")
    }

    // MARK: 読みの続き

    @Test func suggestionShowsTheRestOfARegisteredReading() {
        let lexicon = SKKLexicon(user: UserDictionary(url: temporaryURL()))
        lexicon.register("神様", reading: "かみさま", okuri: nil)
        let composer = composer(lexicon: lexicon)
        type(composer, characters(";kami"))
        #expect(composer.presentation.segments == [
            MarkedSegment(text: "▽かみ", style: .manual),
            MarkedSegment(text: "さま", style: .suggestion),
        ])
        // 読み切れていない綴りがあるうちは出さない
        type(composer, characters("s"))
        #expect(composer.presentation.segments.count == 1)
        type(composer, [.backspace, .tab])
        #expect(composer.presentation.segments == [MarkedSegment(text: "▽かみさま", style: .manual)])
    }

    // MARK: 注釈

    @Test func windowShowsAnnotations() {
        let lexicon = SKKLexicon(
            user: UserDictionary(url: temporaryURL()),
            systems: [SKKDictionary(contents: "かみ /加味;味を加える/紙;*paper/\n")]
        )
        let composer = composer(lexicon: lexicon)
        // 紙 神 髪 かみ 加味 登録…
        type(composer, characters(";kami ") + [.space, .space])
        let window = composer.presentation.window
        #expect(window?.items == ["紙", "神", "髪", "かみ", "加味", Composer.registerItem])
        #expect(window?.annotations == ["paper", nil, nil, nil, "味を加える", nil])
        composer.showsAnnotations = false
        #expect(composer.presentation.window?.annotations == [])
    }

    @Test func annotationOfAWord() {
        let dictionary = SKKDictionary(contents: "かk /書;write/描;(skk-ignore)/\nかみ /紙/\n")
        #expect(dictionary.annotation(of: "書", reading: "か", okuri: "k") == "write")
        #expect(dictionary.annotation(of: "描", reading: "か", okuri: "k") == nil)
        #expect(dictionary.annotation(of: "紙", reading: "かみ", okuri: nil) == nil)
        #expect(dictionary.words(reading: "か", okuri: "k") == ["書", "描"])
    }
}
