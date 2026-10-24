import Foundation

/// 覚えた候補を JSON のファイルに持つ。読みごとに最後に選んだ語だけを残すので、ファイルは小さいまま
public final class FileLearning: Learning {
    private let url: URL
    private var words: [String: String]

    /// ファイルが無いか読めなければ、何も覚えていない状態で始める
    public init(url: URL) {
        self.url = url
        words = (try? JSONDecoder().decode([String: String].self, from: Data(contentsOf: url))) ?? [:]
    }

    public func preferred(for reading: String) -> String? { words[reading] }

    public func record(reading: String, word: String) {
        guard words[reading] != word else { return }
        words[reading] = word
        save()
    }

    /// 覚えた候補をすべて忘れる
    public func forget() {
        words = [:]
        save()
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(words).write(to: url, options: .atomic)
        } catch {
            // 書けなくても入力は止めない。次に選んだときにまた書く
        }
    }
}
