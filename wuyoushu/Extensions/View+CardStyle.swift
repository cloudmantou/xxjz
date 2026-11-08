import SwiftUI

// MARK: - Card Radius Tokens
enum CardRadius {
    static let small: CGFloat = 10
    static let medium: CGFloat = 16
    static let large: CGFloat = 20
    static let hero: CGFloat = 24
}

// MARK: - Card Style Variants
enum CardVariant {
    case `default`      // 普通卡片
    case elevated       // 强调卡片，立体阴影
    case flat           // 无阴影平铺
    case tinted(Color)  // 主题色微底纹
}

extension View {
    // 默认卡片
    func cardStyle() -> some View {
        cardStyle(variant: .default, radius: CardRadius.medium)
    }

    func cardStyle(variant: CardVariant = .default, radius: CGFloat = CardRadius.medium) -> some View {
        let fill: AnyShapeStyle
        let primaryShadowOpacity: Double
        let primaryShadowRadius: CGFloat
        let primaryShadowY: CGFloat
        let secondaryShadowOpacity: Double
        let secondaryShadowRadius: CGFloat
        let secondaryShadowY: CGFloat
        let borderColor: Color
        let borderWidth: CGFloat

        switch variant {
        case .default:
            fill = AnyShapeStyle(Color.appCardBackground)
            primaryShadowOpacity = 0.04
            primaryShadowRadius = 14
            primaryShadowY = 4
            secondaryShadowOpacity = 0.02
            secondaryShadowRadius = 3
            secondaryShadowY = 1
            borderColor = .borderSoft
            borderWidth = 0.7
        case .elevated:
            fill = AnyShapeStyle(Color.surfaceElevated)
            primaryShadowOpacity = 0.08
            primaryShadowRadius = 24
            primaryShadowY = 8
            secondaryShadowOpacity = 0.03
            secondaryShadowRadius = 4
            secondaryShadowY = 2
            borderColor = .borderMedium
            borderWidth = 0.8
        case .flat:
            fill = AnyShapeStyle(Color.appCardMutedBackground)
            primaryShadowOpacity = 0
            primaryShadowRadius = 0
            primaryShadowY = 0
            secondaryShadowOpacity = 0
            secondaryShadowRadius = 0
            secondaryShadowY = 0
            borderColor = .borderSoft
            borderWidth = 0.6
        case .tinted(let color):
            fill = AnyShapeStyle(color.opacity(0.10))
            primaryShadowOpacity = 0.03
            primaryShadowRadius = 10
            primaryShadowY = 3
            secondaryShadowOpacity = 0.01
            secondaryShadowRadius = 2
            secondaryShadowY = 1
            borderColor = color.opacity(0.20)
            borderWidth = 0.7
        }

        return self.background(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(fill)
                .overlay(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .stroke(borderColor, lineWidth: borderWidth)
                )
                .shadow(color: Color.black.opacity(primaryShadowOpacity), radius: primaryShadowRadius, x: 0, y: primaryShadowY)
                .shadow(color: Color.black.opacity(secondaryShadowOpacity), radius: secondaryShadowRadius, x: 0, y: secondaryShadowY)
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
                        .stroke(
                            LinearGradient(
                                colors: [Color.white.opacity(0.35), Color.white.opacity(0.08)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.8
                        )
                )
                .shadow(color: Color.black.opacity(0.06), radius: 16, x: 0, y: 6)
                .shadow(color: Color.black.opacity(0.02), radius: 3, x: 0, y: 1)
        )
    }
}

// MARK: - Tactile Press Button Style
struct CardPressButtonStyle: ButtonStyle {
    var scaleAmount: CGFloat = 0.98

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scaleAmount : 1.0)
            .opacity(configuration.isPressed ? 0.92 : 1.0)
            .animation(.spring(response: 0.26, dampingFraction: 0.78), value: configuration.isPressed)
    }
}

extension View {
    func tactilePressFeedback(scale: CGFloat = 0.97) -> some View {
        self.buttonStyle(CardPressButtonStyle(scaleAmount: scale))
    }
}
