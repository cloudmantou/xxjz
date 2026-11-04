import SwiftUI

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var buttonTitle: String? = nil
    var action: (() -> Void)? = nil

    @State private var appeared = false

    var body: some View {
        VStack(spacing: DS.Space.l) {
            Image(systemName: icon)
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(Color.brandPrimary500)
                .frame(width: 72, height: 72)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color.brandPrimary500.opacity(0.10))
                )
                .scaleEffect(appeared ? 1 : 0.85)
                .opacity(appeared ? 1 : 0)

            VStack(spacing: DS.Space.xs) {
                Text(title)
                    .font(.dsTitle)
                    .foregroundStyle(Color.textPrimary)

                Text(message)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 8)

            if let buttonTitle = buttonTitle, let action = action {
                Button {
                    Haptics.tap()
                    action()
                } label: {
                    Label(buttonTitle, systemImage: "plus")
                }
                .buttonStyle(PrimaryButtonStyle(fullWidth: false))
                .padding(.top, DS.Space.xxs)
                .opacity(appeared ? 1 : 0)
            }
        }
        .padding(DS.Space.xxl)
        .frame(maxWidth: .infinity)
        .onAppear {
            withAnimation(DS.Motion.smooth.delay(0.05)) { appeared = true }
        }
    }
}

#Preview {
    EmptyStateView(
        icon: "shippingbox",
        title: "暂无资产",
        message: "添加您的第一笔资产，开始追踪您的财务状况",
        buttonTitle: "马上添加",
        action: {}
    )
    .background(Color.appPageBackground)
}
