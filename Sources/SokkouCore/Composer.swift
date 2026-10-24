/// sokkou のキー操作の状態機械。キー仕様（docs/keys.md）のとおりに、キーを受けて未確定の文字列と確定する文字列を作る。
/// InputMethodKit に触れないので、macOS 以外でもテストできる
public final class Composer {
    /// 候補の窓で候補を選ぶキー（SKK と同じ）
    public static let labels: [Character] = ["a", "s", "d", "f", "j", "k", "l"]

    public private(set) var mode: InputMode = .hiragana
    /// false にすると選んだ候補を覚えない（プライベートモード）
    public var learns = true
    /// 何も打っていないときの `C-k` をアプリに渡し、macOS の「行末まで削除」を残す。false ならカタカナモードに入る
    public var passesIdleControlK = true

    private let engine: any Engine
    private let learning: (any Learning)?
    private var phase: Phase = .idle
    private var leading: Leading = .start
    /// 確定して、入力メソッドがまだアプリに渡していない文字列
    private var committed = ""

    public init(engine: any Engine, learning: (any Learning)? = nil) {
        self.engine = engine
        self.learning = learning
    }

    // MARK: 入力メソッドから使うもの

    public var isComposing: Bool {
        if case .idle = phase { return false }
        return true
    }

    /// 確定した文字列を受け取る。受け取った分は消える
    public func takeCommitted() -> String {
        defer { committed = "" }
        return committed
    }

    /// 入力ソースの切り替えなど、外からモードを変える。未確定の文字列は確定する
    public func select(mode next: InputMode) {
        commitAll()
        mode = next
    }

    /// 未確定の文字列を、表示しているとおりに確定する
    public func commitAll() {
        switch phase {
        case .idle:
            return
        case .typing(let typing):
            committed += typingText(typing)
        case .selecting(let selecting):
            learn(selecting, through: selecting.list.clauses.count - 1)
            committed += selecting.list.clauses.map(\.output).joined()
        case .manual(let manual):
            committed += manual.choice.map { word(of: manual, $0) } ?? manualKana(manual)
        }
        finish()
    }

    /// 未確定の文字列を捨てる
    public func cancel() {
        finish()
    }

    /// キーを 1 つ処理する。false ならキーをアプリに渡す。leading は打ち始めにだけ呼ぶ
    public func handle(_ key: Key, leading current: () -> Leading) -> Bool {
        switch key {
        case .eisu:
            commitAll()
            mode = .ascii
            return true
        case .kana:
            if mode != .hiragana {
                commitAll()
                mode = .hiragana
            }
            return true
        default:
            break
        }
        switch mode {
        case .ascii:
            guard key == .control("j") else { return false }
            mode = .hiragana
            return true
        case .fullwidthRoman:
            switch key {
            case .control("j"):
                mode = .hiragana
                return true
            case .control("l"):
                mode = .ascii
                return true
            case .character(let character):
                committed += Self.fullwidth(character)
                return true
            default:
                return false
            }
        case .hiragana, .katakana, .halfwidthKatakana:
            break
        }
        switch phase {
        case .idle:
            return handleIdle(key, current)
        case .typing(let typing):
            return handleTyping(key, typing, current)
        case .selecting(let selecting):
            return handleSelecting(key, selecting, current)
        case .manual(let manual):
            return handleManual(key, manual, current)
        }
    }

    // MARK: 状態

    private enum Phase {
        case idle
        /// 打っている途中。打つそばから自動変換して見せる
        case typing(Typing)
        /// 文節選択。自動変換の結果を直す
        case selecting(Selecting)
        /// ▽ ▼。`;` で自分で区切った読み
        case manual(Manual)
    }

    private struct Typing {
        var keys: String
        /// `C-g` で打ったままのかなと英字に戻して見せている
        var raw = false
        /// `;` を押した直後。次の英字から ▽ を始める
        var sticky = false
    }

    private struct Selecting {
        var keys: String
        var list: ClauseList
        var focus = 0
        var window = false
        /// 窓を出さずに次の候補へ進んだ回数。2 回目で窓を出す
        var steps = 0
        /// 自分で候補を選んだ文節。確定するときに覚える
        var chosen: Set<Int> = []
    }

    private struct Manual {
        /// 読みの綴り（ローマ字）
        var stem: String
        /// 送り仮名の綴り。nil なら送り仮名はまだ無い
        var okuri: String?
        /// `;` を押した直後。次の英字から送り仮名にする
        var sticky = false
        /// ▼ の候補。nil なら ▽
        var choice: Choice?
    }

    private struct Choice {
        var words: [String]
        var index = 0
        var window = false
        var steps = 0
    }

    private func finish() {
        phase = .idle
        engine.endComposition()
    }

    // MARK: 何も打っていないとき

    private func handleIdle(_ key: Key, _ current: () -> Leading) -> Bool {
        switch key {
        case .character(let character):
            leading = current()
            if character == ";" && mode == .hiragana {
                phase = .typing(Typing(keys: "", sticky: true))
            } else {
                phase = .typing(Typing(keys: String(character)))
            }
            return true
        case .control("j"):
            mode = .hiragana
            return true
        case .control("k"):
            if passesIdleControlK { return false }
            mode = mode == .katakana ? .hiragana : .katakana
            return true
        case .control("q"):
            mode = mode == .halfwidthKatakana ? .hiragana : .halfwidthKatakana
            return true
        case .control("l"):
            mode = .ascii
            return true
        case .control("L"):
            mode = .fullwidthRoman
            return true
        default:
            return false
        }
    }

    // MARK: 打っている途中

    private func handleTyping(_ key: Key, _ current: Typing, _ leadingProvider: () -> Leading) -> Bool {
        var typing = current
        if typing.sticky {
            typing.sticky = false
            switch key {
            case .character(";"):
                typing.keys.append(";")
                phase = .typing(typing)
                return true
            case .character(let character) where character.isASCII && character.isLetter:
                if !typing.keys.isEmpty {
                    committed += typingText(typing)
                    engine.endComposition()
                }
                phase = .manual(Manual(stem: character.lowercased()))
                return true
            case .escape, .control("g"), .backspace, .control("h"):
                phase = typing.keys.isEmpty ? .idle : .typing(typing)
                return true
            default:
                guard !typing.keys.isEmpty else {
                    phase = .idle
                    return handleIdle(key, leadingProvider)
                }
                phase = .typing(typing)
            }
        }
        switch key {
        case .character(";") where mode == .hiragana:
            typing.sticky = true
            typing.raw = false
        case .character(let character):
            typing.keys.append(character)
            typing.raw = false
        case .space:
            typing.keys.append(" ")
            typing.raw = false
        case .enter, .control("m"), .control("j"):
            committed += typingText(typing)
            finish()
            return true
        case .backspace, .control("h"):
            if !typing.keys.isEmpty { typing.keys.removeLast() }
            typing.raw = false
            if typing.keys.isEmpty {
                finish()
                return true
            }
        case .escape, .control("g"):
            if typing.raw || mode != .hiragana {
                finish()
                return true
            }
            typing.raw = true
        case .shiftSpace, .down, .up, .control("n"), .control("p"), .shiftLeft, .shiftRight:
            guard mode == .hiragana else { break }
            phase = .selecting(startSelecting(typing.keys))
            return true
        case .left, .control("b"), .right, .control("f"):
            guard mode == .hiragana else { break }
            var selecting = startSelecting(typing.keys)
            resize(&selecting, by: key == .left || key == .control("b") ? -1 : 1)
            phase = .selecting(selecting)
            return true
        case .shiftEnter:
            guard mode == .hiragana else {
                committed += typingText(typing)
                finish()
                return true
            }
            commitThrough(startSelecting(typing.keys))
            return true
        case .control("l"):
            // SKK と同じく、打った分を英字のまま確定して英数モードに入る
            if !typing.keys.isEmpty {
                committed += engine.whole(typing.keys, form: .roman, leading: leading).clauses.map(\.output).joined()
            }
            finish()
            mode = .ascii
            return true
        case .control(let letter):
            guard let form = Self.forms[letter] else {
                // 割り当ての無い Ctrl キーは、確定してからアプリに渡す
                committed += typingText(typing)
                finish()
                return false
            }
            phase = .selecting(Selecting(keys: typing.keys, list: engine.whole(typing.keys, form: form, leading: leading)))
            return true
        case .eisu, .kana:
            break
        }
        phase = .typing(typing)
        return true
    }

    /// 入力中に押すと文字種を変えるキー
    private static let forms: [Character: CharacterForm] = [
        "k": .katakana,
        "q": .halfwidthKatakana,
        "l": .roman,
        "L": .fullwidthRoman,
    ]

    private func typingSegments(_ typing: Typing) -> [MarkedSegment] {
        guard !typing.keys.isEmpty else { return [] }
        guard let form = modeForm else {
            let spans = engine.live(typing.keys, leading: leading)
            if typing.raw {
                let text = spans.map { $0.kind == .japanese ? $0.reading : $0.text }.joined()
                return [MarkedSegment(text: text, style: .raw)]
            }
            return spans.map { MarkedSegment(text: $0.text, style: $0.kind == .english ? .english : .japanese) }
        }
        let text = engine.whole(typing.keys, form: form, leading: leading).clauses.map(\.output).joined()
        return [MarkedSegment(text: text, style: .japanese)]
    }

    private func typingText(_ typing: Typing) -> String {
        typingSegments(typing).map(\.text).joined()
    }

    /// カタカナ・半角カタカナモードで、打った読みを出す文字種。ひらがなモードなら nil
    private var modeForm: CharacterForm? {
        switch mode {
        case .katakana: .katakana
        case .halfwidthKatakana: .halfwidthKatakana
        default: nil
        }
    }

    // MARK: 文節選択

    private func startSelecting(_ keys: String) -> Selecting {
        var list = engine.clauses(keys, leading: leading)
        if learns, let learning {
            // 覚えた候補は、今の候補のすぐ次に置く。表示は変えず、C-n 1 回で選べるようにする
            for index in list.clauses.indices where list.clauses[index].kind == .japanese {
                var clause = list.clauses[index]
                guard let word = learning.preferred(for: clause.reading),
                      let found = clause.candidates.firstIndex(of: word), found > 1
                else { continue }
                clause.candidates.remove(at: found)
                clause.candidates.insert(word, at: 1)
                list.clauses[index] = clause
            }
        }
        return Selecting(keys: keys, list: list)
    }

    private func handleSelecting(_ key: Key, _ current: Selecting, _ leadingProvider: () -> Leading) -> Bool {
        var selecting = current
        let count = selecting.list.clauses.count
        switch key {
        case .character(let character) where selecting.window && Self.labels.contains(character):
            let clause = selecting.list.clauses[selecting.focus]
            let start = clause.selected / Self.labels.count * Self.labels.count
            let index = start + Self.labels.firstIndex(of: character)!
            guard index < clause.candidates.count else { break }
            selecting.list.clauses[selecting.focus].selected = index
            selecting.chosen.insert(selecting.focus)
            selecting.window = false
            selecting.steps = 0
            guard selecting.focus + 1 < count else {
                phase = .selecting(selecting)
                commitAll()
                return true
            }
            selecting.focus += 1
        case .space, .shiftSpace, .down, .control("n"):
            step(&selecting, by: 1)
        case .up, .control("p"):
            step(&selecting, by: -1)
        case .right, .control("f"):
            resize(&selecting, by: 1)
        case .left, .control("b"):
            resize(&selecting, by: -1)
        case .shiftRight:
            selecting.focus = min(selecting.focus + 1, count - 1)
            selecting.window = false
            selecting.steps = 0
        case .shiftLeft:
            selecting.focus = max(selecting.focus - 1, 0)
            selecting.window = false
            selecting.steps = 0
        case .enter, .control("m"), .control("j"):
            phase = .selecting(selecting)
            commitAll()
            return true
        case .shiftEnter:
            commitThrough(selecting)
            return true
        case .escape, .control("g"), .backspace, .control("h"):
            guard selecting.window else {
                phase = .typing(Typing(keys: selecting.keys))
                return true
            }
            selecting.window = false
            selecting.steps = 0
        case .control(let letter) where Self.forms[letter] != nil:
            apply(Self.forms[letter]!, to: &selecting)
        default:
            // それ以外のキーは、確定してから打ち始めとして扱う。割り当ての無い Ctrl キーはアプリに渡す
            phase = .selecting(selecting)
            commitAll()
            if case .control = key { return false }
            return handle(key, leading: leadingProvider)
        }
        phase = .selecting(selecting)
        return true
    }

    private func step(_ selecting: inout Selecting, by delta: Int) {
        var clause = selecting.list.clauses[selecting.focus]
        let count = clause.candidates.count
        guard count > 1 else { return }
        if !selecting.window {
            if selecting.steps >= 1 { selecting.window = true }
            selecting.steps += 1
        }
        clause.selected = (clause.selected + delta + count) % count
        selecting.list.clauses[selecting.focus] = clause
        selecting.chosen.insert(selecting.focus)
    }

    private func resize(_ selecting: inout Selecting, by delta: Int) {
        selecting.list = engine.resize(selecting.list, at: selecting.focus, by: delta, leading: leading)
        selecting.focus = min(selecting.focus, selecting.list.clauses.count - 1)
        selecting.window = false
        selecting.steps = 0
        selecting.chosen = []
    }

    private func apply(_ form: CharacterForm, to selecting: inout Selecting) {
        selecting.window = false
        selecting.steps = 0
        // 文節が 1 つなら、全体を 1 つの文字種にする
        guard selecting.list.clauses.count > 1 else {
            selecting.list = engine.whole(selecting.keys, form: form, leading: leading)
            selecting.focus = 0
            selecting.chosen = []
            return
        }
        guard let text = engine.form(selecting.list, at: selecting.focus, to: form) else { return }
        var clause = selecting.list.clauses[selecting.focus]
        if let index = clause.candidates.firstIndex(of: text) {
            clause.selected = index
        } else {
            clause.candidates.append(text)
            clause.selected = clause.candidates.count - 1
        }
        selecting.list.clauses[selecting.focus] = clause
        selecting.chosen.remove(selecting.focus)
    }

    /// 選んでいる文節までを確定し、残りは変換したまま次の文節を選ぶ。最後の文節なら全体を確定する
    private func commitThrough(_ current: Selecting) {
        var selecting = current
        guard selecting.focus < selecting.list.clauses.count - 1 else {
            phase = .selecting(selecting)
            commitAll()
            return
        }
        guard let result = engine.commit(selecting.list, through: selecting.focus) else {
            phase = .selecting(selecting)
            return
        }
        learn(selecting, through: selecting.focus)
        committed += result.text
        leading = result.text.last.map { $0.isASCII ? .afterEnglish : .afterJapanese } ?? leading
        selecting.list = result.rest
        selecting.keys = result.keys
        selecting.focus = 0
        selecting.window = false
        selecting.steps = 0
        selecting.chosen = []
        phase = .selecting(selecting)
    }

    private func learn(_ selecting: Selecting, through last: Int) {
        guard learns, let learning else { return }
        for index in selecting.chosen where index <= last {
            let clause = selecting.list.clauses[index]
            guard clause.kind == .japanese, clause.selected != 0 else { continue }
            learning.record(reading: clause.reading, word: clause.output)
        }
    }

    // MARK: ▽ ▼

    private func handleManual(_ key: Key, _ current: Manual, _ leadingProvider: () -> Leading) -> Bool {
        var manual = current
        if let choice = manual.choice {
            return chosen(key, manual, choice, leadingProvider)
        }
        switch key {
        case .character(";"):
            // ▽ の中の ; は、次の英字から送り仮名にする合図
            if manual.okuri == nil { manual.sticky = true }
        case .character(let character):
            let letter = character.lowercased()
            if manual.sticky || (character.isUppercase && !manual.stem.isEmpty) {
                manual.sticky = false
                manual.okuri = (manual.okuri ?? "") + letter
            } else if let okuri = manual.okuri {
                manual.okuri = okuri + letter
            } else {
                manual.stem += letter
            }
            // 送り仮名が 1 かな読めたら、SKK と同じくすぐに変換する
            if let okuri = manual.okuri {
                let read = engine.kana(okuri)
                if read.rest.isEmpty, !read.kana.isEmpty {
                    manual.choice = makeChoice(manual)
                }
            }
        case .space, .control("n"), .down:
            manual.choice = makeChoice(manual)
        case .enter, .control("m"), .control("j"):
            committed += manualKana(manual)
            finish()
            return true
        case .backspace, .control("h"):
            if manual.sticky {
                manual.sticky = false
            } else if var okuri = manual.okuri {
                okuri.removeLast()
                manual.okuri = okuri.isEmpty ? nil : okuri
            } else if !manual.stem.isEmpty {
                manual.stem.removeLast()
            }
            if manual.stem.isEmpty && manual.okuri == nil && !manual.sticky {
                finish()
                return true
            }
        case .escape, .control("g"):
            finish()
            return true
        case .control("k"), .control("q"):
            let form: CharacterForm = key == .control("k") ? .katakana : .halfwidthKatakana
            committed += engine.convert(kana: manualKana(manual), to: form)
            finish()
            return true
        case .control("l"):
            committed += manual.stem + (manual.okuri ?? "")
            finish()
            return true
        case .control("L"):
            committed += (manual.stem + (manual.okuri ?? "")).map(Self.fullwidth).joined()
            finish()
            return true
        default:
            committed += manualKana(manual)
            finish()
            if case .control = key { return false }
            return handle(key, leading: leadingProvider)
        }
        phase = .manual(manual)
        return true
    }

    private func chosen(_ key: Key, _ current: Manual, _ currentChoice: Choice, _ leadingProvider: () -> Leading) -> Bool {
        var manual = current
        var choice = currentChoice
        switch key {
        case .character(let character) where choice.window && Self.labels.contains(character):
            let start = choice.index / Self.labels.count * Self.labels.count
            let index = start + Self.labels.firstIndex(of: character)!
            guard index < choice.words.count else { break }
            choice.index = index
            commitChoice(manual, choice)
            return true
        case .space, .control("n"), .down:
            if !choice.window {
                if choice.steps >= 1 { choice.window = true }
                choice.steps += 1
            }
            choice.index = (choice.index + 1) % choice.words.count
        case .control("p"), .up:
            choice.index = (choice.index - 1 + choice.words.count) % choice.words.count
        case .enter, .control("m"), .control("j"):
            commitChoice(manual, choice)
            return true
        case .escape, .control("g"), .backspace, .control("h"):
            // ▽ に戻る。送り仮名は SKK と同じく打ち直す
            manual.choice = nil
            manual.okuri = nil
            phase = .manual(manual)
            return true
        default:
            commitChoice(manual, choice)
            if case .control = key { return false }
            return handle(key, leading: leadingProvider)
        }
        manual.choice = choice
        phase = .manual(manual)
        return true
    }

    private func commitChoice(_ manual: Manual, _ choice: Choice) {
        if learns, let learning, choice.index != 0 {
            learning.record(reading: learningKey(manual), word: choice.words[choice.index])
        }
        committed += word(of: manual, choice)
        finish()
    }

    private func word(of manual: Manual, _ choice: Choice) -> String {
        choice.words[choice.index]
    }

    private func makeChoice(_ manual: Manual) -> Choice? {
        let stem = reading(manual.stem)
        guard !stem.isEmpty else { return nil }
        var words = engine.words(reading: stem, okurigana: manual.okuri.map(reading) ?? "")
        if learns, let learning, let word = learning.preferred(for: learningKey(manual)), let found = words.firstIndex(of: word) {
            words.remove(at: found)
            words.insert(word, at: 0)
        }
        return words.isEmpty ? nil : Choice(words: words)
    }

    private func learningKey(_ manual: Manual) -> String {
        let stem = reading(manual.stem)
        guard let okuri = manual.okuri else { return stem }
        return stem + "*" + reading(okuri)
    }

    /// 綴りをかなにする。読み切れずに残った単独の n は「ん」にする
    private func reading(_ romaji: String) -> String {
        let read = engine.kana(romaji)
        return read.kana + (read.rest == "n" ? "ん" : read.rest)
    }

    private func manualKana(_ manual: Manual) -> String {
        reading(manual.stem) + (manual.okuri.map(reading) ?? "")
    }

    // MARK: 表示

    public var presentation: Presentation {
        switch phase {
        case .idle:
            return .empty
        case .typing(let typing):
            var segments = typingSegments(typing)
            if typing.sticky {
                segments.append(MarkedSegment(text: "▽", style: .manual))
            }
            return Presentation(segments: segments)
        case .selecting(let selecting):
            let segments = selecting.list.clauses.enumerated().map { index, clause in
                MarkedSegment(text: clause.output, style: index == selecting.focus ? .focused : .clause)
            }
            let clause = selecting.list.clauses[selecting.focus]
            let window = selecting.window ? Self.window(reading: clause.reading, words: clause.candidates, index: clause.selected) : nil
            return Presentation(segments: segments, window: window)
        case .manual(let manual):
            if let choice = manual.choice {
                let window = choice.window ? Self.window(reading: manualKana(manual), words: choice.words, index: choice.index) : nil
                return Presentation(segments: [MarkedSegment(text: "▼" + word(of: manual, choice), style: .manual)], window: window)
            }
            let stem = engine.kana(manual.stem)
            var text = "▽" + stem.kana + stem.rest
            if manual.okuri != nil || manual.sticky {
                let okuri = engine.kana(manual.okuri ?? "")
                text += "*" + okuri.kana + okuri.rest
            }
            return Presentation(segments: [MarkedSegment(text: text, style: .manual)])
        }
    }

    private static func window(reading: String, words: [String], index: Int) -> CandidateWindow {
        let size = labels.count
        let page = index / size
        let start = page * size
        let items = Array(words[start..<min(start + size, words.count)])
        return CandidateWindow(
            reading: reading,
            items: items,
            labels: Array(labels.prefix(items.count)),
            highlighted: index - start,
            page: page,
            pageCount: (words.count + size - 1) / size
        )
    }

    /// 印字できる ASCII を全角にする
    static func fullwidth(_ character: Character) -> String {
        guard let value = character.asciiValue, (0x21...0x7E).contains(value),
              let scalar = Unicode.Scalar(UInt32(value) + 0xFEE0)
        else { return String(character) }
        return String(Character(scalar))
    }
}
