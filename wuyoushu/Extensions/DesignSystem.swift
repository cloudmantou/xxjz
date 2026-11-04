import SwiftUI
import UIKit

// MARK: - Design System
//
// 风格："纸与墨" —— 温暖的纸色底、墨色文字、一种克制的主色。
// 原则：
// 1. 层级靠留白和字重，而不是阴影和渐变。
// 2. 数字是主角：统一使用圆体 + 等宽数字，金额对齐不跳动。
// 3. 每个可点元素都有按压反馈（缩放 + 轻触感），状态切换用弹簧动画。

enum DS {
    // MARK: Spacing (4pt grid)
    enum Space {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let s: CGFloat = 12
        static let m: CGFloat = 16
        static let l: CGFloat = 20
        static let xl: CGFloat = 28
        static let xxl: CGFloat = 40
    }

    // MARK: Motion
    enum Motion {
        static let snappy = Animation.spring(response: 0.32, dampingFraction: 0.82)
        static let smooth = Animation.spring(response: 0.45, dampingFraction: 0.86)
        static let press = Animation.spring(response: 0.22, dampingFraction: 0.7)
    }
}

// MARK: - Typography

extension Font {
    /// 页面大标题
    static let dsLargeTitle = Font.system(size: 30, weight: .bold, design: .rounded)
    /// 区块标题
    static let dsTitle = Font.system(size: 20, weight: .semibold, design: .rounded)
    /// 卡片标题
    static let dsHeadline = Font.system(size: 15, weight: .semibold, design: .rounded)
    /// 正文
    static let dsBody = Font.system(size: 15, weight: .regular)
    /// 辅助说明
    static let dsCaption = Font.system(size: 12, weight: .medium)
    /// 全大写小标签
    static let dsOverline = Font.system(size: 11, weight: .semibold, design: .rounded)

    /// 金额数字（等宽，避免跳动）
    static func dsAmount(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        Font.system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }
}

// MARK: - Haptics

enum Haptics {
    private static let lightGenerator = UIImpactFeedbackGenerator(style: .light)
    private static let softGenerator = UIImpactFeedbackGenerator(style: .soft)
    private static let selectionGenerator = UISelectionFeedbackGenerator()
    private static let notificationGenerator = UINotificationFeedbackGenerator()

    static func tap() {
        lightGenerator.impactOccurred(intensity: 0.7)
    }

    static func soft() {
        softGenerator.impactOccurred()
    }

    static func selection() {
        selectionGenerator.selectionChanged()
    }

    static func success() {
        notificationGenerator.notificationOccurred(.success)
    }

    static func warning() {
        notificationGenerator.notificationOccurred(.warning)
    }
}

// MARK: - Button Styles

/// 通用按压反馈：轻微缩放 + 降低不透明度
struct PressableButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.96
    var haptic: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(DS.Motion.press, value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { pressed in
                if pressed && haptic { Haptics.tap() }
            }
    }
}

/// 主操作按钮：实心主色胶囊
struct PrimaryButtonStyle: ButtonStyle {
    var fullWidth: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 24)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: 50)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.brandPrimary500)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(DS.Motion.press, value: configuration.isPressed)
    }
}

/// 次要按钮：浅色底胶囊
struct SecondaryButtonStyle: ButtonStyle {
    var fullWidth: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .foregroundStyle(Color.textPrimary)
            .padding(.horizontal, 24)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: 50)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.appCardMutedBackground)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(DS.Motion.press, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableButtonStyle {
    static var pressable: PressableButtonStyle { PressableButtonStyle() }
    static var pressableHaptic: PressableButtonStyle { PressableButtonStyle(haptic: true) }
}

// MARK: - Icon Button

/// 圆形图标按钮（导航箭头、工具栏等）
struct DSIconButton: View {
    let systemName: String
    var size: CGFloat = 36
    var tint: Color = .textPrimary
    var background: Color = .appCardMutedBackground
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: size * 0.36, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: size, height: size)
                .background(Circle().fill(background))
                .contentShape(Circle())
        }
        .buttonStyle(PressableButtonStyle(scale: 0.9))
    }
}

// MARK: - Segmented Control

/// 统一的分段选择器：滑块跟随 + 触感反馈
struct DSSegmentedControl<Item: Hashable>: View {
    let items: [Item]
    @Binding var selection: Item
    let title: (Item) -> String
    var height: CGFloat = 38

    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items, id: \.self) { item in
                let isSelected = item == selection
                Button {
                    guard item != selection else { return }
                    Haptics.selection()
                    withAnimation(DS.Motion.snappy) {
                        selection = item
                    }
                } label: {
                    Text(title(item))
                        .font(.system(size: 14, weight: isSelected ? .semibold : .medium, design: .rounded))
                        .foregroundStyle(isSelected ? Color.textPrimary : Color.textSecondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background {
                            if isSelected {
                                Capsule(style: .continuous)
                                    .fill(Color.surfaceElevated)
                                    .shadow(color: Color.black.opacity(0.08), radius: 4, y: 1)
                                    .matchedGeometryEffect(id: "segment", in: namespace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(3)
        .frame(height: height)
        .background(
            Capsule(style: .continuous)
                .fill(Color.appCardMutedBackground)
        )
    }
}

// MARK: - Small Pieces

/// 小号全大写标签（区块上方的说明文字）
struct DSOverline: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.dsOverline)
            .foregroundStyle(Color.textTertiary)
    }
}

/// 金额的「标签 + 数字」组合
struct DSMetric: View {
    let title: String
    let value: String
    var valueColor: Color = .textPrimary
    var size: CGFloat = 20
    var alignment: HorizontalAlignment = .leading

    var body: some View {
        VStack(alignment: alignment, spacing: 4) {
            Text(title)
                .font(.dsCaption)
                .foregroundStyle(Color.textSecondary)
            Text(value)
                .font(.dsAmount(size))
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }
}

// MARK: - Counting Number

/// 数字滚动动画：金额变化时从旧值平滑过渡到新值
struct CountingNumberModifier: AnimatableModifier {
    var value: Double
    let format: (Double) -> String

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    func body(content: Content) -> some View {
        Text(format(value))
    }
}

struct CountingCurrencyText: View {
    let value: Double
    var font: Font = .dsAmount(20)
    var color: Color = .textPrimary
    var compact: Bool = false

    @State private var displayValue: Double = 0

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .modifier(CountingNumberModifier(value: displayValue, format: { v in
                compact ? v.compactCurrencyString : v.currencyString
            }))
            .font(font)
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .onAppear {
                withAnimation(.easeOut(duration: 0.6)) { displayValue = value }
            }
            .onChange(of: value) { newValue in
                withAnimation(.easeOut(duration: 0.45)) { displayValue = newValue }
            }
    }
}
