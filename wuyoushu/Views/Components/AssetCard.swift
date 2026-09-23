import SwiftUI

struct AssetCard: View {
    let asset: AssetItem
    var onFavoriteToggle: (() -> Void)? = nil

    private var visualDescriptor: ProductVisualDescriptor {
        ProductVisualResolver.assetVisual(name: asset.name, category: asset.category)
    }

    var body: some View {
        HStack(spacing: 14) {
            // ── 缩略图区域 ──
            thumbnailView

            // ── 信息区域 ──
            VStack(alignment: .leading, spacing: 6) {
                // 标题行
                HStack(alignment: .center) {
                    Text(asset.name)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)

                    if asset.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.warmYellow)
                    }

                    Spacer()

                    StatusBadge(status: asset.status)
                }

                // 分类标签
                Text(L10n.tr(asset.category))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color(.tertiarySystemGroupedBackground))
                    .clipShape(Capsule())

                // 数值行
                HStack(alignment: .lastTextBaseline) {
                    Text(asset.currentValue.currencyString)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.warmTeal)
                        .monospacedDigit()

                    Spacer()

                    HStack(spacing: 3) {
                        Image(systemName: "clock")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                        Text(asset.dailyCost.dailyCostString)
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .cardStyle(variant: .default, radius: CardRadius.medium)
    }

    @ViewBuilder
    private var thumbnailView: some View {
        if let imageData = asset.imageData, let uiImage = UIImage(data: imageData) {
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

struct StatusBadge: View {
    let status: AssetStatus

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(dotColor)
                .frame(width: 5, height: 5)
            Text(status.localizedTitle)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(foregroundColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(backgroundColor)
        .clipShape(Capsule())
    }

    private var dotColor: Color {
        switch status {
        case .active: return .profitGreen
        case .sold: return .warmTeal
        case .disposed: return .gray
        }
    }

    private var backgroundColor: Color {
        switch status {
        case .active: return .profitGreen.opacity(0.12)
        case .sold: return .warmTeal.opacity(0.12)
        case .disposed: return .gray.opacity(0.12)
        }
    }

    private var foregroundColor: Color {
        switch status {
        case .active: return .profitGreen
        case .sold: return .warmTeal
        case .disposed: return .gray
        }
    }
}

#Preview {
    VStack(spacing: 12) {
        AssetCard(asset: AssetItem(
            name: "iPhone 15 Pro Max",
            category: "电子产品",
            purchasePrice: 9999,
            currentValue: 8000,
            status: .active
        ))
        AssetCard(asset: AssetItem(
            name: "MacBook Pro",
            category: "电子产品",
            purchasePrice: 19999,
            currentValue: 15000,
            status: .sold
        ))
    }
    .padding()
    .background(Color.appPageBackground)
}
