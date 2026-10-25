import Foundation
import SokkouCore
import SokkouEngine

/// 変換エンジンはプロセスに 1 つだけ持つ。辞書と語表の読み込みが重いので、入力欄ごとに作らない。
/// 別のファイルの大域変数は初めて使うときに作られるので、インストールや画像の書き出しでは読み込まない
let sharedEngine: AzooKeyEngine = {
    do {
        return try AzooKeyEngine()
    } catch {
        fatalError("sokkou を初期化できない: \(error)")
    }
}()

/// 覚えた候補は ~/Library/Application Support/sokkou/learning.json に置く
let sharedLearning: FileLearning = {
    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    return FileLearning(url: support.appendingPathComponent("sokkou/learning.json"))
}()

/// 自分で登録した語と、追加した SKK 辞書。追加の辞書は大きいので、初めて使うときに別のスレッドで読む
let sharedLexicon: SKKLexicon = {
    let lexicon = SKKLexicon(user: UserDictionary(url: Dictionaries.userURL))
    Dictionaries.reload()
    return lexicon
}()
