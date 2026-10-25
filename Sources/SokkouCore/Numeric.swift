import Foundation

/// SKK の数値変換。読みの数字を # にして辞書を引き（3がつ → #がつ）、候補の #0 #1 #2 #3 #8 を数字の書き方に置き換える
enum Numeric {
    /// 読みの中の数字の並びを # にした見出しと、その数字。数字が無ければ nil
    static func template(_ reading: String) -> (key: String, numbers: [String])? {
        var key = ""
        var numbers: [String] = []
        var number = ""
        for character in reading {
            if character.isASCII, character.isNumber {
                number.append(character)
                continue
            }
            if !number.isEmpty {
                key += "#"
                numbers.append(number)
                number = ""
            }
            key.append(character)
        }
        if !number.isEmpty {
            key += "#"
            numbers.append(number)
        }
        return numbers.isEmpty ? nil : (key, numbers)
    }

    /// 候補の #0〜#9 を、前から順に numbers の書き方にする。sokkou が書けない書き方（#5 大字、#9 棋譜）や、数が合わなければ nil
    static func expand(_ candidate: String, numbers: [String]) -> String? {
        var result = ""
        var index = 0
        var characters = candidate[...]
        while let character = characters.first {
            characters = characters.dropFirst()
            guard character == "#", let type = characters.first, let kind = type.wholeNumberValue else {
                result.append(character)
                continue
            }
            characters = characters.dropFirst()
            guard index < numbers.count, let text = format(numbers[index], kind) else { return nil }
            result += text
            index += 1
        }
        return index == numbers.count ? result : nil
    }

    /// 語の中の半角の数字を、ほかの書き方にした候補（3,000円 ３０００円 三千円 三〇〇〇円）
    static func variants(of word: String) -> [String] {
        guard let template = template(word) else { return [] }
        var words: [String] = []
        for kind in [8, 1, 3, 2] {
            let candidate = template.key.replacingOccurrences(of: "#", with: "#\(kind)")
            if let variant = expand(candidate, numbers: template.numbers), variant != word, !words.contains(variant) {
                words.append(variant)
            }
        }
        return words
    }

    private static let kanjiDigits: [Character] = ["〇", "一", "二", "三", "四", "五", "六", "七", "八", "九"]

    static func format(_ number: String, _ kind: Int) -> String? {
        switch kind {
        case 0: number
        case 1: String(number.compactMap { character -> Character? in
            guard let digit = character.wholeNumberValue, let scalar = Unicode.Scalar(UInt32(0xFF10 + digit)) else { return nil }
            return Character(scalar)
        })
        case 2: String(number.compactMap { $0.wholeNumberValue.map { kanjiDigits[$0] } })
        case 3: positional(number)
        case 8: grouped(number)
        default: nil
        }
    }

    /// 3 桁ごとに , で区切る
    private static func grouped(_ number: String) -> String {
        var result = ""
        for (offset, character) in number.enumerated() {
            if offset > 0, (number.count - offset) % 3 == 0 { result += "," }
            result.append(character)
        }
        return result
    }

    /// 位取りの漢数字（1024 → 千二十四）。十・百・千の前の一は書かない
    private static func positional(_ number: String) -> String {
        let digits = number.compactMap(\.wholeNumberValue).drop { $0 == 0 }
        guard !digits.isEmpty else { return "〇" }
        let units = ["", "十", "百", "千"]
        let groups = ["", "万", "億", "兆", "京"]
        var result = ""
        let count = digits.count
        for (offset, digit) in digits.enumerated() {
            let place = count - 1 - offset
            let unit = place % 4
            if digit != 0 {
                if digit != 1 || unit == 0 { result.append(kanjiDigits[digit]) }
                result += units[unit]
            }
            if unit == 0, place > 0 {
                // 4 桁の組がすべて 0 なら、万や億を書かない
                let start = max(offset - 3, 0)
                if digits[digits.startIndex + start...digits.startIndex + offset].contains(where: { $0 != 0 }) {
                    result += place / 4 < groups.count ? groups[place / 4] : ""
                }
            }
        }
        return result
    }
}
