import SwiftUI

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    var trend: Double? = nil
    var trendTitle: String? = nil
    var iconColor: Color = Color.warmTeal

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                // 图标背景容器
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(iconColor.opacity(0.13))
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(iconColor)
                }
                .frame(width: 36, height: 36)

                Spacer()

                if let trend = trend {
                    TrendBadge(value: trend)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            if let trendTitle = trendTitle {
                Text(trendTitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .cardStyle(variant: .default, radius: CardRadius.medium)
    }
}

struct TrendBadge: View {
    let value: Double

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: value >= 0 ? "arrow.up.right" : "arrow.down.right")
                .font(.caption2)

            Text(value.percentString)
                .font(.caption2)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(backgroundColor)
        .foregroundStyle(foregroundColor)
        .clipShape(Capsule())
    }

    private var backgroundColor: Color {
        value >= 0 ? Color.profitGreen.opacity(0.13) : Color.lossRed.opacity(0.13)
    }

    private var foregroundColor: Color {
        value >= 0 ? Color.profitGreen : Color.lossRed
    }
}

#Preview {
    HStack {
        StatCard(
            title: "总资产",
            value: "¥125,999",
            icon: "creditcard.fill",
            trend: 5.2,
            trendTitle: "较上月"
        )

        StatCard(
            title: "日均成本",
            value: "¥28.5",
            icon: "chart.line.downtrend.xyaxis"
        )
    }
    .padding()
    .background(Color.appPageBackground)
}
