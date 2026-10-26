import Foundation
import SokkouCore
import SokkouEngine

/// 打鍵ごとにかかる時間とメモリを測る。入力メソッドと同じく、キーを 1 つ処理して表示を作るまでを 1 打鍵とする。
/// 結果は Markdown の表で出し、CI のまとめに載せる。model に賢い変換のモデルの名前を渡すと、そのモデルで測る（先に --fetch-model で取ってくる）
enum Bench {
    /// 普段打つ長さの文と、確定せずに打ち続けた長い文
    static let sentences = [
        "kyouhagithubdekensakusitekara,pull requestwotukurimasu.",
        "asitanokaigidesiryouwosetumeisimasu.",
        "konosystemnoperformancewohakattemitaikedo,doudesyou?",
        "tokyoekidemachiawasesite,lunchnoatoniseminarniikimasu.",
        "nihongonyuuryokunohayasawotamesutamenisukosinagaibunsyouwokakuninsimasu,sikamokakuteisezuniutitudukemasu.",
    ]

    static func run(model id: String?) -> Int32 {
        let model = id.flatMap(ConversionModel.named)
        if let id, model == nil {
            print("--bench には \(ConversionModel.all.map(\.id).joined(separator: " か ")) を渡すか、何も渡さない")
            return 1
        }
        if let model, !model.isInstalled {
            print("\(model.title) のモデルが無い。先に --fetch-model \(model.id) で取ってくる")
            return 1
        }
        let clock = ContinuousClock()
        let loadStart = clock.now
        let engine: AzooKeyEngine
        do {
            engine = try AzooKeyEngine(method: model?.method ?? .azooKey)
        } catch {
            print("変換エンジンを作れない: \(error)")
            return 1
        }
        let load = loadStart.duration(to: clock.now)
        let afterLoad = peakMemory()
        let composer = Composer(engine: engine)

        var typing: [Duration] = []
        var selecting: [Duration] = []
        var byLength: [(length: Int, time: Duration)] = []
        var slowest: [(typed: String, time: Duration)] = []
        func measure(_ key: Key) -> Duration {
            let start = clock.now
            _ = composer.handle(key, leading: { .start })
            _ = composer.presentation
            return start.duration(to: clock.now)
        }

        // 1 周目は辞書のページを読み込むので、2 周目からを測る
        for round in 0..<3 {
            for sentence in sentences {
                for (index, character) in sentence.enumerated() {
                    let time = measure(character == " " ? .space : .character(character))
                    guard round > 0 else { continue }
                    typing.append(time)
                    if round == 2 {
                        byLength.append((index + 1, time))
                        slowest.append((String(sentence.prefix(index + 1)), time))
                    }
                }
                // 文節選択に入り、候補を 2 つ進めて窓を開き、確定する
                for key in [Key.shiftSpace, .space, .space, .enter] {
                    let time = measure(key)
                    if round > 0 { selecting.append(time) }
                }
                _ = composer.takeCommitted()
            }
        }

        let longest = byLength.filter { $0.length > 60 }.map(\.time)
        print("### 賢い変換: \(model.map { "\($0.title)（\($0.fileName)）" } ?? "使わない")")
        print("")
        print("| | 打鍵数 | 中央値 | 95% | 最大 |")
        print("| --- | ---: | ---: | ---: | ---: |")
        print(row("打っている途中", typing))
        print(row("61 打鍵目から", longest))
        print(row("文節選択と確定", selecting))
        print("")
        print("遅かった打鍵（そこまでに打ったもの）")
        print("")
        for entry in slowest.sorted(by: { $0.time > $1.time }).prefix(5) {
            print("- \(ms(entry.time)) ms `\(entry.typed)`")
        }
        print("")
        print("- 辞書と語表\(model == nil ? "" : "とモデル")の読み込み: \(ms(load)) ms")
        print("- メモリの最大（読み込み後）: \(megabytes(afterLoad)) MB")
        print("- メモリの最大（打ち終わり）: \(megabytes(peakMemory())) MB")
        return 0
    }

    private static func row(_ name: String, _ samples: [Duration]) -> String {
        let sorted = samples.sorted()
        guard !sorted.isEmpty else { return "| \(name) | 0 | | | |" }
        func at(_ fraction: Double) -> Duration { sorted[min(sorted.count - 1, Int(Double(sorted.count) * fraction))] }
        return "| \(name) | \(sorted.count) | \(ms(at(0.5))) ms | \(ms(at(0.95))) ms | \(ms(sorted.last!)) ms |"
    }

    private static func ms(_ duration: Duration) -> String {
        let (seconds, attoseconds) = duration.components
        return String(format: "%.2f", Double(seconds) * 1000 + Double(attoseconds) / 1e15)
    }

    private static func megabytes(_ bytes: Int) -> String {
        String(format: "%.0f", Double(bytes) / 1_048_576)
    }

    /// このプロセスが使ったメモリの最大（macOS の ru_maxrss はバイト）
    private static func peakMemory() -> Int {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        return Int(usage.ru_maxrss)
    }
}
