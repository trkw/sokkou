import AppKit

/// 入力メニューと自動の更新から頼まれて、新しい版に入れ替える。中身はこのアプリに入れた install.sh（Resources/update.sh）で、
/// 取ってきた版のインストーラーの --install が sokkou を止めて、入れた版を起動し直す。
/// 入れ替わったら新しい sokkou が、しくじったらこのアプリが、窓で知らせる
enum Update {
    static let log = home.appendingPathComponent("Library/Logs/sokkou-update.log")

    /// いま入っている sokkou のビルド（例: v0.1.7 · abc1234、PR #4 · abc1234）
    private static var build: String {
        Installer.ime.object(forInfoDictionaryKey: "SokkouBuild") as? String
            ?? Installer.ime.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "?"
    }

    /// 最新のリリースか、pr を渡したらその PR の CI のビルドを、rollback なら取っておいた 1 つ前の版を入れる。
    /// quiet なら、しくじっても窓を出さない（自動の更新。ログには残り、次に確かめたときにまた試す）
    static func run(pr: Int?, rollback: Bool, quiet: Bool, reason: String?) -> Int32 {
        guard let script = Bundle.main.url(forResource: "update", withExtension: "sh") else {
            print("update.sh が無い")
            return 1
        }
        var arguments = [script.path, "--notify"]
        if rollback {
            guard FileManager.default.fileExists(atPath: Installer.previous.path) else {
                if !quiet {
                    Installer.alert("前の版に戻せませんでした", "取っておいた前の版がありません。")
                }
                return 1
            }
            arguments.append(Installer.previous.path)
        } else if let pr {
            arguments += ["--pr", String(pr)]
        }
        let reason = reason ?? (rollback ? "前の版に戻す" : pr.map { "PR #\($0) の版を入れる" } ?? "最新版に更新")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = arguments
        if let handle = openLog() {
            handle.write(Data("\n==== \(Date().formatted(.iso8601)) \(reason)（\(build) から）\n".utf8))
            process.standardOutput = handle
            process.standardError = handle
        }
        do {
            try process.run()
        } catch {
            if !quiet {
                Installer.alert("更新を始められませんでした", error.localizedDescription)
            }
            return 1
        }
        process.waitUntilExit()
        // 入れ替えられたら新しい sokkou が知らせる。入れられなかったときは古い sokkou が残るので、ここで知らせる（通知は許可が無いと出ないため）
        if process.terminationStatus != 0, !quiet {
            reportFailure()
        }
        return process.terminationStatus
    }

    /// 更新のたびに書き足す。512 KB を超えたら古いほうの半分を捨てる
    private static func openLog() -> FileHandle? {
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: log.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let size = (try? fileManager.attributesOfItem(atPath: log.path))?[.size] as? Int, size > 512 * 1024,
           let data = try? Data(contentsOf: log) {
            try? data.suffix(256 * 1024).write(to: log)
        }
        if !fileManager.fileExists(atPath: log.path) {
            fileManager.createFile(atPath: log.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: log) else { return nil }
        handle.seekToEndOfFile()
        return handle
    }

    /// ログの最後の「失敗: 」の行を出す。無ければ最後の 3 行
    private static func reportFailure() {
        let text = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
        let lines = text.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
        let reason = lines.last { $0.contains("失敗: ") }.map { String($0[$0.range(of: "失敗: ")!.upperBound...]) }
            ?? lines.suffix(3).joined(separator: "\n")
        Installer.alert("更新できませんでした", "\(reason)\n\n今の版（\(build)）のまま使えます。詳しくは ~/Library/Logs/sokkou-update.log")
    }
}
