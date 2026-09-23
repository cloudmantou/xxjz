import SwiftUI

extension Color {
    // MARK: - Adaptive Color Helper
    /// 根据暗/亮模式自动切换颜色
    static func adaptive(light: String, dark: String) -> Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(Color(hex: dark))
                : UIColor(Color(hex: light))
        })
    }

    // MARK: - Primary Colors
    static let primaryBlue = Color(hex: "007AFF")
    static let secondaryPurple = Color(hex: "5856D6")

    // MARK: - Semantic Colors
    static let profitGreen = adaptive(light: "58B67A", dark: "69C88A")
    static let warningOrange = adaptive(light: "E6B85C", dark: "E2B865")
    static let lossRed = adaptive(light: "E97777", dark: "F08A8A")

    // MARK: - Text Colors
    static let textPrimary = adaptive(light: "161616", dark: "F2F4EF")
    static let textSecondary = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(Color(hex: "A7AEA5"))
            : UIColor(Color(hex: "6F736C"))
    })
    static let textTertiary = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(Color(hex: "7E857D"))
            : UIColor(Color(hex: "A2A79F"))
    })
    static let textOnPrimary = Color.white

    // MARK: - Background Colors
    static let cardBackground = Color.appCardBackground
    static let secondaryCardBackground = Color.appCardMutedBackground

    // MARK: - Brand / Theme Tokens
    static let brandPrimary400 = adaptive(light: "6AC8C0", dark: "74D3CB")
    static let brandPrimary500 = adaptive(light: "4CB7AE", dark: "58C1B8")
    static let brandPrimary600 = adaptive(light: "3AA79D", dark: "43AEA5")

    static let backgroundBase = adaptive(light: "F7F7F3", dark: "111513")
    static let backgroundSecondary = adaptive(light: "F1F2EC", dark: "171C19")
    static let backgroundTinted = adaptive(light: "EEF6F4", dark: "15201D")

    static let cardBase = adaptive(light: "FBFAF4", dark: "1B211E")
    static let cardElevated = adaptive(light: "FFFFFF", dark: "222925")

    static let borderSoft = adaptive(light: "E7E8E1", dark: "2A312D")
    static let borderMedium = adaptive(light: "D9DDD4", dark: "323A35")

    static let semanticSuccess = adaptive(light: "58B67A", dark: "69C88A")
    static let semanticWarning = adaptive(light: "E6B85C", dark: "E2B865")
    static let semanticDanger = adaptive(light: "E97777", dark: "F08A8A")
    static let semanticInfo = adaptive(light: "6DA9E4", dark: "7DB7F0")

    // MARK: - Bookkeeping Warm Theme (兼容旧命名)
    static let warmTeal = brandPrimary500
    static let warmTealDark = brandPrimary600
    static let warmTealLight = backgroundTinted
    static let warmYellow = semanticWarning
    static let warmYellowDark = adaptive(light: "D6A94F", dark: "C89E4B")
    static let warmMint = adaptive(light: "F1FAF8", dark: "1A2623")
    static let warmMintDark = adaptive(light: "CDEFEA", dark: "236F69")
    static let warmCoral = semanticDanger

    // MARK: - Pastel Category Backgrounds (暗/亮自适应)
    static let pastelYellow = adaptive(light: "FFF8EC", dark: "2B261C")
    static let pastelPink = adaptive(light: "FFF5F5", dark: "2A2021")
    static let pastelGreen = adaptive(light: "F1FAF8", dark: "1A2623")
    static let pastelBlue = adaptive(light: "F3F8FD", dark: "1C242C")
    static let pastelPurple = adaptive(light: "F5EEFF", dark: "261F2C")
    static let pastelOrange = adaptive(light: "FFF4DD", dark: "2B241A")
    static let pastelTeal = adaptive(light: "EEF6F4", dark: "15201D")
    static let pastelRed = adaptive(light: "FFF0F4", dark: "2A2021")
    static let pastelCyan = adaptive(light: "EEF7FD", dark: "1C242C")
    static let pastelGray = adaptive(light: "F1F2EC", dark: "171C19")

    static let categoryPastelColors: [Color] = [
        .pastelYellow, .pastelBlue, .pastelPink, .pastelGreen,
        .pastelPurple, .pastelOrange, .pastelTeal, .pastelRed,
        .pastelCyan, .pastelGray
    ]

    static func categoryPastelColor(at index: Int) -> Color {
        categoryPastelColors[index % categoryPastelColors.count]
    }

    // MARK: - Hero Gradient Colors
    static let heroGradientTop = adaptive(light: "67D6CD", dark: "2D8E87")
    static let heroGradientBottom = adaptive(light: "43B7AF", dark: "236F69")
    static let heroSurface = brandPrimary500
    static let homeHeroGradientTop = adaptive(light: "67D6CD", dark: "2D8E87")
    static let homeHeroGradientBottom = adaptive(light: "43B7AF", dark: "236F69")

    // MARK: - App Surface Colors
    static let appPageBackground = backgroundBase
    static let appCardBackground = cardBase
    static let appCardMutedBackground = backgroundSecondary
    static let statisticsCardBackground = cardBase
    static let surfaceElevated = cardElevated
    static let surfacePrimary = appPageBackground

    // MARK: - Income / Expense Semantic
    static let expenseRed = semanticDanger
    static let incomeGreen = semanticSuccess
    static let neutralBlue = semanticInfo

    // MARK: - Receipt Paper
    static let receiptPaper = Color(hex: "FBFAF4")
    static let receiptText = Color(hex: "161616")

    // MARK: - Chart Colors (low saturation)
    static let chartColors: [Color] = [
        Color(hex: "49B6AE"),
        Color(hex: "F0C96A"),
        Color(hex: "EE8D8D"),
        Color(hex: "67A9E6"),
        Color(hex: "AF7CE1"),
        Color(hex: "7BC47F"),
        Color(hex: "8EC3B0"),
        Color(hex: "C9C3B8")
    ]

    static func chartColor(at index: Int) -> Color {
        chartColors[index % chartColors.count]
    }

    // MARK: - Hex Initializer
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
