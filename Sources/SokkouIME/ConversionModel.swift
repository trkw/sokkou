import AppKit
import CryptoKit
import SokkouConverter

/// 賢い変換に使う言語モデル（GGUF）。設定の「辞書」で 1 つ選ぶか、使わない（既定）。
/// モデルはアプリにも入れず、選んだ人が初めて使うときに Hugging Face からコミットで固定して取ってきて、SHA-256 で確かめる。
/// モデルを足すときは `all` に 1 つ足す。設定の窓も --fetch-model と --bench も、この表から作る。
/// 取ってくるのはメインスレッドの外で行うので、メインアクターに置かない
nonisolated struct ConversionModel: Identifiable, Hashable, Sendable {
    /// モデルの動かし方
    enum Runner: Hashable, Sendable {
        /// azooKey の Zenzai に渡し、azooKey が採点の候補を選び直す（zenz-v3 の形式のモデル）
        case zenzai
        /// zenz 形式のモデルを sokkou が直接動かし、出力をそのまま表示にする（genmai）
        case direct
    }

    /// 設定に書く名前。--fetch-model と --bench にもこれを渡す
    let id: String
    let title: String
    let detail: String
    let fileName: String
    let url: URL
    let sha256: String
    /// 取ってくる大きさ。窓に出すだけなので、丸めた文字列で持つ
    let size: String
    /// 出典と利用条件。README と THIRD_PARTY_NOTICES.md にも同じものを書く
    let credit: String
    let runner: Runner

    static let zenzai = ConversionModel(
        id: "zenzai",
        title: "Zenzai",
        detail: "azooKey の標準のモデル（zenz-v3.2-small）。少し賢く、軽め",
        fileName: "zenz-v3.2-small-Q5_K_M.gguf",
        url: URL(string: "https://huggingface.co/Miwa-Keita/zenz-v3.2-small-gguf/resolve/c67e03e07d215c869f591b274c1631170d3e11fe/ggml-model-Q5_K_M.gguf")!,
        sha256: "29c223d4c23327b80fd13ebb5ab2555057a46317997d5da391584ffbef0db673",
        size: "74MB",
        credit: "zenz-v3.2-small（Miwa-Keita、Apache-2.0）",
        runner: .zenzai
    )

    static let genmai = ConversionModel(
        id: "genmai",
        title: "genmai",
        detail: "zenz-v2.5-medium を育てた genmai-310M。いちばん賢いが、メモリと打鍵ごとの時間がかかる",
        fileName: "genmai-310M-q8_0.gguf",
        url: URL(string: "https://huggingface.co/miyaoka/genmai-310M-GGUF/resolve/d79b9b71c2ff9a6debdb8d2f4670729a2043b5cb/genmai-310M-q8_0.gguf")!,
        sha256: "fa951e50aa42880d08ec24579e089ff7bb7c8057cf0a11b48d18b77b0468986b",
        size: "340MB",
        credit: "genmai-310M（subdiox、CC BY-SA 4.0。GGUF は miyaoka）",
        runner: .direct
    )

    static let all = [zenzai, genmai]

    static func named(_ id: String) -> ConversionModel? {
        all.first { $0.id == id }
    }

    /// モデルを置くところ。入れ物の中の Application Support/sokkou/Models
    static let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("sokkou/Models", isDirectory: true)

    var file: URL { Self.directory.appendingPathComponent(fileName) }

    var isInstalled: Bool { FileManager.default.fileExists(atPath: file.path) }

    var method: ConversionMethod {
        switch runner {
        case .zenzai: .azooKeyZenzai(weight: file)
        case .direct: .direct(weight: file)
        }
    }

    // MARK: 選んでいるモデル

    private static let key = "conversionModel"

    /// 選んでいるモデル。nil なら使わない（azooKey の辞書だけで変換する）
    static var selected: ConversionModel? {
        get { UserDefaults.standard.string(forKey: key).flatMap(named) }
        set { UserDefaults.standard.set(newValue?.id, forKey: key) }
    }

    /// モデルを読み込んでいる間だけ置く印。読み込みの途中でプロセスが止まると残る
    private static let loadingMarker = directory.appendingPathComponent(".loading")

    /// 起動したときに使う方式。前の起動がモデルの読み込みで止まっていたら、同じモデルでまた止まり続けないよう使わない設定に戻す。
    /// モデルを使うときは印を置くので、読み込み終えたら finishedLoading() を呼ぶ
    static func startupMethod() -> ConversionMethod {
        let manager = FileManager.default
        if manager.fileExists(atPath: loadingMarker.path) {
            try? manager.removeItem(at: loadingMarker)
            selected = nil
            return .azooKey
        }
        guard let model = selected, model.isInstalled else { return .azooKey }
        manager.createFile(atPath: loadingMarker.path, contents: nil)
        return model.method
    }

    static func finishedLoading() {
        try? FileManager.default.removeItem(at: loadingMarker)
    }

    // MARK: 取ってくる

    /// モデルを取ってきて、SHA-256 が合えば置く。もう置いてあれば取り直さない
    func fetch() async throws {
        guard !isInstalled else { return }
        let (download, response) = try await URLSession.shared.download(from: url)
        defer { try? FileManager.default.removeItem(at: download) }
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        guard try Self.sha256(of: download) == sha256 else {
            throw InstallError("取ってきた \(title) のモデルの SHA-256 が合いません。途中で書き換えられたか壊れています。")
        }
        try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: download, to: file)
    }

    /// 大きなファイルを一度に読まないよう、1MB ずつ足して数える
    static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// --fetch-model。CI はこれでモデルを取ってきて、--bench で測る
    static func fetchFromCommandLine(_ id: String?) -> Int32 {
        guard let id, let model = named(id) else {
            print("--fetch-model には \(all.map(\.id).joined(separator: " か ")) を渡す")
            return 1
        }
        let done = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var failure: (any Error)?
        Task.detached {
            do { try await model.fetch() } catch { failure = error }
            done.signal()
        }
        done.wait()
        if let failure {
            print("\(model.title) を取ってこられない: \(failure.localizedDescription)")
            return 1
        }
        print(model.file.path)
        return 0
    }

    // MARK: 切り替える

    /// 起動し直したあとに設定の窓を開く印
    static let reopenSettingsArgument = "--reopen-settings"

    /// 変換のエンジンはプロセスに 1 つで、モデルは起動したときに読む。切り替えたら起動し直して、設定の窓を開き直す
    static func relaunch() -> Never {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        // このプロセスが消えてから開く。残っているうちに開くと、LaunchServices が古いほうを前に出すだけになる
        process.arguments = ["-c", "sleep 1; /usr/bin/open -g \"$0\" --args \(reopenSettingsArgument)", Bundle.main.bundlePath]
        try? process.run()
        exit(0)
    }
}
