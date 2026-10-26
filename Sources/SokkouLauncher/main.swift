import Foundation

/// sokkou の .app の Contents/XPCServices に入れる XPC サービス。サンドボックスに入れない。
/// サンドボックスの中の sokkou は、入れ物の外に書くインストーラー（Contents/Helpers/sokkou-installer.app）を自分では起こせないので、ここに頼む。
/// XPC サービスは、それを入れている .app からしか呼べない。受けるのはインストーラーの決まった引数だけで、動かすのも同じ .app のインストーラーだけ
@objc protocol Launcher {
    func run(_ arguments: [String], wait: Bool, reply: @escaping @Sendable (Int32, String?) -> Void)
}

final class Service: NSObject, Launcher, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: Launcher.self)
        connection.exportedObject = self
        connection.resume()
        return true
    }

    /// このサービスを入れている sokkou の .app のインストーラー
    private var helper: URL {
        Bundle.main.bundleURL
            .deletingLastPathComponent() // XPCServices
            .deletingLastPathComponent() // Contents
            .appendingPathComponent("Helpers/sokkou-installer.app", isDirectory: true)
    }

    /// wait なら終わるまで待って終わりの状態を返す（端末からの --install など）。
    /// 待たないときは別のアプリとして起こす。入れ替えで sokkou とこのサービスが止められても、インストーラーは続く
    func run(_ arguments: [String], wait: Bool, reply: @escaping @Sendable (Int32, String?) -> Void) {
        guard Self.allowed(arguments) else {
            reply(2, "インストーラーに渡せない引数: \(arguments)")
            return
        }
        let process = Process()
        if wait {
            process.executableURL = helper.appendingPathComponent("Contents/MacOS/sokkou-installer")
            process.arguments = arguments
            // インストーラーが止める sokkou から、頼んできた sokkou（端末から動かした --install）を除く
            var environment = ProcessInfo.processInfo.environment
            environment["SOKKOU_SPARE_PID"] = String(NSXPCConnection.current()?.processIdentifier ?? 0)
            process.environment = environment
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["-n", "-g", helper.path, "--args"] + arguments
        }
        do {
            try process.run()
        } catch {
            reply(1, error.localizedDescription)
            return
        }
        process.waitUntilExit()
        reply(process.terminationStatus, nil)
    }

    /// インストーラーの使い方（SokkouInstaller/main.swift）にある引数だけを通す
    static func allowed(_ arguments: [String]) -> Bool {
        guard let command = arguments.first, ["--install", "--update", "--uninstall"].contains(command) else { return false }
        var rest = arguments.dropFirst()[...]
        while let flag = rest.popFirst() {
            switch flag {
            case "--interactive", "--quiet", "--rollback", "--purge":
                continue
            case "--pr":
                guard let number = rest.popFirst(), !number.isEmpty, number.allSatisfy(\.isASCII), Int(number) != nil else { return false }
            case "--reason":
                guard rest.popFirst() != nil else { return false }
            default:
                return false
            }
        }
        return true
    }
}

let service = Service()
let listener = NSXPCListener.service()
listener.delegate = service
listener.resume()
