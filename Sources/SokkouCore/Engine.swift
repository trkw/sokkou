/// 日英の判定とかな漢字変換。sokkou はこれを通してだけ変換エンジンを使う。
/// 入力メソッドは tugime の変換エンジンをつないだもの（SokkouEngine）を、テストは小さな辞書の偽物を渡す
public protocol Engine: AnyObject {
    /// 打っている途中に見せる区間の並び。text をつなぐと、そのまま Enter で確定する文字列になる
    func live(_ keys: String, leading: Leading) -> [Span]
    /// 文節に区切り、文節ごとに候補を付ける
    func clauses(_ keys: String, leading: Leading) -> ClauseList
    /// index の文節を伸ばす（delta が正）・縮める（負）。できなければ元のまま返す
    func resize(_ list: ClauseList, at index: Int, by delta: Int, leading: Leading) -> ClauseList
    /// index の文節までを確定するときの、確定する文字列、残りの文節、残りの打鍵列。切れなければ nil
    func commit(_ list: ClauseList, through index: Int) -> (text: String, rest: ClauseList, keys: String)?
    /// 未確定の文字列全体を 1 つの文字種にした 1 文節
    func whole(_ keys: String, form: CharacterForm, leading: Leading) -> ClauseList
    /// index の文節だけを指定の文字種にした文字列。英字にする打鍵を切り出せなければ nil
    func form(_ list: ClauseList, at index: Int, to form: CharacterForm) -> String?
    /// ローマ字を前から読めるだけかなにする。rest は読み切れずに残った綴り
    func kana(_ romaji: String) -> (kana: String, rest: String)
    /// かなを指定の文字種にする
    func convert(kana: String, to form: CharacterForm) -> String
    /// ▽ で自分で区切った読みを 1 語として変換した候補。okurigana が空でなければ、それで終わる語だけを返す
    func words(reading: String, okurigana: String) -> [String]
    /// 未確定の文字列を確定・取り消ししたときに呼ぶ
    func endComposition()
}

/// 選んだ候補を覚えて、次に同じ読みが来たときに上へ出す
public protocol Learning: AnyObject {
    func preferred(for reading: String) -> String?
    func record(reading: String, word: String)
    /// `X` で消した語を覚えていれば忘れる
    func forget(reading: String, word: String)
}

/// 覚えた候補をメモリだけに持つ。テストとプライベートモードで使う
public final class MemoryLearning: Learning {
    private var words: [String: String] = [:]

    public init() {}

    public func preferred(for reading: String) -> String? { words[reading] }

    public func record(reading: String, word: String) { words[reading] = word }

    public func forget(reading: String, word: String) {
        if words[reading] == word { words[reading] = nil }
    }
}
