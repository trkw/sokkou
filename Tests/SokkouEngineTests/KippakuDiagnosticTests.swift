import Testing
import SokkouCore
import SokkouEngine
import SokkouConverter

// 一時的な診断。kippaku の区切りの候補と点を、失敗の文に入れて出す
@Suite struct KippakuDiagnosticTests {
    @Test func dump() async throws {
        let table = try AzooKeyEngine.romajiTable()
        let segmenter = Segmenter(table: table, english: try AzooKeyEngine.englishModel(table: table), japanese: ConversionMethod.azooKey.make())
        var lines: [String] = []
        for input in ["kippaku", "kitte"] {
            for leading in [Segmenter.Leading.start, .afterJapanese] {
                let chosen = segmenter.segment(input, leading: leading).map { "\($0.kind):\($0.source)=\($0.output)(\($0.score))" }
                lines.append("\(input) \(leading) chosen \(chosen)")
                for span in segmenter.candidates(input, leading: leading) {
                    lines.append("  [\(span.start),\(span.end)) after=\(String(describing: span.after)) \(span.segment.kind) \(span.segment.source)=\(span.segment.output) \(span.segment.score)")
                }
            }
        }
        // 変換エンジンの出力に埋もれないよう、ほかのテストが終わってから出す
        try await Task.sleep(for: .seconds(150))
        Issue.record("DIAGDUMP\n\(lines.joined(separator: "\n"))")
    }
}
