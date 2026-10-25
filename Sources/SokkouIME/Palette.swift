import AppKit

/// 色の組。設定の「色」で選ぶ。地・板・墨・控えめな字・罫・差し色と差し色の上の字を、明るい外観と暗い外観の 2 つずつ持つ
nonisolated enum Palette: String, CaseIterable, Identifiable, Sendable {
    /// 紙の地に墨、差し色は朱。はじめの色
    case shu
    /// 色を使わず、墨の濃淡だけ
    case shizuka
    /// 生成りの地に藍
    case ai
    /// 白磁の地に青磁
    case seiji
    /// 淡い青の地に空色
    case sora
    /// 若草
    case wakakusa
    /// 桜
    case sakura
    /// 山吹
    case yamabuki
    /// 藤
    case fuji
    /// 墨の地に金。暗い外観がいちばん映える
    case sumi
    /// 白と黒をはっきり分ける。字がいちばん読みやすい
    case contrast
    /// macOS の外観とアクセントカラーに合わせる
    case system

    var id: Self { self }

    var title: String {
        switch self {
        case .shu: "紙と朱"
        case .shizuka: "しずか"
        case .ai: "生成りと藍"
        case .seiji: "白磁と青磁"
        case .sora: "空"
        case .wakakusa: "若草"
        case .sakura: "桜"
        case .yamabuki: "山吹"
        case .fuji: "藤"
        case .sumi: "墨と金"
        case .contrast: "くっきり"
        case .system: "macOS に合わせる"
        }
    }

    /// この色の組で、この外観での役目の色
    func color(_ role: ThemeRole, dark: Bool) -> NSColor {
        guard let tones else { return role.system }
        let tone = dark ? tones.dark : tones.light
        let hex: UInt32 = switch role {
        case .ground: tone.ground
        case .surface: tone.surface
        case .ink: tone.ink
        case .quiet: tone.quiet
        case .rule: tone.rule
        case .accent: tone.accent
        case .onAccent: tone.onAccent
        }
        return ThemeRole.srgb(hex)
    }

    /// 1 つの外観での色。16 進の sRGB
    struct Tone: Sendable {
        let ground: UInt32
        let surface: UInt32
        let ink: UInt32
        let quiet: UInt32
        let rule: UInt32
        let accent: UInt32
        let onAccent: UInt32
    }

    /// 明るい外観と暗い外観の色。macOS に合わせるときは nil で、システムの色を使う
    var tones: (light: Tone, dark: Tone)? {
        switch self {
        case .shu: (
            Tone(ground: 0xF4F2EC, surface: 0xFCFBF8, ink: 0x1E1C19, quiet: 0x6B675F, rule: 0xE5E1D7, accent: 0xC23B12, onAccent: 0xFFFFFF),
            Tone(ground: 0x141311, surface: 0x22201D, ink: 0xEEEAE2, quiet: 0xA29D93, rule: 0x34312C, accent: 0xF0663C, onAccent: 0x1A0D07)
        )
        case .shizuka: (
            Tone(ground: 0xF5F5F4, surface: 0xFFFFFF, ink: 0x222222, quiet: 0x6E6E6E, rule: 0xE6E6E4, accent: 0x222222, onAccent: 0xFFFFFF),
            Tone(ground: 0x161616, surface: 0x222222, ink: 0xECECEC, quiet: 0xA0A0A0, rule: 0x333333, accent: 0xECECEC, onAccent: 0x161616)
        )
        case .ai: (
            Tone(ground: 0xF4F2EE, surface: 0xFCFBF9, ink: 0x1D2030, quiet: 0x666A78, rule: 0xE3E1DB, accent: 0x2E4C8F, onAccent: 0xFFFFFF),
            Tone(ground: 0x12141A, surface: 0x1D2029, ink: 0xE9EBF1, quiet: 0x9DA2B2, rule: 0x2F3340, accent: 0x8EA8E8, onAccent: 0x0E1220)
        )
        case .seiji: (
            Tone(ground: 0xF3F5F3, surface: 0xFBFCFB, ink: 0x1C2221, quiet: 0x657270, rule: 0xE0E5E2, accent: 0x2F7A6E, onAccent: 0xFFFFFF),
            Tone(ground: 0x111615, surface: 0x1B2120, ink: 0xE6ECEA, quiet: 0x98A6A3, rule: 0x2C3533, accent: 0x6CC2B2, onAccent: 0x0B1715)
        )
        case .sora: (
            Tone(ground: 0xF1F5FA, surface: 0xFFFFFF, ink: 0x172033, quiet: 0x5F6B80, rule: 0xDFE6EF, accent: 0x2F6BEA, onAccent: 0xFFFFFF),
            Tone(ground: 0x0F141C, surface: 0x1A2130, ink: 0xE8EDF6, quiet: 0x98A3B8, rule: 0x2A3345, accent: 0x7FA8FF, onAccent: 0x0B1222)
        )
        case .wakakusa: (
            Tone(ground: 0xF3F4EE, surface: 0xFBFBF7, ink: 0x1F2219, quiet: 0x676C5C, rule: 0xE2E4D9, accent: 0x55822B, onAccent: 0xFFFFFF),
            Tone(ground: 0x131510, surface: 0x1E211A, ink: 0xE8EBE0, quiet: 0xA0A693, rule: 0x30352A, accent: 0x9CCB6A, onAccent: 0x10180A)
        )
        case .sakura: (
            Tone(ground: 0xF7F2F2, surface: 0xFDFAFA, ink: 0x2A1F22, quiet: 0x7A6A6E, rule: 0xEBE0E2, accent: 0xC2456E, onAccent: 0xFFFFFF),
            Tone(ground: 0x171213, surface: 0x241D1F, ink: 0xF0E6E8, quiet: 0xAE9DA2, rule: 0x372C2F, accent: 0xF08AAB, onAccent: 0x22101A)
        )
        case .yamabuki: (
            Tone(ground: 0xF6F3EA, surface: 0xFDFBF5, ink: 0x221E14, quiet: 0x6F6858, rule: 0xE7E1D1, accent: 0xA8730A, onAccent: 0xFFFFFF),
            Tone(ground: 0x15130E, surface: 0x221F18, ink: 0xEFEADD, quiet: 0xA8A08D, rule: 0x36312A, accent: 0xE8B54A, onAccent: 0x1E1504)
        )
        case .fuji: (
            Tone(ground: 0xF4F2F6, surface: 0xFCFBFD, ink: 0x221F2B, quiet: 0x6D6878, rule: 0xE4E0EA, accent: 0x7253B0, onAccent: 0xFFFFFF),
            Tone(ground: 0x141218, surface: 0x201D26, ink: 0xECE9F2, quiet: 0xA39EB0, rule: 0x332F3C, accent: 0xB39CF0, onAccent: 0x150E24)
        )
        case .sumi: (
            Tone(ground: 0xEFEDE8, surface: 0xF9F8F5, ink: 0x141413, quiet: 0x5E5C57, rule: 0xDEDBD3, accent: 0x8F7128, onAccent: 0xFFFFFF),
            Tone(ground: 0x0E0E0D, surface: 0x1A1A18, ink: 0xF2EFE8, quiet: 0x9B988F, rule: 0x2C2B28, accent: 0xD4B36A, onAccent: 0x171204)
        )
        case .contrast: (
            Tone(ground: 0xFFFFFF, surface: 0xFFFFFF, ink: 0x000000, quiet: 0x3A3A3A, rule: 0xA8A8A8, accent: 0x0040C0, onAccent: 0xFFFFFF),
            Tone(ground: 0x000000, surface: 0x0A0A0A, ink: 0xFFFFFF, quiet: 0xD0D0D0, rule: 0x6A6A6A, accent: 0x70AAFF, onAccent: 0x000000)
        )
        case .system: nil
        }
    }

    // 色は描くたびに引くので、設定は覚えておいて UserDefaults を毎回読まない。読み書きはメインスレッドでだけする
    nonisolated(unsafe) private static var stored: Palette?
    nonisolated(unsafe) private static var storedAccent: UInt32??

    static var current: Palette {
        get {
            if let stored { return stored }
            let value = UserDefaults.standard.string(forKey: "palette").flatMap(Palette.init(rawValue:)) ?? .shu
            stored = value
            return value
        }
        set {
            stored = newValue
            UserDefaults.standard.set(newValue.rawValue, forKey: "palette")
        }
    }

    /// いまの色の組と差し色を 1 つの字にしたもの。変わったら絵を描き直す目印にする
    static var key: String {
        "\(current.rawValue)-\(customAccent.map { String($0, radix: 16) } ?? "")"
    }

    /// 自分で選んだ差し色。nil なら色の組の差し色を使う
    static var customAccent: UInt32? {
        get {
            if let storedAccent { return storedAccent }
            let value = (UserDefaults.standard.object(forKey: "customAccent") as? Int).map { UInt32(truncatingIfNeeded: $0) }
            storedAccent = .some(value)
            return value
        }
        set {
            storedAccent = .some(newValue)
            if let newValue {
                UserDefaults.standard.set(Int(newValue), forKey: "customAccent")
            } else {
                UserDefaults.standard.removeObject(forKey: "customAccent")
            }
        }
    }
}

/// Theme の色の役目
nonisolated enum ThemeRole: Sendable {
    case ground, surface, ink, quiet, rule, accent, onAccent

    /// いまの色の組とこの外観で、この役目の色
    func color(dark: Bool) -> NSColor {
        if self == .accent || self == .onAccent, let custom = Palette.customAccent {
            return Self.custom(custom, onAccent: self == .onAccent, dark: dark)
        }
        return Palette.current.color(self, dark: dark)
    }

    /// macOS の色。アクセントカラーはシステム設定で選んだ色になる
    var system: NSColor {
        switch self {
        case .ground: .windowBackgroundColor
        case .surface: .controlBackgroundColor
        case .ink: .labelColor
        case .quiet: .secondaryLabelColor
        case .rule: .separatorColor
        case .accent: .controlAccentColor
        case .onAccent: .white
        }
    }

    /// 自分で選んだ差し色。暗い外観では少し明るくし、上に載せる字は明るさで白か墨に決める
    static func custom(_ hex: UInt32, onAccent: Bool, dark: Bool) -> NSColor {
        var color = srgb(hex)
        if dark {
            color = color.blended(withFraction: 0.28, of: .white) ?? color
        }
        guard onAccent else { return color }
        return luminance(color) > 0.55 ? srgb(0x161616) : .white
    }

    private static func luminance(_ color: NSColor) -> CGFloat {
        guard let rgb = color.usingColorSpace(.sRGB) else { return 0 }
        return 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent + 0.0722 * rgb.blueComponent
    }

    static func srgb(_ hex: UInt32) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }

    /// NSColor を 16 進の sRGB にする。色を選ぶ窓で選んだ色を覚えるのに使う
    static func hex(_ color: NSColor) -> UInt32? {
        guard let rgb = color.usingColorSpace(.sRGB) else { return nil }
        func byte(_ value: CGFloat) -> UInt32 { UInt32((min(max(value, 0), 1) * 255).rounded()) }
        return byte(rgb.redComponent) << 16 | byte(rgb.greenComponent) << 8 | byte(rgb.blueComponent)
    }
}
