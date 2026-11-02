import SwiftUI
import CoreData

struct AssetsStatisticsView: View {
    @Environment(\.bottomBarInset) private var bottomBarInset: CGFloat
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \AssetItem.updatedAt, ascending: false)],
        animation: .default
    )
    private var assets: FetchedResults<AssetItem>

    // MARK: - Summary Metrics

    private var visibleAssets: [AssetItem] {
        assets.filter { $0.status != .deleted }
    }

    private var activeAssets: [AssetItem] {
        visibleAssets.filter { $0.status == .active }
    }

    private var totalCurrentValue: Double {
        activeAssets.reduce(0) { $0 + $1.currentValue }
    }

    private var totalPurchaseValue: Double {
        activeAssets.reduce(0) { $0 + $1.purchasePrice }
    }

    private var totalDailyCost: Double {
        activeAssets.reduce(0) { $0 + $1.dailyCost }
    }

    private var activeCount: Int { activeAssets.count }
    private var soldCount: Int { visibleAssets.filter { $0.status == .sold }.count }
    private var disposedCount: Int { visibleAssets.filter { $0.status == .disposed }.count }

    // MARK: - Category Distribution

    private var categoryDistribution: [(name: String, value: Double, color: Color)] {
        var map: [String: Double] = [:]
        for asset in activeAssets {
            map[asset.category, default: 0] += asset.currentValue
        }
        let sorted = map.sorted { $0.value > $1.value }
        return sorted.enumerated().map { index, item in
            (name: L10n.tr(item.key), value: item.value, color: Color.chartColor(at: index))
        }
    }

    // MARK: - Value Trend (last 6 months)

    private var monthlyValueTrend: [(date: Date, value: Double)] {
        let calendar = Calendar.current
        let now = Date()

        // Build trend: for each month (current + 5 previous), compute implied total value
        // of all active assets as of that month
        // Approximation: linearly interpolate implied value between purchasePrice and currentValue
        // based on holding days
        return (0..<6).reversed().compactMap { offset -> (date: Date, value: Double)? in
            guard let monthDate = calendar.date(byAdding: .month, value: -offset, to: now) else { return nil }
            let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: monthDate)) ?? monthDate

            var totalImplied: Double = 0
            for asset in activeAssets {
                // Only include assets purchased by this month
                guard asset.purchaseDate <= startOfMonth else { continue }

                let totalDays = max(1, asset.holdingDays)
                let daysAsOfMonth = max(0, calendar.dateComponents([.day], from: asset.purchaseDate, to: startOfMonth).day ?? 0)
                let ratio = min(1.0, max(0, Double(daysAsOfMonth) / Double(totalDays)))
                let impliedValue = asset.purchasePrice + (asset.currentValue - asset.purchasePrice) * ratio
                totalImplied += impliedValue
            }

            return (startOfMonth, totalImplied)
        }
    }

    // MARK: - Top Assets by Daily Cost

    private var topAssetsByDailyCost: [(name: String, value: Double)] {
        activeAssets
            .sorted { $0.dailyCost > $1.dailyCost }
            .prefix(5)
            .map { (name: $0.name, value: $0.dailyCost) }
    }

    // MARK: - Status Distribution

    private var statusDistribution: [(name: String, value: Double, color: Color)] {
        [
            (name: AssetStatus.active.localizedTitle, value: Double(activeCount), color: Color.profitGreen),
            (name: AssetStatus.sold.localizedTitle, value: Double(soldCount), color: Color.warmTeal),
            (name: AssetStatus.disposed.localizedTitle, value: Double(disposedCount), color: Color.secondary.opacity(0.4))
        ]
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if visibleAssets.isEmpty {
                    emptyState
                } else {
                    summarySection
                    valueTrendSection
                    categorySection
                    topAssetsSection
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 12 + bottomBarInset)
        }
        .background(Color.appPageBackground)
        .navigationTitle("资产统计")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Summary Section

    private var summarySection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                StatCard(
                    title: "资产总价值",
                    value: totalCurrentValue.currencyString,
                    icon: "creditcard.fill",
                    iconColor: .warmTeal
                )

                StatCard(
                    title: "日均总成本",
                    value: totalDailyCost.dailyCostString,
                    icon: "chart.line.downtrend.xyaxis",
                    iconColor: .warmCoral
                )
            }

            HStack(spacing: 12) {
                StatCard(
                    title: "使用中",
                    value: "\(activeCount)",
                    icon: "checkmark.circle.fill",
                    iconColor: .profitGreen
                )

                StatCard(
                    title: "已卖出",
                    value: "\(soldCount)",
                    icon: "tag.fill",
                    iconColor: .warmTeal
                )

                StatCard(
                    title: "已报废",
                    value: "\(disposedCount)",
                    icon: "trash.fill",
                    iconColor: .secondary
                )
            }
        }
    }

    // MARK: - Value Trend Section

    private var valueTrendSection: some View {
        LineChartCard(
            title: "资产价值趋势",
            data: monthlyValueTrend
        )
    }

    // MARK: - Category Section

    private var categorySection: some View {
        PieChartCard(
            title: "类别分布",
            data: categoryDistribution
        )
    }

    // MARK: - Top Assets Section

    private var topAssetsSection: some View {
        BarChartCard(
            title: "日均成本 Top5",
            data: topAssetsByDailyCost
        )
    }

    // MARK: - Empty State

    private var emptyState: some View {
        EmptyStateView(
            icon: "chart.bar.xaxis",
            title: "暂无资产数据",
            message: "添加资产后，这里会展示统计信息",
            buttonTitle: nil,
            action: nil
        )
        .padding(.top, 60)
    }
}

#Preview {
    NavigationView {
        AssetsStatisticsView()
    }
    .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
