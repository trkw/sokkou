// swift-tools-version: 6.2

import PackageDescription

// tugime の変換は azooKey と C++ の llama.cpp を使うので、TugimeCore の型を見るターゲットは C++ の相互運用を有効にする
let cxx: SwiftSetting = .interoperabilityMode(.Cxx)

let package = Package(
    name: "sokkou",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SokkouCore", targets: ["SokkouCore"]),
        .executable(name: "sokkou", targets: ["SokkouIME"]),
    ],
    dependencies: [
        // tugime はまだ版を切っていないので revision で固定する
        .package(url: "https://github.com/miyaoka/tugime", revision: "040aefe4a716ea084660bc5605725d91295b1dd4"),
    ],
    targets: [
        // キー操作の状態と表示。変換エンジンに頼らないので Linux でもテストできる
        .target(name: "SokkouCore"),
        // tugime の日英判定と azooKey の変換を SokkouCore につなぐ
        .target(
            name: "SokkouEngine",
            dependencies: ["SokkouCore", .product(name: "TugimeCore", package: "tugime")],
            // sokkou の綴りの表。tugime の表に zi shi chi tsu fu などの綴りを足したもの
            resources: [.copy("Resources")],
            swiftSettings: [cxx]
        ),
        .executableTarget(
            name: "SokkouIME",
            dependencies: ["SokkouCore", "SokkouEngine"],
            // 入力メソッドの呼び出しはすべてメインスレッドで届くので、既定の隔離をメインアクターにする（SE-0466）
            swiftSettings: [.defaultIsolation(MainActor.self), cxx],
            linkerSettings: [.linkedFramework("InputMethodKit")]
        ),
        .testTarget(name: "SokkouCoreTests", dependencies: ["SokkouCore"]),
        // 本物の綴りの表と azooKey の辞書を通すテスト。macOS でだけ組み立てられる
        .testTarget(
            name: "SokkouEngineTests",
            dependencies: ["SokkouCore", "SokkouEngine", .product(name: "TugimeCore", package: "tugime")],
            // テストは 1 つの本物の変換エンジンを共有するので、同時に使わないようメインアクターで動かす
            swiftSettings: [.defaultIsolation(MainActor.self), cxx]
        ),
    ]
)
