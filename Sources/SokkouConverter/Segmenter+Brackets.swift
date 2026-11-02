import Foundation

/// 句読点の形と、丸括弧の組
extension Segmenter {
    /// 開き丸括弧ごとの、同じ形の閉じ丸括弧
    static let closingBracket: [Character: Character] = ["(": ")", "（": "）"]

    /// 句読点 c の区間の形。直前の区間が英語なら nil（打ったまま英語の区間に含める）、日本語なら日本語の記号にする。
    /// 閉じ丸括弧は、opened の最後の開き丸括弧（入れ子を数えて組になるもの）と同じ形にし、opened から外す。全角なら直前が英語でも区間にし、
    /// 半角なら直前が日本語でも半角の区間にする。組が無ければほかの句読点と同じ。
    /// 開き丸括弧は、決めた形を opened に積む
    static func punctuationMark(_ c: Character, opened: inout [Character], previousIsEnglish: Bool) -> String? {
        if closingBracket.values.contains(c), let opener = opened.popLast() {
            if opener == "(" { return previousIsEnglish ? nil : ")" }
            return "）"
        }
        if closingBracket[c] != nil { opened.append(previousIsEnglish ? c : "（") }
        return previousIsEnglish ? nil : punctuation[c]
    }

    /// text の中で閉じていない開き丸括弧。外側から順に並べる
    static func unclosedOpeners(in text: String) -> [Character] {
        var opened: [Character] = []
        for c in text {
            if closingBracket[c] != nil {
                opened.append(c)
            } else if closingBracket.values.contains(c), !opened.isEmpty {
                opened.removeLast()
            }
        }
        return opened
    }
}
