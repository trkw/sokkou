import Foundation
import Security

/// つまづきの記録を、利用者の非公開のリポジトリ（既定は trkw/sokkou-stumbles）に 1 時間ごとに送る。
/// token は利用者が設定の窓に貼り、Keychain に入れる。アプリには埋め込まない。
/// 送るのは前に送ったあとの記録だけで、1 回ごとに stumbles/ の下に新しいファイルを作る
enum StumbleUpload {
    /// 送る間隔。1 時間ごとのタイマーが少しずれても飛ばさないよう、1 時間より短くする
    private static let interval: TimeInterval = 50 * 60
    private static var timer: Timer?
    private static var sending = false

    static var repository: String {
        get { UserDefaults.standard.string(forKey: "stumbleRepository") ?? "trkw/sokkou-stumbles" }
        set { UserDefaults.standard.set(newValue, forKey: "stumbleRepository") }
    }

    /// 最後に送った記録の時刻。これより後の記録を次に送る
    private static var sentThrough: Date? {
        get { UserDefaults.standard.object(forKey: "stumblesSentThrough") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "stumblesSentThrough") }
    }

    /// sentThrough と同じ時刻（秒まで）の記録のうち、送った数。同じ秒にあとから残した記録を取りこぼさない
    private static var sentAtThrough: Int {
        get { UserDefaults.standard.integer(forKey: "stumblesSentAtThrough") }
        set { UserDefaults.standard.set(newValue, forKey: "stumblesSentAtThrough") }
    }

    /// 最後に送ろうとした時刻
    private static var lastAttempt: Date? {
        get { UserDefaults.standard.object(forKey: "stumblesLastAttempt") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "stumblesLastAttempt") }
    }

    /// 設定の窓に出す、最後に送った結果
    static var status: String? {
        get { UserDefaults.standard.string(forKey: "stumblesUploadStatus") }
        set { UserDefaults.standard.set(newValue, forKey: "stumblesUploadStatus") }
    }

    /// どの Mac から送ったかをファイルの名前で分ける。マシン名は出さず、最初に作った乱数を使う
    private static var machine: String {
        if let id = UserDefaults.standard.string(forKey: "stumblesMachine") { return id }
        let id = String(UUID().uuidString.prefix(8)).lowercased()
        UserDefaults.standard.set(id, forKey: "stumblesMachine")
        return id
    }

    /// 1 時間ごとに、記録がオンで token があり、前に送ってから 50 分たっていれば送る
    static func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 60 * 60, repeats: true) { _ in
            MainActor.assumeIsolated { sendIfDue() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { sendIfDue() }
    }

    private static func sendIfDue() {
        guard Settings.recordsStumbles, token != nil else { return }
        if let lastAttempt, Date().timeIntervalSince(lastAttempt) < interval { return }
        send { _ in }
    }

    /// 前に送ったあとの記録を送る。終わったら結果の言葉を渡す
    static func send(_ done: @escaping @MainActor (String) -> Void) {
        guard !sending else { return }
        guard let token else {
            done("token がありません")
            return
        }
        let all = StumbleLog.records()
        var skip = sentAtThrough
        let records = all.filter { record in
            guard let through = sentThrough else { return true }
            if record.at == through, skip > 0 {
                skip -= 1
                return false
            }
            return record.at >= through
        }
        lastAttempt = Date()
        guard let last = records.last else {
            finish("送る記録はありませんでした", done)
            return
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .sortedKeys
        var body = Data()
        for record in records {
            guard let line = try? encoder.encode(record) else { continue }
            body.append(line)
            body.append(0x0A)
        }
        let stampFormat = DateFormatter()
        stampFormat.locale = Locale(identifier: "en_US_POSIX")
        stampFormat.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = stampFormat.string(from: Date())
        let path = "stumbles/\(stamp)-\(machine).jsonl"
        guard let url = URL(string: "https://api.github.com/repos/\(repository)/contents/\(path)") else {
            finish("リポジトリの名前が読めません", done)
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        let payload: [String: String] = [
            "message": "\(records.count) 件のつまづき（\(Updater.build)）",
            "content": body.base64EncodedString(),
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        sending = true
        let count = records.count
        let sameTime = all.filter { $0.at == last.at }.count
        Task {
            let result: String
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                if (200..<300).contains(code) {
                    sentThrough = last.at
                    sentAtThrough = sameTime
                    result = "\(count) 件を送りました"
                } else if code == 401 || code == 403 || code == 404 {
                    result = "送れませんでした（\(code)）。token とリポジトリの名前を確かめてください"
                } else {
                    result = "送れませんでした（\(code)）"
                }
            } catch {
                result = "送れませんでした（\(error.localizedDescription)）"
            }
            sending = false
            finish(result, done)
        }
    }

    private static func finish(_ result: String, _ done: @MainActor (String) -> Void) {
        let format = DateFormatter()
        format.dateFormat = "M/d HH:mm"
        status = "\(format.string(from: Date())) \(result)"
        done(status ?? result)
    }

    // MARK: Keychain

    private static let service = "sokkou.stumbles.github"

    static var token: String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// token を Keychain に入れる。空なら消す
    static func setToken(_ value: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        SecItemDelete(base as CFDictionary)
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var item = base
        item[kSecValueData as String] = Data(trimmed.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }
}
