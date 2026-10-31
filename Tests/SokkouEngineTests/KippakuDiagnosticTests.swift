import Testing
import SokkouCore
import SokkouEngine
import SokkouConverter

// 一時的な診断。kippaku の区切りの候補と点を出す
@Suite struct KippakuDiagnosticTests {
    @Test(arguments: ["kippaku", "ippaku", "kitte", "kappa", "zettai", "sekkaku", "hakkiri", "tyotto", "kekkou"])
    func dump(input: String) throws {
        let table = try AzooKeyEngine.romajiTable()
        let segmenter = Segmenter(table: table, english: try AzooKeyEngine.englishModel(table: table), japanese: ConversionMethod.azooKey.make())
        for leading in [Segmenter.Leading.start, .afterJapanese] {
            let chosen = segmenter.segment(input, leading: leading).map { "\($0.kind):\($0.source)=\($0.output)(\($0.score))" }
            print("DIAG \(input) \(leading) chosen \(chosen)")
            for span in segmenter.candidates(input, leading: leading) {
                print("DIAG \(input) \(leading) [\(span.start),\(span.end)) after=\(String(describing: span.after)) \(span.segment.kind) \(span.segment.source)=\(span.segment.output) \(span.segment.score)")
            }
        }
    }
}
