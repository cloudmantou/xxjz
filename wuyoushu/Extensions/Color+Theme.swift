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
    static let profitGreen = adaptive(light: "2F9E6B", dark: "4CC38A")
    static let warningOrange = adaptive(light: "D9A030", dark: "E8B44E")
    static let lossRed = adaptive(light: "D9534F", dark: "F07A73")

    // MARK: - Text Colors
    static let textPrimary = adaptive(light: "1C1C1A", dark: "F1F1EC")
    static let textSecondary = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(Color(hex: "A3A69F"))
            : UIColor(Color(hex: "6B6A63"))
    })
    static let textTertiary = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(Color(hex: "6F736D"))
            : UIColor(Color(hex: "A3A199"))
    })
    static let textOnPrimary = Color.white

    // MARK: - Background Colors
    static let cardBackground = Color.appCardBackground
    static let secondaryCardBackground = Color.appCardMutedBackground

    // MARK: - Brand / Theme Tokens
    static let brandPrimary400 = adaptive(light: "3FA68A", dark: "5CC4A6")
    static let brandPrimary500 = adaptive(light: "1F8A70", dark: "3DB491")
    static let brandPrimary600 = adaptive(light: "17705B", dark: "2E9C7C")

    static let backgroundBase = adaptive(light: "F5F4EF", dark: "0F1110")
    static let backgroundSecondary = adaptive(light: "EDECE6", dark: "1C1F1D")
    static let backgroundTinted = adaptive(light: "E6F1EC", dark: "14211D")

    static let cardBase = adaptive(light: "FFFFFF", dark: "181B19")
    static let cardElevated = adaptive(light: "FFFFFF", dark: "232724")

    static let borderSoft = adaptive(light: "E8E6DE", dark: "262A27")
    static let borderMedium = adaptive(light: "D8D6CC", dark: "323733")

    static let semanticSuccess = adaptive(light: "2F9E6B", dark: "4CC38A")
    static let semanticWarning = adaptive(light: "D9A030", dark: "E8B44E")
    static let semanticDanger = adaptive(light: "D9534F", dark: "F07A73")
    static let semanticInfo = adaptive(light: "4A86D9", dark: "6FA3EE")

    // MARK: - Bookkeeping Warm Theme (兼容旧命名)
    static let warmTeal = brandPrimary500
    static let warmTealDark = brandPrimary600
    static let warmTealLight = backgroundTinted
    static let warmYellow = semanticWarning
    static let warmYellowDark = adaptive(light: "D6A94F", dark: "C89E4B")
    static let warmMint = adaptive(light: "EEF6F2", dark: "17231F")
    static let warmMintDark = adaptive(light: "CBE6DB", dark: "1F5E4E")
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
    static let heroGradientTop = adaptive(light: "23977B", dark: "1E6B59")
    static let heroGradientBottom = adaptive(light: "17705B", dark: "154A3E")
    static let heroSurface = brandPrimary500
    static let homeHeroGradientTop = adaptive(light: "23977B", dark: "1E6B59")
    static let homeHeroGradientBottom = adaptive(light: "17705B", dark: "154A3E")

    // MARK: - App Surface Colors
    static let appPageBackground = backgroundBase
    static let appCardBackground = cardBase
    static let appCardMutedBackground = backgroundSecondary
    static let statisticsCardBackground = cardBase
    static let surfaceElevated = cardElevated
    static let surfacePrimary = appPageBackground
    static let appTabBarBackground = adaptive(light: "FAFAF7", dark: "1A201D")
    static let appTabBarBorder = adaptive(light: "E4E7E1", dark: "2C3430")
    static let appPillBackground = adaptive(light: "EDEFEA", dark: "222A26")

    // MARK: - Income / Expense Semantic
    static let expenseRed = semanticDanger
    static let incomeGreen = semanticSuccess
    static let neutralBlue = semanticInfo

    // MARK: - Receipt Paper
    static let receiptPaper = Color(hex: "FBFAF4")
    static let receiptText = Color(hex: "161616")

    // MARK: - Chart Colors (low saturation)
    static let chartColors: [Color] = [
        Color(hex: "1F8A70"),
        Color(hex: "E3A33B"),
        Color(hex: "D96C5F"),
        Color(hex: "4A86D9"),
        Color(hex: "8E6CC9"),
        Color(hex: "6BB27A"),
        Color(hex: "5FA9A6"),
        Color(hex: "B8B2A6")
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
