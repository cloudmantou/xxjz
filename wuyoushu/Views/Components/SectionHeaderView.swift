import SwiftUI

struct SectionHeaderView: View {
    let title: String
    var icon: String? = nil
    var subtitle: String? = nil
    var iconColor: Color = .warmTeal

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            if let icon = icon {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(iconColor.opacity(0.13))
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(iconColor)
                }
                .frame(width: 26, height: 26)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        SectionHeaderView(title: "最近记账")
        SectionHeaderView(title: "资产概览", icon: "chart.pie.fill")
        SectionHeaderView(title: "月度趋势", icon: "chart.line.uptrend.xyaxis", subtitle: "近6个月", iconColor: .profitGreen)
    }
    .padding()
    .background(Color.appPageBackground)
}
