import SwiftUI

struct WishCard: View {
    let item: WishlistItem

    private var visualDescriptor: ProductVisualDescriptor {
        ProductVisualResolver.wishVisual(name: item.name, category: item.category)
    }

    var body: some View {
        HStack(spacing: 14) {
            // Thumbnail
            thumbnailView

            // Info
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center) {
                    Text(item.name)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)

                    Spacer()

                    PriorityBadge(priority: Int(item.priority))
                }

                // 分类与购买状态标签
                HStack(spacing: 6) {
                    Text(L10n.tr(item.category))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(Color.appPillBackground)
                        .clipShape(Capsule())

                    if item.isPurchased {
                        Text("已购")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.profitGreen)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.profitGreen.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }

                // 数值对比行
                HStack(alignment: .lastTextBaseline) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("目标价")
                            .font(.system(size: 10, design: .rounded))
                            .foregroundStyle(.secondary)
                        Text(item.targetPrice.currencyString)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.warmCoral)
                            .monospacedDigit()
                    }

                    Spacer()

                    if let lowestPrice = item.currentLowestPrice {
                        VStack(alignment: .trailing, spacing: 1) {
                            HStack(spacing: 2) {
                                if lowestPrice <= item.targetPrice {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 9))
                                }
                                Text(lowestPrice <= item.targetPrice ? "已达目标" : "最低价")
                                    .font(.system(size: 10, design: .rounded))
                            }
                            .foregroundStyle(lowestPrice <= item.targetPrice ? Color.profitGreen : Color.warningOrange)

                            Text(lowestPrice.currencyString)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(lowestPrice <= item.targetPrice ? Color.profitGreen : Color.warningOrange)
                                .monospacedDigit()
                        }
                    } else if item.targetDailyCost > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "clock")
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                            Text(item.targetDailyCost.dailyCostString)
                                .font(.system(size: 11, design: .rounded))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .cardStyle(variant: .default, radius: CardRadius.medium)
        .opacity(item.isPurchased ? 0.72 : 1)
    }

    @ViewBuilder
    private var thumbnailView: some View {
        if let imageData = item.imageData, let uiImage = UIImage(data: imageData) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: 58, height: 58)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: visualDescriptor.gradientColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: visualDescriptor.symbolName)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(visualDescriptor.tintColor)
            }
            .frame(width: 58, height: 58)
        }
    }
}

struct PriorityBadge: View {
    let priority: Int

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "star.fill")
                .font(.system(size: 8.5))
                .foregroundStyle(Color.warmYellow)

            Text("P\(priority)")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(Color.warmYellowDark)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Color.pastelYellow)
        .clipShape(Capsule())
    }
}

#Preview {
    VStack {
        WishCard(item: WishlistItem(
            name: "iPhone 16 Pro",
            category: "电子产品",
            targetPrice: 8000,
            priority: 5
        ))

        WishCard(item: WishlistItem(
            name: "AirPods Pro",
            category: "数码配件",
            targetPrice: 1500,
            priority: 3
        ))
    }
    .padding()
}
