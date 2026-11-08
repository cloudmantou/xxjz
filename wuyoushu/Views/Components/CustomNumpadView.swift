import SwiftUI

struct CustomNumpadView: View {
    @Binding var amountString: String
    var isMinimalMode: Bool = false
    var onConfirm: () -> Void
    var onDateToggle: (() -> Void)?
    @Environment(\.colorScheme) private var colorScheme

    private let fullColumns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    private let minimalColumns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    // MARK: - Brand Adaptive Colors
    private var digitBgColor: Color {
        Color.appCardBackground
    }
    private var digitFgColor: Color {
        Color.primary
    }
    private var actionBgColor: Color {
        Color.warmTeal.opacity(0.12)
    }
    private var actionFgColor: Color {
        Color.warmTeal
    }
    private var deleteFgColor: Color {
        Color.secondary
    }

    var body: some View {
        VStack(spacing: 10) {
            if isMinimalMode {
                minimalNumpad
            } else {
                fullNumpad
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.appCardBackground)
    }

    private var fullNumpad: some View {
        LazyVGrid(columns: fullColumns, spacing: 10) {
            numpadButton("1")
            numpadButton("2")
            numpadButton("3")
            deleteButton

            numpadButton("4")
            numpadButton("5")
            numpadButton("6")
            plusButton

            numpadButton("7")
            numpadButton("8")
            numpadButton("9")
            dateButton

            decimalButton
            numpadButton("0")
            doubleZeroButton
            confirmButton
        }
    }

    private var minimalNumpad: some View {
        VStack(spacing: 10) {
            LazyVGrid(columns: minimalColumns, spacing: 10) {
                numpadButton("1")
                numpadButton("2")
                numpadButton("3")

                numpadButton("4")
                numpadButton("5")
                numpadButton("6")

                numpadButton("7")
                numpadButton("8")
                numpadButton("9")

                decimalButton
                numpadButton("0")
                deleteButton
            }

            confirmButton
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Button Builders

    private func numpadButton(_ value: String) -> some View {
        Button(action: {
            hapticFeedback()
            appendDigit(value)
        }) {
            Text(value)
                .font(.system(size: 20, weight: .medium, design: .rounded))
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(digitBgColor)
                .cornerRadius(14)
        }
        .foregroundColor(digitFgColor)
    }

    private var deleteButton: some View {
        Button(action: {
            hapticFeedback()
            if !amountString.isEmpty {
                amountString.removeLast()
            }
        }) {
            Image(systemName: "delete.left.fill")
                .font(.system(size: 16))
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(digitBgColor)
                .cornerRadius(14)
        }
        .foregroundColor(deleteFgColor)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.6).onEnded { _ in
                amountString = ""
            }
        )
    }

    private var plusButton: some View {
        Button(action: {
            hapticFeedback()
            if !amountString.contains("+") && !amountString.isEmpty {
                amountString += "+"
            }
        }) {
            Text("+")
                .font(.system(size: 22, weight: .medium, design: .rounded))
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(actionBgColor)
                .cornerRadius(14)
        }
        .foregroundColor(actionFgColor)
    }

    private var dateButton: some View {
        Button(action: {
            hapticFeedback()
            onDateToggle?()
        }) {
            Image(systemName: "calendar")
                .font(.system(size: 15))
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(actionBgColor)
                .cornerRadius(14)
        }
        .foregroundColor(actionFgColor)
    }

    private var decimalButton: some View {
        Button(action: {
            hapticFeedback()
            if !amountString.contains(".") && !amountString.isEmpty {
                amountString += "."
            }
        }) {
            Text(".")
                .font(.system(size: 22, weight: .medium, design: .rounded))
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(digitBgColor)
                .cornerRadius(14)
        }
        .foregroundColor(digitFgColor)
    }

    private var doubleZeroButton: some View {
        Button(action: {
            hapticFeedback()
            appendDigit("00")
        }) {
            Text("00")
                .font(.system(size: 20, weight: .medium, design: .rounded))
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(digitBgColor)
                .cornerRadius(14)
        }
        .foregroundColor(digitFgColor)
    }

    private var confirmButton: some View {
        Button(action: {
            hapticFeedback()
            onConfirm()
        }) {
            Text("记账")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(
                    LinearGradient(
                        colors: [Color.heroGradientTop, Color.heroGradientBottom],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .cornerRadius(14)
                .shadow(color: Color.warmTeal.opacity(0.3), radius: 6, y: 2)
        }
        .foregroundColor(.white)
    }

    // MARK: - Helpers

    private func appendDigit(_ digit: String) {
        let newString = amountString + digit
        let cleaned = newString.replacingOccurrences(of: "+", with: "")
        let parts = cleaned.components(separatedBy: ".")
        if let intPart = parts.first, intPart.count > Constants.Bookkeeping.maxAmountDigits {
            return
        }
        if parts.count > 1, parts[1].count > 2 {
            return
        }
        amountString = newString
    }

    private func hapticFeedback() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }
}
