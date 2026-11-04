import SwiftUI

// MARK: - Card Radius Tokens
enum CardRadius {
    static let small: CGFloat = 12
    static let medium: CGFloat = 18
    static let large: CGFloat = 22
    static let hero: CGFloat = 24
}

// MARK: - Card Style Variants
enum CardVariant {
    case `default`      // 普通卡片
    case elevated       // 强调卡片，阴影更重
    case flat           // 无阴影，用于嵌套
    case tinted(Color)  // 带主题色背景
}

extension View {
    // 默认卡片（兼容原有调用）
    func cardStyle() -> some View {
        cardStyle(variant: .default, radius: CardRadius.medium)
    }

    func cardStyle(variant: CardVariant = .default, radius: CGFloat = CardRadius.medium) -> some View {
        let fill: AnyShapeStyle
        let shadowOpacity: Double
        let shadowRadius: CGFloat
        let shadowYOffset: CGFloat
        let borderColor: Color
        let borderWidth: CGFloat

        switch variant {
        case .default:
            fill = AnyShapeStyle(Color.appCardBackground)
            shadowOpacity = 0.035
            shadowRadius = 10
            shadowYOffset = 3
            borderColor = .borderSoft
            borderWidth = 0.8
        case .elevated:
            fill = AnyShapeStyle(Color.surfaceElevated)
            shadowOpacity = 0.08
            shadowRadius = 20
            shadowYOffset = 8
            borderColor = .borderSoft
            borderWidth = 0.9
        case .flat:
            fill = AnyShapeStyle(Color.appCardMutedBackground)
            shadowOpacity = 0
            shadowRadius = 0
            shadowYOffset = 0
            borderColor = .borderSoft
            borderWidth = 0.8
        case .tinted(let color):
            fill = AnyShapeStyle(color.opacity(0.10))
            shadowOpacity = 0
            shadowRadius = 0
            shadowYOffset = 0
            borderColor = color.opacity(0.22)
            borderWidth = 0.8
        }

        return self.background(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(fill)
                .overlay(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .stroke(borderColor, lineWidth: borderWidth)
                )
                .shadow(color: Color.black.opacity(shadowOpacity), radius: shadowRadius, x: 0, y: shadowYOffset)
        )
    }
}

// MARK: - Glassmorphism Style
extension View {
    func glassCard(radius: CGFloat = CardRadius.medium) -> some View {
        self.background(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                )
                .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 4)
        )
    }
}
