import Testing
@testable import SokkouCore

struct ModeMemoryTests {
    let terminal = "com.mitchellh.ghostty"
    let editor = "com.apple.TextEdit"

    @Test func terminalsStartInAscii() {
        let memory = ModeMemory()
        #expect(memory.mode(for: terminal) == .ascii)
        #expect(memory.mode(for: editor) == .hiragana)
        #expect(memory.mode(for: nil) == .hiragana)
    }

    @Test func movingToAnotherAppRestoresItsMode() {
        let memory = ModeMemory()
        #expect(memory.activate(editor, current: .hiragana, source: .japanese) == .hiragana)
        memory.remember(.ascii, for: editor)
        #expect(memory.activate(terminal, current: .ascii, source: .roman) == .ascii)
        memory.remember(.hiragana, for: terminal)
        #expect(memory.activate(editor, current: .hiragana, source: .japanese) == .ascii)
        #expect(memory.activate(terminal, current: .ascii, source: .roman) == .hiragana)
    }

    @Test func withinTheSameAppTheSelectedSourceWins() {
        let memory = ModeMemory()
        #expect(memory.activate(terminal, current: .hiragana, source: .roman) == .ascii)
        // ABC から sokkou (日本語) に切り替えた。覚えた英数には戻さない
        #expect(memory.activate(terminal, current: .ascii, source: .japanese) == .hiragana)
        #expect(memory.mode(for: terminal) == .hiragana)
        // 同じアプリの別の欄。新しい入力コントローラはひらがなで始まるが、入力ソースが英数なら英数
        memory.remember(.ascii, for: terminal)
        #expect(memory.activate(terminal, current: .hiragana, source: .roman) == .ascii)
    }

    @Test func kanaModesStayWhenTheSourceMatches() {
        let memory = ModeMemory()
        _ = memory.activate(editor, current: .hiragana, source: .japanese)
        #expect(memory.activate(editor, current: .katakana, source: .japanese) == .katakana)
    }

    @Test func switchingBetweenAsciiAndKanaSelectsTheSource() {
        #expect(ModeChangeReaction(from: .hiragana, to: .ascii) == .selectSource(.roman))
        #expect(ModeChangeReaction(from: .ascii, to: .hiragana) == .selectSource(.japanese))
        #expect(ModeChangeReaction(from: .katakana, to: .ascii) == .selectSource(.roman))
        #expect(ModeChangeReaction(from: .fullwidthRoman, to: .ascii) == .selectSource(.roman))
    }

    @Test func kanaModesShowTheBadge() {
        #expect(ModeChangeReaction(from: .hiragana, to: .katakana) == .showBadge)
        #expect(ModeChangeReaction(from: .katakana, to: .hiragana) == .showBadge)
        #expect(ModeChangeReaction(from: .hiragana, to: .fullwidthRoman) == .showBadge)
    }
}
