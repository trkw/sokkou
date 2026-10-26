// swift-tools-version: 6.2

import PackageDescription

// azooKey の Zenzai は C++ の llama.cpp を使うので、SokkouConverter の型を見るターゲットは C++ の相互運用を有効にする
let cxx: SwiftSetting = .interoperabilityMode(.Cxx)

let package = Package(
    name: "sokkou",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SokkouCore", targets: ["SokkouCore"]),
        .executable(name: "sokkou", targets: ["SokkouIME"]),
        .executable(name: "sokkou-installer", targets: ["SokkouInstaller"]),
    ],
    dependencies: [
        // 1.0 まではマイナー版でも破壊的変更があるため revision で固定する
        .package(
            url: "https://github.com/azooKey/AzooKeyKanaKanjiConverter",
            revision: "04ce2ec3afe2bd6f92fcae1dc15a2357d332c27a",
            traits: ["Zenzai"]
        ),
    ],
    targets: [
        // キー操作の状態と表示。変換エンジンに頼らないので Linux でもテストできる
        .target(name: "SokkouCore"),
        // 日英の区切りと azooKey のかな漢字変換。llama.cpp（import llama）は azooKey が trait Zenzai で載せる binaryTarget を使う
        .target(
            name: "SokkouConverter",
            dependencies: [
                .product(name: "KanaKanjiConverterModuleWithDefaultDictionary", package: "AzooKeyKanaKanjiConverter"),
            ],
            // 英語の語表と語の頻度
            resources: [.copy("Resources")],
            swiftSettings: [cxx]
        ),
        // SokkouConverter を SokkouCore の Engine につなぐ
        .target(
            name: "SokkouEngine",
            dependencies: ["SokkouCore", "SokkouConverter"],
            // sokkou の綴りの表（訓令式とヘボン式の綴りを読む）
            resources: [.copy("Resources")],
            swiftSettings: [cxx]
        ),
        .executableTarget(
            name: "SokkouIME",
            dependencies: ["SokkouCore", "SokkouEngine", "SokkouConverter"],
            // 入力メソッドの呼び出しはすべてメインスレッドで届くので、既定の隔離をメインアクターにする（SE-0466）
            swiftSettings: [.defaultIsolation(MainActor.self), cxx],
            linkerSettings: [.linkedFramework("InputMethodKit")]
        ),
        // sokkou を ~/Library/Input Methods に入れる・更新する・取り除く別のアプリ。sokkou の .app の Contents/Helpers に入れる。
        // 本体を App Sandbox に入れても入れ替えられるよう、本体と別のプロセスで動かす
        .executableTarget(
            name: "SokkouInstaller",
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(name: "SokkouCoreTests", dependencies: ["SokkouCore"]),
        // 本物の綴りの表と azooKey の辞書を通すテスト。macOS でだけ組み立てられる
        .testTarget(
            name: "SokkouEngineTests",
            dependencies: ["SokkouCore", "SokkouEngine", "SokkouConverter"],
            // テストは 1 つの本物の変換エンジンを共有するので、同時に使わないようメインアクターで動かす
            swiftSettings: [.defaultIsolation(MainActor.self), cxx]
        ),
    ]
)
