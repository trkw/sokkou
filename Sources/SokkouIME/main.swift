import Carbon
import Cocoa
import InputMethodKit
import SokkouCore
import SokkouEngine

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

/// 変換エンジンはプロセスに 1 つだけ持つ。辞書と語表の読み込みが重いので、入力欄ごとに作らない
let sharedEngine: TugimeEngine = {
    do {
        return try TugimeEngine()
    } catch {
        fatalError("sokkou を初期化できない: \(error)")
    }
}()

/// 覚えた候補は ~/Library/Application Support/sokkou/learning.json に置く
let sharedLearning: FileLearning = {
    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    return FileLearning(url: support.appendingPathComponent("sokkou/learning.json"))
}()

switch CommandLine.arguments.dropFirst().first {
case "--register":
    exit(register())
case "--status":
    exit(printStatus())
case "--check":
    exit(check())
default:
    break
}

guard let connectionName = Bundle.main.infoDictionary?["InputMethodConnectionName"] as? String else {
    fatalError("Info.plist に InputMethodConnectionName が無い")
}
// IMKServer はプロセスに 1 つだけ作る。2 つあると Chromium 系のアプリに入力が届かない
let server = IMKServer(name: connectionName, bundleIdentifier: Bundle.main.bundleIdentifier)
// 候補の窓とモードの印もプロセスに 1 つ
let candidatePanel = CandidatePanel()
let modeBadge = ModeBadge()
// 綴りの表・語表・辞書の読み込みを、最初の打鍵より前に済ませる
_ = sharedEngine
NSApplication.shared.run()
