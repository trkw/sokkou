/// sokkou のキー操作の状態機械。キー仕様（docs/keys.md）のとおりに、キーを受けて未確定の文字列と確定する文字列を作る。
/// InputMethodKit に触れないので、macOS 以外でもテストできる
public final class Composer {
    /// 候補の窓で候補を選ぶキー（SKK と同じ）
    public static let labels: [Character] = ["a", "s", "d", "f", "j", "k", "l"]
    /// 候補の最後に置く、単語を登録する項目。選ぶと読みに語を登録する
    public static let registerItem = "登録…"

    public private(set) var mode: InputMode = .hiragana
    /// false にすると選んだ候補を覚えない（プライベートモード）
    public var learns = true
    /// 何も打っていないときの `C-k` をアプリに渡し、macOS の「行末まで削除」を残す。false ならカタカナモードに入る
    public var passesIdleControlK = true

    // SKK の手触りの機能。入力メソッドは設定で切り替える。既定は使わない

    /// 確定した直後の `C-/` で、確定した文字列を未確定に戻して選び直す（ddskk の確定の取り消し）
    public var undoesCommit = false
    /// ▽ の中の `q` で、読みをカタカナにして確定する
    public var convertsWithQ = false
    /// ▼ の `x` で前の候補。候補の窓では Space で次のページ、`x` で前のページ
    public var usesSKKCandidateKeys = false
    /// 打っている途中に 、。！？ を打ったら、そこまでを確定する
    public var commitsAtPunctuation = false
    /// ▽ で、登録した読みの続きを薄く見せる。Tab で採る
    public var suggestsCompletion = false
    /// 候補の窓に SKK 辞書の注釈を出す
    public var showsAnnotations = false

    private let engine: any Engine
    private let learning: (any Learning)?
    private let lexicon: (any Lexicon)?
    private var phase: Phase = .idle
    private var leading: Leading = .start
    /// 確定して、入力メソッドがまだアプリに渡していない文字列
    private var committed = ""
    /// 直前のキーで確定したもの。次のキーが `C-/` なら未確定に戻す
    private var recall: Recall?
    /// 確定したところが、確定の取り消しで戻す状態と、その状態で確定した文字列の始まり（committed の文字数）を決めるとき。
    /// 1 つのキーで 2 回確定したとき（▼ のあとの 。）は、あとの確定だけを取り消す
    private var recallPhase: (phase: Phase, start: Int)?
    /// 確定の取り消しで未確定に戻した文字列。入力メソッドは入力欄のこの文字列を未確定の文字列で置き換える
    private var replaced: String?

    public init(engine: any Engine, learning: (any Learning)? = nil, lexicon: (any Lexicon)? = nil) {
        self.engine = engine
        self.learning = learning
        self.lexicon = lexicon
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

    /// `C-/` で取り消せる、直前に確定した文字列
    public var undoableCommit: String? {
        guard undoesCommit, case .idle = phase else { return nil }
        return recall?.text
    }

    /// 確定を取り消せないことにする。入力欄の文字列が確定したものと合わないとき
    public func forgetCommit() {
        recall = nil
    }

    /// 確定の取り消しで未確定に戻した文字列を受け取る。受け取った分は消える
    public func takeReplaced() -> String? {
        defer { replaced = nil }
        return replaced
    }

    /// 入力ソースの切り替えなど、外からモードを変える。未確定の文字列は確定する
    public func select(mode next: InputMode) {
        commitAll()
        mode = next
    }

    /// 未確定の文字列を、表示しているとおりに確定する
    public func commitAll() {
        // 入力欄を離れたなど。カーソルが動いたかもしれないので、確定の取り消しはできなくする
        recall = nil
        switch phase {
        case .idle:
            return
        case .typing(let typing):
            committed += typingText(typing)
        case .selecting(let selecting):
            learn(selecting, through: selecting.list.clauses.count - 1)
            committed += selecting.list.clauses.map(Self.text).joined()
        case .manual(let manual):
            if let choice = manual.choice {
                committed += word(of: manual, choice)
            } else {
                committed += manual.abbrev ? "/" + manual.stem : manualKana(manual)
            }
        case .registering(let registering):
            // 登録の途中で入力欄を離れたら、登録をやめて元の未確定の文字列を確定する
            phase = registering.back
            commitAll()
            return
        }
        finish()
    }

    /// 未確定の文字列を捨てる
    public func cancel() {
        recall = nil
        finish()
    }

    /// キーを 1 つ処理する。false ならキーをアプリに渡す。leading は打ち始めにだけ呼ぶ
    public func handle(_ key: Key, leading current: () -> Leading) -> Bool {
        if key == .control("/"), undoesCommit, case .idle = phase, let recall {
            self.recall = nil
            leading = recall.leading
            phase = reopened(recall.phase)
            replaced = recall.text
            return true
        }
        recall = nil
        recallPhase = nil
        let before = phase
        let start = committed.count
        let handled = handleKey(key, leading: current)
        if undoesCommit, mode == .hiragana, case .idle = phase, committed.count > start,
           let back = recallPhase ?? Self.recallable(before).map({ (phase: $0, start: start) }) {
            recall = Recall(text: String(committed.dropFirst(back.start)), phase: back.phase, leading: leading)
        }
        recallPhase = nil
        return handled
    }

    private func handleKey(_ key: Key, leading current: () -> Leading) -> Bool {
        if case .registering(let registering) = phase {
            return handleRegistering(key, registering)
        }
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
            case .space:
                // SKK の全英と同じく、空白も全角にする
                committed += "\u{3000}"
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
        case .registering(let registering):
            return handleRegistering(key, registering)
        }
    }

    // MARK: 状態

    private indirect enum Phase {
        case idle
        /// 打っている途中。打つそばから自動変換して見せる
        case typing(Typing)
        /// 文節選択。自動変換の結果を直す
        case selecting(Selecting)
        /// ▽ ▼。`;` で自分で区切った読みと、`/` で始めた abbrev
        case manual(Manual)
        /// 単語の登録。登録する語を、入れ子の Composer で打つ
        case registering(Registering)
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
        /// Tab で補完した読み（かな）。読みは prefix のあとに stem を読んだもの
        var prefix = ""
        /// abbrev。stem は打った英字のままで、読みにもそのまま使う
        var abbrev = false
        /// Tab の補完の候補。Tab 以外のキーで空に戻す
        var completions: [String] = []
        var completionIndex = 0
    }

    private struct Registering {
        /// 辞書の見出しの読み
        var reading: String
        /// 送りありの見出しの、送り仮名の頭のローマ字
        var okuri: Character?
        /// 送り仮名。登録した語のあとに付けて確定する
        var okuriKana: String
        /// 打ち終えた分
        var word = ""
        var inner: Composer
        /// 登録を終えた・やめたときに戻る状態
        var back: Phase
    }

    private struct Choice {
        var words: [String]
        var index = 0
        var window = false
        var steps = 0
    }

    private struct Recall {
        /// 確定した文字列
        var text: String
        /// 確定する前の状態
        var phase: Phase
        var leading: Leading
    }

    /// 確定の取り消しで戻せる、確定する前の状態。戻しても何も無いなら nil
    private static func recallable(_ phase: Phase) -> Phase? {
        switch phase {
        case .typing(let typing) where !typing.keys.isEmpty:
            return phase
        case .selecting:
            return phase
        case .manual(let manual) where !(manual.stem.isEmpty && manual.prefix.isEmpty):
            return phase
        default:
            return nil
        }
    }

    /// 確定を取り消して戻す状態。自動変換は文節選択に、▼ は窓を閉じた ▼ にして、すぐ選び直せるようにする
    private func reopened(_ phase: Phase) -> Phase {
        switch phase {
        case .typing(let typing):
            return .selecting(startSelecting(typing.keys))
        case .selecting(var selecting):
            selecting.list = Self.settled(selecting.list)
            selecting.window = false
            selecting.steps = 0
            return .selecting(selecting)
        case .manual(var manual):
            if var choice = manual.choice {
                choice.window = false
                choice.steps = 0
                manual.choice = choice
            }
            manual.completions = []
            return .manual(manual)
        default:
            return phase
        }
    }

    private func finish() {
        phase = .idle
        engine.endComposition()
    }

    // MARK: 何も打っていないとき

    private func handleIdle(_ key: Key, _ current: () -> Leading) -> Bool {
        switch key {
        case .character("/") where mode == .hiragana:
            leading = current()
            phase = .manual(Manual(stem: "", abbrev: true))
            return true
        case .character(let character):
            leading = current()
            if character == ";" && mode == .hiragana {
                phase = .typing(Typing(keys: "", sticky: true))
            } else {
                let typing = Typing(keys: String(character))
                phase = .typing(typing)
                commitIfSentenceMark(character, typing)
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
            case .character(let character) where character.isASCII && (character.isLetter || character.isNumber):
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
            if commitIfSentenceMark(character, typing) { return true }
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
            var selecting = startSelecting(typing.keys)
            // 打った直後の Shift+← は、最後の文節を選ぶ（文節の移動は両端で反対の端へ回る）
            if key == .shiftLeft { selecting.focus = max(selecting.list.clauses.count - 1, 0) }
            phase = .selecting(selecting)
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
        case .tab:
            if mode == .hiragana, let completions = completions(of: typing), let first = completions.first {
                phase = .manual(Manual(stem: "", prefix: first, completions: completions))
                return true
            }
            committed += typingText(typing)
            finish()
            return false
        case .eisu, .kana:
            break
        }
        phase = .typing(typing)
        return true
    }

    /// 句読点で確定するとき、打った句読点が日本語の 、。！？ になったら、そこまでを確定する。確定したら true
    @discardableResult
    private func commitIfSentenceMark(_ character: Character, _ typing: Typing) -> Bool {
        guard commitsAtPunctuation, mode == .hiragana, Self.sentenceMarks.contains(character),
              engine.live(typing.keys, leading: leading).last?.kind == .punctuation
        else { return false }
        recallPhase = (phase: .typing(typing), start: committed.count)
        committed += typingText(typing)
        finish()
        return true
    }

    /// 句読点で確定するときの、文の区切りの打鍵
    private static let sentenceMarks: Set<Character> = [",", ".", "!", "?"]

    /// 打っている途中の読みを補完する候補。空白や英語を含むときと、補完できないときは nil
    private func completions(of typing: Typing) -> [String]? {
        guard let lexicon, !typing.keys.contains(" ") else { return nil }
        let spans = engine.live(typing.keys, leading: leading)
        guard !spans.isEmpty, spans.allSatisfy({ $0.kind == .japanese }) else { return nil }
        var reading = spans.map(\.reading).joined()
        // 読み切れていない綴り（kais の s）は外して補完する
        while let last = reading.last, last.isASCII, last.isLetter {
            reading.removeLast()
        }
        let completions = lexicon.completions(of: reading)
        return completions.isEmpty ? nil : completions
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
        Selecting(keys: keys, list: decorated(engine.clauses(keys, leading: leading)))
    }

    /// 変換エンジンの候補に、辞書の語・数字の書き方・覚えた候補・登録の項目を足す。何度かけても同じになる
    private func decorated(_ list: ClauseList) -> ClauseList {
        var list = list
        for index in list.clauses.indices {
            let clause = list.clauses[index]
            if clause.kind == .japanese || (clause.kind != .whole && Numeric.template(clause.reading) != nil) {
                list.clauses[index] = decorated(clause)
            }
        }
        return list
    }

    private func decorated(_ clause: Clause) -> Clause {
        var clause = clause
        let current = clause.output
        let engineWords = clause.candidates.filter { $0 != Self.registerItem }
        var words = Array(engineWords.prefix(1))
        if clause.kind == .japanese, let lexicon {
            // 自分で登録した語は、変換エンジンが選んだ語のすぐ次に置く。追加の SKK 辞書の語は後ろに足す
            words += lexicon.userWords(reading: clause.reading, okuri: nil)
            words += engineWords.dropFirst()
            words += lexicon.systemWords(reading: clause.reading, okuri: nil)
        } else {
            words += engineWords.dropFirst()
        }
        words += words.prefix(3).flatMap(Numeric.variants)
        words = Self.unique(words)
        if clause.kind == .japanese {
            if learns, let learning, let word = learning.preferred(for: clause.reading),
               let found = words.firstIndex(of: word), found > 1 {
                // 覚えた候補は、今の候補のすぐ次に置く。表示は変えず、C-n 1 回で選べるようにする
                words.remove(at: found)
                words.insert(word, at: 1)
            }
            if let lexicon {
                words = words.filter { !lexicon.isIgnored($0, reading: clause.reading, okuri: nil) }
                if words.isEmpty { words = [clause.reading] }
                words.append(Self.registerItem)
            }
        }
        clause.candidates = words
        clause.selected = words.firstIndex(of: current) ?? 0
        return clause
    }

    private static func unique(_ words: [String]) -> [String] {
        var seen: Set<String> = []
        return words.filter { seen.insert($0).inserted }
    }

    /// 文節の確定する文字列。登録の項目を選んだままなら読み
    private static func text(_ clause: Clause) -> String {
        clause.output == registerItem ? clause.reading : clause.output
    }

    /// 登録の項目を選んだままの文節を、変換エンジンが選んだ語に戻す
    private static func settled(_ list: ClauseList) -> ClauseList {
        var list = list
        for index in list.clauses.indices where list.clauses[index].output == registerItem {
            list.clauses[index].selected = 0
        }
        return list
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
            if clause.candidates[index] == Self.registerItem {
                selecting.list.clauses[selecting.focus].selected = index
                startRegistering(from: selecting)
            } else {
                pick(selecting, index)
            }
            return true
        case .character("X") where selecting.window && lexicon != nil:
            removeCandidate(&selecting)
        case .space where usesSKKCandidateKeys && selecting.window:
            var clause = selecting.list.clauses[selecting.focus]
            clause.selected = Self.nextPage(from: clause.selected, count: clause.candidates.count)
            selecting.list.clauses[selecting.focus] = clause
            selecting.chosen.insert(selecting.focus)
        case .character("x") where usesSKKCandidateKeys && selecting.window:
            var clause = selecting.list.clauses[selecting.focus]
            if let index = Self.previousPage(from: clause.selected) {
                clause.selected = index
                selecting.list.clauses[selecting.focus] = clause
                selecting.chosen.insert(selecting.focus)
            } else {
                selecting.window = false
            }
        case .space, .shiftSpace, .down, .control("n"):
            step(&selecting, by: 1)
        case .up, .control("p"):
            step(&selecting, by: -1)
        case .right, .control("f"):
            resize(&selecting, by: 1)
        case .left, .control("b"):
            resize(&selecting, by: -1)
        case .shiftRight:
            selecting.list = Self.settled(selecting.list)
            // 両端では反対の端へ回る（tugime・Mozc と同じ）
            selecting.focus = (selecting.focus + 1) % count
            selecting.window = false
            selecting.steps = 0
        case .shiftLeft:
            selecting.list = Self.settled(selecting.list)
            selecting.focus = (selecting.focus - 1 + count) % count
            selecting.window = false
            selecting.steps = 0
        case .enter, .control("m"), .control("j"):
            if selecting.list.clauses[selecting.focus].output == Self.registerItem {
                startRegistering(from: selecting)
                return true
            }
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
            return handleKey(key, leading: leadingProvider)
        }
        phase = .selecting(selecting)
        return true
    }

    /// 候補の窓の次のページの先頭。最後のページなら最初のページに戻る
    private static func nextPage(from index: Int, count: Int) -> Int {
        let start = (index / labels.count + 1) * labels.count
        return start < count ? start : 0
    }

    /// 候補の窓の前のページの先頭。最初のページなら nil
    private static func previousPage(from index: Int) -> Int? {
        let page = index / labels.count
        return page > 0 ? (page - 1) * labels.count : nil
    }

    /// 窓で選んだ候補にして次の文節へ移る。最後の文節なら確定する
    private func pick(_ current: Selecting, _ index: Int) {
        var selecting = current
        selecting.list.clauses[selecting.focus].selected = index
        selecting.chosen.insert(selecting.focus)
        selecting.window = false
        selecting.steps = 0
        guard selecting.focus + 1 < selecting.list.clauses.count else {
            // 確定の取り消しでは、窓で選んだ候補に戻す
            recallPhase = (phase: .selecting(selecting), start: committed.count)
            phase = .selecting(selecting)
            commitAll()
            return
        }
        selecting.focus += 1
        phase = .selecting(selecting)
    }

    /// `X`。選んでいる候補をユーザー辞書から消し、以後は出さない
    private func removeCandidate(_ selecting: inout Selecting) {
        guard let lexicon else { return }
        var clause = selecting.list.clauses[selecting.focus]
        let word = clause.output
        guard clause.kind == .japanese, word != Self.registerItem else { return }
        lexicon.remove(word, reading: clause.reading, okuri: nil)
        learning?.forget(reading: clause.reading, word: word)
        clause.candidates.remove(at: clause.selected)
        if clause.candidates.allSatisfy({ $0 == Self.registerItem }) {
            clause.candidates.insert(clause.reading, at: 0)
        }
        clause.selected = min(clause.selected, clause.candidates.count - 1)
        if clause.output == Self.registerItem { clause.selected = 0 }
        selecting.list.clauses[selecting.focus] = clause
        selecting.chosen.remove(selecting.focus)
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
        selecting.list = decorated(engine.resize(Self.settled(selecting.list), at: selecting.focus, by: delta, leading: leading))
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
            // 登録の項目は最後に残す
            let end = clause.candidates.last == Self.registerItem ? clause.candidates.count - 1 : clause.candidates.count
            clause.candidates.insert(text, at: end)
            clause.selected = end
        }
        selecting.list.clauses[selecting.focus] = clause
        selecting.chosen.remove(selecting.focus)
    }

    /// 選んでいる文節までを確定し、残りは変換したまま次の文節を選ぶ。最後の文節なら全体を確定する
    private func commitThrough(_ current: Selecting) {
        var selecting = current
        selecting.list = Self.settled(selecting.list)
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
        selecting.list = decorated(result.rest)
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
            guard clause.kind == .japanese, clause.selected != 0, clause.output != Self.registerItem else { continue }
            learning.record(reading: clause.reading, word: clause.output)
        }
    }

    // MARK: ▽ ▼

    private func handleManual(_ key: Key, _ current: Manual, _ leadingProvider: () -> Leading) -> Bool {
        var manual = current
        if let choice = manual.choice {
            return chosen(key, manual, choice, leadingProvider)
        }
        if manual.abbrev {
            return handleAbbrev(key, manual, leadingProvider)
        }
        if key != .tab {
            manual.completions = []
        }
        switch key {
        case .character(";"):
            // ▽ の中の ; は、次の英字から送り仮名にする合図
            if manual.okuri == nil { manual.sticky = true }
        case .character("q") where convertsWithQ && !manual.sticky:
            // SKK と同じく、読みをカタカナにして確定する
            committed += engine.convert(kana: manualKana(manual), to: .katakana)
            finish()
            return true
        case .character(let character):
            let letter = character.lowercased()
            if manual.sticky || (character.isUppercase && !(manual.stem.isEmpty && manual.prefix.isEmpty)) {
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
        case .tab:
            // SKK と同じく、ユーザー辞書の読みで補完する。もう一度で次の読み
            guard let lexicon, manual.okuri == nil, !manual.sticky else { break }
            if manual.completions.isEmpty {
                manual.completions = lexicon.completions(of: manualStem(manual))
                manual.completionIndex = 0
            } else {
                manual.completionIndex = (manual.completionIndex + 1) % manual.completions.count
            }
            if !manual.completions.isEmpty {
                manual.prefix = manual.completions[manual.completionIndex]
                manual.stem = ""
            }
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
            } else if !manual.prefix.isEmpty {
                manual.prefix.removeLast()
            }
            if manual.stem.isEmpty && manual.prefix.isEmpty && manual.okuri == nil && !manual.sticky {
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
            committed += manual.prefix + manual.stem + (manual.okuri ?? "")
            finish()
            return true
        case .control("L"):
            committed += manual.prefix + (manual.stem + (manual.okuri ?? "")).map(Self.fullwidth).joined()
            finish()
            return true
        default:
            committed += manualKana(manual)
            finish()
            if case .control = key { return false }
            return handleKey(key, leading: leadingProvider)
        }
        phase = .manual(manual)
        return true
    }

    /// `/` で始めた abbrev。打った英字を読みにして辞書を引く。辞書に無ければ、打ったとおり / を付けて確定する
    private func handleAbbrev(_ key: Key, _ current: Manual, _ leadingProvider: () -> Leading) -> Bool {
        var manual = current
        let literal = "/" + manual.stem
        switch key {
        case .character(let character) where !manual.stem.isEmpty || (character.isASCII && (character.isLetter || character.isNumber)):
            manual.stem.append(character)
        case .character("/"):
            // `//` で / を 1 つ打つ
            committed += "/"
            finish()
            return true
        case .space where !manual.stem.isEmpty && hasDictionaryWords(abbrev: manual.stem):
            manual.choice = makeChoice(manual)
        case .control("n"), .down, .shiftSpace:
            guard !manual.stem.isEmpty else {
                committed += "/"
                finish()
                return handleKey(key, leading: leadingProvider)
            }
            manual.choice = makeChoice(manual)
        case .enter, .control("m"):
            committed += literal
            finish()
            return true
        case .backspace, .control("h"):
            guard !manual.stem.isEmpty else {
                finish()
                return true
            }
            manual.stem.removeLast()
        case .escape, .control("g"):
            finish()
            return true
        default:
            committed += literal
            finish()
            return handleKey(key, leading: leadingProvider)
        }
        phase = .manual(manual)
        return true
    }

    private func hasDictionaryWords(abbrev: String) -> Bool {
        guard let lexicon else { return false }
        return !lexicon.userWords(reading: abbrev, okuri: nil).isEmpty || !lexicon.systemWords(reading: abbrev, okuri: nil).isEmpty
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
            if choice.words[index] == Self.registerItem {
                manual.choice = choice
                startRegistering(from: manual)
            } else {
                commitChoice(manual, choice)
            }
            return true
        case .character("X") where lexicon != nil:
            guard choice.words[choice.index] != Self.registerItem else { break }
            removeChoice(manual, &choice)
            guard choice.words.contains(where: { $0 != Self.registerItem }) else {
                manual.choice = nil
                manual.okuri = nil
                phase = .manual(manual)
                return true
            }
        case .space where usesSKKCandidateKeys && choice.window:
            choice.index = Self.nextPage(from: choice.index, count: choice.words.count)
        case .character("x") where usesSKKCandidateKeys:
            if choice.window {
                if let index = Self.previousPage(from: choice.index) {
                    choice.index = index
                } else {
                    choice.window = false
                }
            } else if choice.index > 0 {
                choice.index -= 1
            } else {
                // 最初の候補で x なら、SKK と同じく ▽ に戻る
                manual.choice = nil
                manual.okuri = nil
                phase = .manual(manual)
                return true
            }
        case .space, .control("n"), .down:
            if !choice.window {
                if choice.steps >= 1 { choice.window = true }
                choice.steps += 1
            }
            choice.index = (choice.index + 1) % choice.words.count
        case .control("p"), .up:
            choice.index = (choice.index - 1 + choice.words.count) % choice.words.count
        case .enter, .control("m"), .control("j"):
            if choice.words[choice.index] == Self.registerItem {
                manual.choice = choice
                startRegistering(from: manual)
            } else {
                commitChoice(manual, choice)
            }
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
            return handleKey(key, leading: leadingProvider)
        }
        manual.choice = choice
        phase = .manual(manual)
        return true
    }

    /// ▼ の `X`。選んでいる語をユーザー辞書から消し、以後は出さない
    private func removeChoice(_ manual: Manual, _ choice: inout Choice) {
        let word = choice.words[choice.index]
        let heading = manualHeading(manual)
        lexicon?.remove(Self.stripping(heading.okuriKana, from: word), reading: heading.reading, okuri: heading.okuri)
        learning?.forget(reading: learningKey(manual), word: word)
        choice.words.remove(at: choice.index)
        choice.index = min(choice.index, choice.words.count - 1)
        if choice.words[choice.index] == Self.registerItem { choice.index = 0 }
    }

    private func commitChoice(_ manual: Manual, _ choice: Choice) {
        // 確定の取り消しでは、確定した候補の ▼ に戻す
        var chosen = manual
        chosen.choice = choice
        recallPhase = (phase: .manual(chosen), start: committed.count)
        if learns, let learning, choice.index != 0 {
            learning.record(reading: learningKey(manual), word: choice.words[choice.index])
        }
        committed += word(of: manual, choice)
        finish()
    }

    private func word(of manual: Manual, _ choice: Choice) -> String {
        let word = choice.words[choice.index]
        return word == Self.registerItem ? (manual.abbrev ? manual.stem : manualKana(manual)) : word
    }

    /// ▽ の読みを辞書の見出しにしたもの
    private func manualHeading(_ manual: Manual) -> (reading: String, okuri: Character?, okuriKana: String) {
        guard !manual.abbrev else { return (manual.stem, nil, "") }
        return (manualStem(manual), manual.okuri?.first, manual.okuri.map { reading($0) } ?? "")
    }

    private func makeChoice(_ manual: Manual) -> Choice? {
        let heading = manualHeading(manual)
        guard !heading.reading.isEmpty else { return nil }
        let okuriKana = heading.okuriKana
        var words: [String] = []
        if let lexicon {
            words += lexicon.userWords(reading: heading.reading, okuri: heading.okuri).map { $0 + okuriKana }
        }
        if manual.abbrev {
            // abbrev は辞書の語を先に、打った英字をあとに出す
            words += lexicon?.systemWords(reading: heading.reading, okuri: nil) ?? []
            words += [manual.stem, manual.stem.map(Self.fullwidth).joined()]
        } else {
            words += engine.words(reading: heading.reading, okurigana: okuriKana)
            words += lexicon?.systemWords(reading: heading.reading, okuri: heading.okuri).map { $0 + okuriKana } ?? []
        }
        words += words.prefix(3).flatMap(Numeric.variants)
        words = Self.unique(words)
        if let lexicon {
            words = words.filter { !lexicon.isIgnored(Self.stripping(okuriKana, from: $0), reading: heading.reading, okuri: heading.okuri) }
        }
        if learns, let learning, let word = learning.preferred(for: learningKey(manual)), let found = words.firstIndex(of: word) {
            words.remove(at: found)
            words.insert(word, at: 0)
        }
        if lexicon != nil {
            words.append(Self.registerItem)
        }
        return words.isEmpty ? nil : Choice(words: words)
    }

    private static func stripping(_ suffix: String, from word: String) -> String {
        guard !suffix.isEmpty, word.hasSuffix(suffix), word.count > suffix.count else { return word }
        return String(word.dropLast(suffix.count))
    }

    private func learningKey(_ manual: Manual) -> String {
        let stem = manualStem(manual)
        guard let okuri = manual.okuri, !manual.abbrev else { return stem }
        return stem + "*" + reading(okuri)
    }

    /// ▽ の読みの語幹（送り仮名を除く）
    private func manualStem(_ manual: Manual) -> String {
        manual.abbrev ? manual.stem : manual.prefix + reading(manual.stem)
    }

    /// 綴りをかなにする。数字はそのまま残す。読み切れずに残った単独の n は「ん」にする（shown が true なら、表示のため残す）
    private func reading(_ romaji: String, shown: Bool = false) -> String {
        var result = ""
        var chunk = ""
        func read() {
            guard !chunk.isEmpty else { return }
            let kana = engine.kana(chunk)
            result += kana.kana + (kana.rest == "n" && !shown ? "ん" : kana.rest)
            chunk = ""
        }
        for character in romaji {
            if character.isASCII && character.isNumber {
                read()
                result.append(character)
            } else {
                chunk.append(character)
            }
        }
        read()
        return result
    }

    private func manualKana(_ manual: Manual) -> String {
        manualStem(manual) + (manual.okuri.map { reading($0) } ?? "")
    }

    // MARK: 単語の登録

    private func startRegistering(from selecting: Selecting) {
        let clause = selecting.list.clauses[selecting.focus]
        startRegistering(Registering(reading: clause.reading, okuri: nil, okuriKana: "", inner: innerComposer(), back: .selecting(selecting)))
    }

    private func startRegistering(from manual: Manual) {
        let heading = manualHeading(manual)
        startRegistering(Registering(
            reading: heading.reading, okuri: heading.okuri, okuriKana: heading.okuriKana, inner: innerComposer(), back: .manual(manual)
        ))
    }

    private func startRegistering(_ registering: Registering) {
        phase = .registering(registering)
    }

    /// 登録する語を打つための Composer。ひらがなで始まり、C-k でカタカナ、C-l で英字も打てる
    private func innerComposer() -> Composer {
        let inner = Composer(engine: engine, learning: learning, lexicon: lexicon)
        inner.learns = learns
        inner.passesIdleControlK = false
        return inner
    }

    private func handleRegistering(_ key: Key, _ current: Registering) -> Bool {
        var registering = current
        if !registering.inner.isComposing {
            switch key {
            case .enter, .control("m"):
                finishRegistering(registering)
                return true
            case .escape, .control("g"):
                cancelRegistering(registering)
                return true
            case .backspace, .control("h"):
                if !registering.word.isEmpty { registering.word.removeLast() }
                phase = .registering(registering)
                return true
            default:
                break
            }
        }
        let leading: Leading = registering.word.last.map { $0.isASCII ? .afterEnglish : .afterJapanese } ?? .start
        let handled = registering.inner.handle(key, leading: { leading })
        registering.word += registering.inner.takeCommitted()
        if !handled {
            // 英数モードの文字と、何も打っていないときの空白は、そのまま語に入れる
            switch key {
            case .character(let character): registering.word.append(character)
            case .space: registering.word.append(" ")
            default: break
            }
        }
        phase = .registering(registering)
        return true
    }

    private func finishRegistering(_ registering: Registering) {
        let word = Self.stripping(registering.okuriKana, from: registering.word.trimmingSpaces)
        guard !word.isEmpty, let lexicon else {
            cancelRegistering(registering)
            return
        }
        lexicon.register(word, reading: registering.reading, okuri: registering.okuri)
        switch registering.back {
        case .selecting(var selecting):
            var clause = selecting.list.clauses[selecting.focus]
            clause.candidates.removeAll { $0 == word }
            let end = clause.candidates.last == Self.registerItem ? clause.candidates.count - 1 : clause.candidates.count
            clause.candidates.insert(word, at: end)
            selecting.list.clauses[selecting.focus] = clause
            pick(selecting, end)
        default:
            committed += word + registering.okuriKana
            finish()
        }
    }

    private func cancelRegistering(_ registering: Registering) {
        switch registering.back {
        case .selecting(var selecting):
            selecting.list = Self.settled(selecting.list)
            selecting.window = false
            selecting.steps = 0
            phase = .selecting(selecting)
        case .manual(var manual):
            if var choice = manual.choice {
                choice.index = 0
                choice.window = false
                choice.steps = 0
                manual.choice = choice
            }
            phase = .manual(manual)
        default:
            phase = registering.back
        }
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
            var window: CandidateWindow?
            if selecting.window {
                window = candidateWindow(reading: clause.reading, words: clause.candidates, index: clause.selected, annotation: { word in
                    clause.kind == .japanese ? self.lexicon?.annotation(of: word, reading: clause.reading, okuri: nil) : nil
                })
            }
            return Presentation(segments: segments, window: window)
        case .manual(let manual):
            if let choice = manual.choice {
                let reading = manual.abbrev ? manual.stem : manualKana(manual)
                let heading = manualHeading(manual)
                var window: CandidateWindow?
                if choice.window {
                    window = candidateWindow(reading: reading, words: choice.words, index: choice.index, annotation: { word in
                        self.lexicon?.annotation(of: Self.stripping(heading.okuriKana, from: word), reading: heading.reading, okuri: heading.okuri)
                    })
                }
                return Presentation(segments: [MarkedSegment(text: "▼" + choice.words[choice.index], style: .manual)], window: window)
            }
            if manual.abbrev {
                return Presentation(segments: [MarkedSegment(text: "/" + manual.stem, style: .manual)])
            }
            var text = "▽" + manual.prefix + reading(manual.stem, shown: true)
            if manual.okuri != nil || manual.sticky {
                text += "*" + reading(manual.okuri ?? "", shown: true)
            }
            var segments = [MarkedSegment(text: text, style: .manual)]
            if let rest = suggestion(manual) {
                segments.append(MarkedSegment(text: rest, style: .suggestion))
            }
            return Presentation(segments: segments)
        case .registering(let registering):
            let okuri = registering.okuriKana.isEmpty ? "" : "*" + registering.okuriKana
            var segments = [MarkedSegment(text: "［登録 " + registering.reading + okuri + "］", style: .manual)]
            if !registering.word.isEmpty {
                segments.append(MarkedSegment(text: registering.word, style: .raw))
            }
            let inner = registering.inner.presentation
            return Presentation(segments: segments + inner.segments, window: inner.window)
        }
    }

    /// ▽ の読みに続く、登録した読みの残り。Tab で 1 つ目の補完を採ると、この読みになる
    private func suggestion(_ manual: Manual) -> String? {
        guard suggestsCompletion, let lexicon, manual.okuri == nil, !manual.sticky, manual.completions.isEmpty else { return nil }
        let typed = manual.prefix + reading(manual.stem, shown: true)
        // 読み切れていない綴りが残っているうちは出さない
        guard let last = typed.last, !(last.isASCII && last.isLetter),
              let first = lexicon.completions(of: typed).first
        else { return nil }
        return String(first.dropFirst(typed.count))
    }

    /// 候補の窓。注釈を出すなら、annotation で候補の注釈を引く
    private func candidateWindow(reading: String, words: [String], index: Int, annotation: (String) -> String?) -> CandidateWindow {
        let size = Self.labels.count
        let page = index / size
        let start = page * size
        let items = Array(words[start..<min(start + size, words.count)])
        var annotations: [String?] = showsAnnotations ? items.map(annotation) : []
        if annotations.allSatisfy({ $0 == nil }) { annotations = [] }
        return CandidateWindow(
            reading: reading,
            items: items,
            labels: Array(Self.labels.prefix(items.count)),
            highlighted: index - start,
            page: page,
            pageCount: (words.count + size - 1) / size,
            annotations: annotations
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

private extension String {
    /// 前後の空白を除いたもの
    var trimmingSpaces: String {
        String(drop { $0 == " " }.reversed().drop { $0 == " " }.reversed())
    }
}
