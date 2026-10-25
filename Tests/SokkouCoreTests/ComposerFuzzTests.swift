import Testing
@testable import SokkouCore

/// でたらめなキーの並びを打ち続けても、止まらず、表示が崩れないことを確かめる。
/// 入力メソッドが落ちると打っていた文字が消えるので、状態の組み合わせを広く通しておく
@MainActor
struct ComposerFuzzTests {
    /// 毎回同じ並びになるよう、種から決まる乱数を使う
    struct Generator: RandomNumberGenerator {
        var state: UInt64

        mutating func next() -> UInt64 {
            // SplitMix64
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    /// 辞書の語になりやすい英字を多めにした、打つキーの袋
    static let keys: [Key] = {
        var keys: [Key] = "kakuminosatehoeqx".map { .character($0) }
        keys += "KS;;.,? -1".map { $0 == " " ? .space : .character($0) }
        keys += "ghjkqlLnpfbmx/".map { .control($0) }
        keys += [.control("j"), .control("j"), .space, .shiftSpace, .shiftSpace, .enter, .shiftEnter]
        keys += [.backspace, .escape, .left, .right, .up, .down, .shiftLeft, .shiftRight, .eisu, .kana]
        return keys
    }()

    @Test(arguments: 0..<4)
    func randomKeysNeverBreakThePresentation(seed: UInt64) {
        var random = Generator(state: seed)
        let learning = MemoryLearning()
        for _ in 0..<500 {
            let composer = Composer(engine: FakeEngine(), learning: learning)
            composer.learns = Bool.random(using: &random)
            composer.passesIdleControlK = Bool.random(using: &random)
            composer.undoesCommit = Bool.random(using: &random)
            composer.convertsWithQ = Bool.random(using: &random)
            composer.usesSKKCandidateKeys = Bool.random(using: &random)
            composer.commitsAtPunctuation = Bool.random(using: &random)
            var typed: [Key] = []
            for _ in 0..<Int.random(in: 1...40, using: &random) {
                let key = Self.keys.randomElement(using: &random)!
                typed.append(key)
                _ = composer.handle(key, leading: { .start })
                let presentation = composer.presentation
                if !composer.isComposing {
                    #expect(presentation.segments.isEmpty, "\(typed)")
                }
                if let window = presentation.window {
                    #expect(!window.items.isEmpty, "\(typed)")
                    #expect(window.items.count == window.labels.count, "\(typed)")
                    #expect(window.items.indices.contains(window.highlighted), "\(typed)")
                    #expect((0..<window.pageCount).contains(window.page), "\(typed)")
                }
            }
            composer.commitAll()
            #expect(!composer.isComposing, "\(typed)")
            #expect(composer.presentation == .empty, "\(typed)")
        }
    }
}
