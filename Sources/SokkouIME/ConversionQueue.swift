import Foundation
import SokkouConverter
import SokkouCore
import SokkouEngine

/// 変換エンジンを 1 本の直列キューで動かす（tugime の ConversionQueue）。AzooKeyEngine はスレッド安全ではないので、触るのはこのキューの上だけにする。
/// 打っている途中の表示（live）は変換を待たずに積み、変換が届くまでは届いた変換と打鍵の読みから作った表示を返す。
/// 変換は 1 つずつ積み、届いたときに最新の打鍵列がまだなら積む。打鍵が変換より速くても、変換を取り消さずに最新へ追いつく。
/// 文節の選択・確定など、結果が無いと次に進めない呼び出しは、積んだ変換が終わるのを待って返す。確定する文字列（settled）も同じく待つので、
/// 変換が届く前の仮の表示（読み切れない子音が残ったかな）をそのまま確定しない。
/// 状態はメインスレッドだけで読み書きする（Composer も届いた変換もメインスレッドで扱う）
nonisolated final class ConversionQueue: Engine, @unchecked Sendable {
    private let queue = DispatchQueue(label: "sokkou.conversion", qos: .userInteractive)
    private let base: AzooKeyEngine
    /// 綴りの表。変わらない値なので、キューの外から読む
    private let table: RomajiTable
    /// 変換が届いたときに呼ぶ。打っている入力欄が表示を作り直す
    var onConvert: (@MainActor () -> Void)?

    /// 未確定の文字列の世代。終えるたびに進め、届いた変換が今のものかを見分ける
    private var generation = 0
    /// 変換が届いた打鍵列と区間。後から打った分をつなぐ土台にする
    private var converted: [(keys: String, leading: Leading, spans: [Span])] = []
    /// 変換をキューに積み、まだ届いていない
    private var converting = false
    /// 最後に表示を求められた打鍵列。変換が届いたとき、これがまだならこれを積む
    private var latest: (keys: String, leading: Leading)?

    init(base: AzooKeyEngine) {
        self.base = base
        table = base.spellingTable
    }

    func live(_ keys: String, leading: Leading) -> [Span] {
        let bases = converted.filter { $0.leading == leading }.map { (keys: $0.keys, spans: $0.spans) }
        if !bases.contains(where: { $0.keys == keys }) {
            latest = (keys, leading)
            request()
        }
        return AzooKeyEngine.provisional(keys, leading: leading, converted: bases, table: table)
    }

    /// 確定に使う区間。届いていればそれを、届いていなければ積んだ変換が終わるのを待って変換する
    func settled(_ keys: String, leading: Leading) -> [Span] {
        if let same = converted.last(where: { $0.keys == keys && $0.leading == leading }) { return same.spans }
        return queue.sync { base.live(keys, leading: leading) }
    }

    /// 最後に求められた打鍵列の変換を、積んでいなければ積む
    private func request() {
        guard !converting, let (keys, leading) = latest else { return }
        latest = nil
        converting = true
        let generation = generation
        queue.async {
            let spans = self.base.live(keys, leading: leading)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self.didConvert(spans, keys: keys, leading: leading, generation: generation) }
            }
        }
    }

    /// 変換が届いた。今の未確定の文字列のものなら覚えて表示を作り直させ、その間に求められた打鍵列があれば積む
    @MainActor private func didConvert(_ spans: [Span], keys: String, leading: Leading, generation: Int) {
        converting = false
        if generation == self.generation {
            converted.append((keys, leading, spans))
            onConvert?()
        }
        request()
    }

    func clauses(_ keys: String, leading: Leading) -> ClauseList {
        queue.sync { base.clauses(keys, leading: leading) }
    }

    func resize(_ list: ClauseList, at index: Int, by delta: Int, leading: Leading) -> ClauseList {
        queue.sync { base.resize(list, at: index, by: delta, leading: leading) }
    }

    func commit(_ list: ClauseList, through index: Int) -> (text: String, rest: ClauseList, keys: String)? {
        queue.sync { base.commit(list, through: index) }
    }

    func whole(_ keys: String, form: SokkouCore.CharacterForm, leading: Leading) -> ClauseList {
        queue.sync { base.whole(keys, form: form, leading: leading) }
    }

    func form(_ list: ClauseList, at index: Int, to form: SokkouCore.CharacterForm) -> String? {
        queue.sync { base.form(list, at: index, to: form) }
    }

    // kana と convert は綴りの表と文字の変換だけを使うので、変換を待たない
    func kana(_ romaji: String) -> (kana: String, rest: String) {
        base.kana(romaji)
    }

    func convert(kana: String, to form: SokkouCore.CharacterForm) -> String {
        base.convert(kana: kana, to: form)
    }

    func words(reading: String, okurigana: String) -> [String] {
        queue.sync { base.words(reading: reading, okurigana: okurigana) }
    }

    /// 届いた変換を捨て、変換エンジンが覚えたものもキューの上で捨てる
    func endComposition() {
        generation += 1
        converted = []
        latest = nil
        queue.async { self.base.endComposition() }
    }
}
