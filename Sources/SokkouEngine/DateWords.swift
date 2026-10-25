import Foundation

/// きょう・いま などの読みに、今日の日付や今の時刻を候補として足す（Meltype と同じ動き。コードは使っていない）。
/// 読み全体がその語の文節だけに出し、候補の一覧の後ろ（辞書の候補・かなの後）に置く
public struct DateWords: Sendable {
    private let now: @Sendable () -> Date
    private let calendar: Calendar

    public init(now: @escaping @Sendable () -> Date = { Date() }, timeZone: TimeZone = .current) {
        self.now = now
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        self.calendar = calendar
    }

    /// 日付の読みと、今日から何日ずらすか
    static let dayOffsets: [String: Int] = ["おととい": -2, "きのう": -1, "きょう": 0, "あした": 1, "あす": 1, "あさって": 2]
    /// 今の時刻の読み
    static let nowReadings: Set<String> = ["いま", "なう"]

    private static let weekdays = ["日", "月", "火", "水", "木", "金", "土"]

    public func candidates(for reading: String) -> [String] {
        let date = now()
        if let offset = Self.dayOffsets[reading], let day = calendar.date(byAdding: .day, value: offset, to: date) {
            return dates(day)
        }
        if Self.nowReadings.contains(reading) {
            return times(date)
        }
        return []
    }

    /// 2026年10月25日 / 2026年10月25日(日) / 10月25日(日) / 2026/10/25 / 2026-10-25 / 日曜日
    private func dates(_ date: Date) -> [String] {
        let d = calendar.dateComponents([.year, .month, .day, .weekday], from: date)
        let (year, month, day) = (d.year!, d.month!, d.day!)
        let weekday = Self.weekdays[d.weekday! - 1]
        return [
            "\(year)年\(month)月\(day)日",
            "\(year)年\(month)月\(day)日(\(weekday))",
            "\(month)月\(day)日(\(weekday))",
            "\(year)/\(pad(month))/\(pad(day))",
            "\(year)-\(pad(month))-\(pad(day))",
            "\(weekday)曜日",
        ]
    }

    /// 17:22 / 17時22分 / 午後5時22分（正午は午後0時） / 2026年10月25日(日) 17時22分 / 10月25日(日) 17時22分 / 2026/10/25 17:22
    private func times(_ date: Date) -> [String] {
        let d = calendar.dateComponents([.year, .month, .day, .weekday, .hour, .minute], from: date)
        let (year, month, day, hour, minute) = (d.year!, d.month!, d.day!, d.hour!, d.minute!)
        let weekday = Self.weekdays[d.weekday! - 1]
        return [
            "\(hour):\(pad(minute))",
            "\(hour)時\(minute)分",
            "\(hour < 12 ? "午前" : "午後")\(hour % 12)時\(minute)分",
            "\(year)年\(month)月\(day)日(\(weekday)) \(hour)時\(minute)分",
            "\(month)月\(day)日(\(weekday)) \(hour)時\(minute)分",
            "\(year)/\(pad(month))/\(pad(day)) \(hour):\(pad(minute))",
        ]
    }

    private func pad(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }
}
