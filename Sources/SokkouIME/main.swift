import Carbon
import Cocoa
import InputMethodKit
import SokkouCore

/// バンドルを入力ソースとして登録する。有効化はしない（利用者がシステム設定の「+」で追加する）
func register() -> Int32 {
    let url = Bundle.main.bundleURL as CFURL
    let status = TISRegisterInputSource(url)
    print("TISRegisterInputSource \(Bundle.main.bundleURL.path) -> \(status)")
    return status == noErr ? 0 : 1
}

/// このバンドルの入力ソースを、有効にしていないものも含めて列挙する
func printStatus() -> Int32 {
    guard let bundleID = Bundle.main.bundleIdentifier else {
        print("バンドル ID が無い")
        return 1
    }
    let filter = [kTISPropertyBundleID as String: bundleID] as CFDictionary
    guard let list = TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource] else {
        print("入力ソース 0 件")
        return 1
    }
    func property(_ source: TISInputSource, _ key: CFString) -> Any? {
        guard let raw = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<AnyObject>.fromOpaque(raw).takeUnretainedValue()
    }
    print("入力ソース \(list.count) 件")
    for source in list {
        let id = property(source, kTISPropertyInputSourceID) as? String ?? "?"
        let enabled = (property(source, kTISPropertyInputSourceIsEnabled) as? Bool).map { "\($0)" } ?? "?"
        print("\(id)\tenabled=\(enabled)")
    }
    return 0
}

/// 組み立てたバンドルから綴りの表・語表・辞書を読み、1 文を変換して出す。読めなければ初期化の時点で止まる
func check() -> Int32 {
    let input = "kyouhagithubdekensaku"
    print("\(input)\t\(sharedEngine.live(input, leading: .start).map(\.text).joined())")
    return 0
}

switch CommandLine.arguments.dropFirst().first {
case "--register":
    exit(register())
case "--status":
    exit(printStatus())
case "--check":
    exit(check())
case "--version":
    print(Updater.build)
    exit(0)
case "--install":
    exit(Installer.run(interactive: false))
case "--uninstall":
    exit(Installer.uninstall(purge: CommandLine.arguments.contains("--purge")))
case "--bench":
    exit(Bench.run())
case "--snapshot":
    exit(Snapshot.write(to: CommandLine.arguments.dropFirst(2).first ?? "snapshots"))
default:
    // dmg から開かれたら、入力メソッドとして動く前に自分をインストールする
    if !Installer.isInstalled {
        exit(Installer.run(interactive: true))
    }
}

guard let connectionName = Bundle.main.infoDictionary?["InputMethodConnectionName"] as? String else {
    fatalError("Info.plist に InputMethodConnectionName が無い")
}
// IMKServer はプロセスに 1 つだけ作る。2 つあると Chromium 系のアプリに入力が届かない
let server = IMKServer(name: connectionName, bundleIdentifier: Bundle.main.bundleIdentifier)
// 候補の窓とモードの印もプロセスに 1 つ
let candidatePanel = CandidatePanel()
let modeBadge = ModeBadge()
// 入力ソースを 1 つにまとめていた版から入れ替えたとき、英数の入力ソースが有効になっていなければ有効にする
InputSourceRow.enableMissing()
// 綴りの表・語表・辞書の読み込みを、最初の打鍵より前に済ませる
_ = sharedEngine
// ユーザー辞書も先に読み、追加の SKK 辞書（SKK-JISYO.L など）は別のスレッドで読み始める
_ = sharedLexicon
// リリースの版で動いていれば、新しいリリースを確かめて、打っていないときに入れ替える
Updater.startAutoUpdate()
// 入れ替えた直後なら、どの版になったかを知らせる
Updater.reportUpdate()
NSApplication.shared.run()
