import AppKit

/// sokkou の入れ替えを受け持つアプリ。sokkou の .app の Contents/Helpers に入れて配る。
/// sokkou 本体は App Sandbox に入れて ~/Library/Input Methods に書けなくするので、入れる・更新する・取り除くはここでする。
///
///   --install [--interactive]          この .app を入れている sokkou を入れる。interactive なら結果を窓で知らせる（dmg から開いたとき）
///   --update [--pr N | --rollback] [--quiet] [--reason 文]
///                                      最新のリリース、PR の版、取っておいた前の版に入れ替える
///   --uninstall [--purge]              入力ソースから外し、入れた版と取っておいた前の版を消す。purge なら覚えた候補と設定も消す
let arguments = Array(CommandLine.arguments.dropFirst())

func value(after flag: String) -> String? {
    guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
    return arguments[index + 1]
}

switch arguments.first {
case "--install":
    exit(Installer.run(interactive: arguments.contains("--interactive")))
case "--update":
    exit(Update.run(
        pr: value(after: "--pr").flatMap(Int.init),
        rollback: arguments.contains("--rollback"),
        quiet: arguments.contains("--quiet"),
        reason: value(after: "--reason")
    ))
case "--uninstall":
    exit(Installer.uninstall(purge: arguments.contains("--purge")))
default:
    print("使い方: --install [--interactive] / --update [--pr N | --rollback] [--quiet] / --uninstall [--purge]")
    exit(2)
}
