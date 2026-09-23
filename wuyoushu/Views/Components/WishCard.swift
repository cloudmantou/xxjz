import SwiftUI

struct WishCard: View {
    let item: WishlistItem

    private var visualDescriptor: ProductVisualDescriptor {
        ProductVisualResolver.wishVisual(name: item.name, category: item.category)
    }

    var body: some View {
        HStack(spacing: Constants.UI.spacing) {
            // Thumbnail
            if let imageData = item.imageData, let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: Constants.UI.thumbnailSize, height: Constants.UI.thumbnailSize)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        LinearGradient(
                            colors: visualDescriptor.gradientColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: Constants.UI.thumbnailSize, height: Constants.UI.thumbnailSize)
                    .overlay {
                        Image(systemName: visualDescriptor.symbolName)
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(visualDescriptor.tintColor)
                    }
            }

            // Info
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(item.name)
                        .font(.headline)
                        .lineLimit(1)

                    Spacer()

                    PriorityBadge(priority: Int(item.priority))
                }

                Text(L10n.tr(item.category))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack {
                    if let lowestPrice = item.currentLowestPrice {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("最低价")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(lowestPrice.currencyString)
                                .font(.callout)
                                .fontWeight(.semibold)
                                .foregroundStyle(lowestPrice <= item.targetPrice ? Color.profitGreen : Color.warningOrange)
                        }
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text("目标价")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(item.targetPrice.currencyString)
                            .font(.callout)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.warmCoral)
                        if item.targetDailyCost > 0 {
                            Text(item.targetDailyCost.dailyCostString)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
            }
        }
        .padding(Constants.UI.cardPadding)
        .cardStyle()
        .opacity(item.isPurchased ? 0.6 : 1)
    }
}

struct PriorityBadge: View {
    let priority: Int

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<5) { index in
                Circle()
                    .fill(index < priority ? Color.warningOrange : Color.gray.opacity(0.3))
                    .frame(width: 6, height: 6)
            }
        }
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
