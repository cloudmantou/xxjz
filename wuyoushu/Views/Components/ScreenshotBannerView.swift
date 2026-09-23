import SwiftUI

struct ScreenshotBannerView: View {
    let amount: Double
    let categoryKey: String?
    let isIncome: Bool
    let onTap: () -> Void
    let onDismiss: () -> Void

    @State private var offsetY: CGFloat = -100
    @State private var opacity: Double = 0

    private var displayText: String {
        if isIncome {
            return "检测到收入 ¥\(String(format: "%.2f", amount))"
        }
        return "检测到支出 ¥\(String(format: "%.2f", amount))"
    }

    private var categoryName: String? {
        guard let key = categoryKey else { return nil }
        let map: [String: String] = [
            "dining": "餐饮", "transport": "交通", "shopping": "购物",
            "entertainment": "娱乐", "housing": "居住", "medical": "医疗",
            "education": "教育", "social": "人情", "transfer": "转账", "other": "其他"
        ]
        return map[key]
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: isIncome ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundColor(isIncome ? .green : .warmCoral)

                VStack(alignment: .leading, spacing: 2) {
                    Text(displayText)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)
                    if let cat = categoryName {
                        Text("分类：\(cat)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.appCardMutedBackground)
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .offset(y: offsetY)
        .opacity(opacity)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                offsetY = 0
                opacity = 1
            }
            // Auto-dismiss after 5 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                dismiss()
            }
        }
    }

    private func dismiss() {
        withAnimation(.easeOut(duration: 0.3)) {
            offsetY = -100
            opacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            onDismiss()
        }
    }
}
