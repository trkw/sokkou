/// 未確定の文字列の 1 区切り。入力メソッドは style ごとに下線や強調を変えて表示する
public struct MarkedSegment: Sendable, Equatable {
    public enum Style: Sendable, Equatable {
        /// 自動変換した日本語（実線）
        case japanese
        /// 英語のまま残す区間（点線）
        case english
        /// `C-g` で打ったままのかなと英字に戻した表示
        case raw
        /// 文節選択の文節
        case clause
        /// 文節選択で選んでいる文節
        case focused
        /// ▽ ▼（自分で区切った読みと、その変換）
        case manual
        /// ▽ の読みに続く、登録した読みの残り。薄く見せ、Tab で採る
        case suggestion
    }

    public var text: String
    public var style: Style

    public init(text: String, style: Style) {
        self.text = text
        self.style = style
    }
}

/// 候補の窓に出す 1 ページ
public struct CandidateWindow: Sendable, Equatable {
    /// 窓の見出しに出す読み
    public var reading: String
    /// このページの候補
    public var items: [String]
    /// 候補を選ぶキー。items と同じ数
    public var labels: [Character]
    /// このページの中で強調している候補の位置
    public var highlighted: Int
    /// 0 から数えたページ
    public var page: Int
    public var pageCount: Int
    /// 候補の注釈（SKK 辞書の ; のあと）。items と同じ数か、注釈が 1 つも無ければ空
    public var annotations: [String?]

    public init(
        reading: String, items: [String], labels: [Character], highlighted: Int, page: Int, pageCount: Int, annotations: [String?] = []
    ) {
        self.reading = reading
        self.items = items
        self.labels = labels
        self.highlighted = highlighted
        self.page = page
        self.pageCount = pageCount
        self.annotations = annotations
    }

    /// index 番目の候補の注釈
    public func annotation(at index: Int) -> String? {
        annotations.indices.contains(index) ? annotations[index] : nil
    }
}

/// 入力メソッドが今表示するもの
public struct Presentation: Sendable, Equatable {
    public var segments: [MarkedSegment]
    public var window: CandidateWindow?

    public init(segments: [MarkedSegment], window: CandidateWindow? = nil) {
        self.segments = segments
        self.window = window
    }

    public static let empty = Presentation(segments: [])

    public var text: String { segments.map(\.text).joined() }
}
