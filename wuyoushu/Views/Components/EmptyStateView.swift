import SwiftUI

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var buttonTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 20) {
            // 渐变图标容器
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.heroGradientTop.opacity(0.18), Color.heroGradientBottom.opacity(0.25)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 88, height: 88)

                Image(systemName: icon)
                    .font(.system(size: 38, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.heroGradientTop, Color.heroGradientBottom],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            VStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)

                Text(message)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            if let buttonTitle = buttonTitle, let action = action {
                Button(action: action) {
                    Text(buttonTitle)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 13)
                        .background(
                            LinearGradient(
                                colors: [Color.heroGradientTop, Color.heroGradientBottom],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(Capsule())
                        .shadow(color: Color.warmTeal.opacity(0.18), radius: 20, y: 8)
                }
                .padding(.top, 4)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    EmptyStateView(
        icon: "creditcard.fill",
        title: "暂无资产",
        message: "添加您的第一笔资产，开始追踪您的财务状况",
        buttonTitle: "马上添加",
        action: {}
    )
    .background(Color.appPageBackground)
}
