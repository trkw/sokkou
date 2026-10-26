import Foundation

/// 日本語区間を変換する方式。変換器はこの値からだけ作る
public enum ConversionMethod: Sendable, Hashable {
    /// azooKey の辞書と n-gram だけで変換する。sokkou の既定
    case azooKey
    /// 採点は azooKey、表示は azooKey の Zenzai に GGUF のモデルを渡して選び直す
    case azooKeyZenzai(weight: URL)
    /// 採点と候補の窓は azooKey（Zenzai なし）、表示は zenz 形式の GGUF のモデル（genmai など）を直接動かした出力そのもの
    case direct(weight: URL)

    /// 方式が読むモデルのファイル。nil ならモデルを使わない方式
    public var weight: URL? {
        switch self {
        case .azooKey: nil
        case .azooKeyZenzai(let weight): weight
        case .direct(let weight): weight
        }
    }

    /// 変換器を作り、モデルを読み込み終えた状態で返す。最初の変換で読み込みの時間が混ざらないよう、ここで先読みまで済ませる。
    /// モデルを読めなければプロセスごと止まる（fatalError。投げるエラーではないので、呼び出し元は受け止められない）
    public func make() -> any JapaneseConverting {
        switch self {
        case .azooKey:
            return AzooKeyConverter(zenzaiWeight: nil)
        case .azooKeyZenzai(let weight):
            let converter = AzooKeyConverter(zenzaiWeight: weight)
            converter.preloadZenzai()
            return converter
        case .direct(let weight):
            // azooKey には Zenzai を渡さない。llama.cpp にモデルを載せるのは ZenzGenerator だけになる
            return DirectConverter(scorer: AzooKeyConverter(zenzaiWeight: nil), generator: ZenzGenerator(weight: weight))
        }
    }
}
