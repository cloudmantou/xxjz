import SwiftUI
import CoreData
#if canImport(Charts)
import Charts
#endif

struct WishlistDetailView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var router: AppRouter
    @ObservedObject var item: WishlistItem
    @State private var showingEditSheet = false
    @State private var showingPlatformPriceSheet = false
    @State private var showingPriceHistorySheet = false
    @State private var isFetchingPriceInsight = false
    @State private var priceInsightMessage: String?

    var sortedPriceHistory: [WishlistPriceHistory] {
        item.priceHistories.sorted { $0.recordedAt > $1.recordedAt }
    }

    var priceChartData: [(date: Date, price: Double)] {
        item.priceHistories
            .sorted { $0.recordedAt < $1.recordedAt }
            .map { ($0.recordedAt, $0.price) }
    }

    var allTrackedPrices: [Double] {
        let historyPrices = item.priceHistories.map(\.price)
        let platformPrices = item.platformPrices.map(\.price)
        return (historyPrices + platformPrices).filter { $0 > 0 }
    }

    var lowestTrackedPrice: Double? { allTrackedPrices.min() }
    var highestTrackedPrice: Double? { allTrackedPrices.max() }
    var averageTrackedPrice: Double? {
        guard !allTrackedPrices.isEmpty else { return nil }
        return allTrackedPrices.reduce(0, +) / Double(allTrackedPrices.count)
    }

    var referenceCurrentPrice: Double? {
        item.currentLowestPrice ?? priceChartData.last?.price
    }

    var pricePercentile: Double? {
        guard
            let current = referenceCurrentPrice,
            let low = lowestTrackedPrice,
            let high = highestTrackedPrice,
            high > low
        else {
            return nil
        }
        let raw = (current - low) / (high - low)
        return min(max(raw, 0), 1)
    }

    var sortedPlatformPrices: [WishlistPlatformPrice] {
        item.platformPrices.sorted { $0.price < $1.price }
    }

    var platformPriceSpread: Double? {
        guard
            let lowest = sortedPlatformPrices.first?.price,
            let highest = sortedPlatformPrices.last?.price
        else {
            return nil
        }
        return highest - lowest
    }

    var aiSuggestionSummary: String {
        guard let lowest = item.currentLowestPrice else {
            return "先记录 1~2 个平台价格，AI 才能给到更可靠的购买建议。"
        }
        if lowest <= item.targetPrice {
            return "当前最低价已达到目标价，建议优先在低价平台下单，并记录成交价复盘。"
        }
        let gap = lowest - item.targetPrice
        return "当前最低价距离目标价还有 \(gap.currencyString)，建议继续观望并开启降价提醒。"
    }

    var body: some View {
        List {
            // Basic Info Section
            Section("基本信息") {
                DetailRow(label: "名称", value: item.name)
                DetailRow(label: "分类", value: L10n.tr(item.category))
                DetailRow(label: "目标价格", value: item.targetPrice.currencyString)
                if item.targetDailyCost > 0 {
                    DetailRow(label: "目标日均价格", value: item.targetDailyCost.dailyCostString)
                }
                DetailRow(label: "优先级", value: priorityText)

                HStack {
                    Text("当前最低价")
                    Spacer()
                    if let lowestPrice = item.currentLowestPrice {
                        Text(lowestPrice.currencyString)
                            .fontWeight(.semibold)
                            .foregroundStyle(lowestPrice <= item.targetPrice ? Color.profitGreen : Color.warningOrange)
                    } else {
                        Text("暂无")
                            .foregroundStyle(.secondary)
                    }
                }

                if let avgPrice = item.averagePrice {
                    DetailRow(label: "平均价格", value: avgPrice.currencyString)
                }
            }

            // Price Comparison
            if item.currentLowestPrice != nil {
                Section("价格对比") {
                    HStack {
                        Text("目标达成")
                        Spacer()
                        if let lowestPrice = item.currentLowestPrice {
                            Text(lowestPrice <= item.targetPrice ? "✓ 是" : "✗ 否")
                                .fontWeight(.semibold)
                                .foregroundStyle(lowestPrice <= item.targetPrice ? Color.profitGreen : Color.lossRed)
                        }
                    }

                    HStack {
                        Text("差额")
                        Spacer()
                        if let lowestPrice = item.currentLowestPrice {
                            let diff = lowestPrice - item.targetPrice
                            Text(diff <= 0 ? "低于目标 \(abs(diff).currencyString)" : "高于目标 \(diff.currencyString)")
                                .foregroundStyle(diff <= 0 ? Color.profitGreen : Color.warningOrange)
                        }
                    }
                }
            }

            if !allTrackedPrices.isEmpty {
                Section("价格统计") {
                    if let lowest = lowestTrackedPrice {
                        DetailRow(label: "历史最低价", value: lowest.currencyString)
                    }
                    if let highest = highestTrackedPrice {
                        DetailRow(label: "历史最高价", value: highest.currencyString)
                    }
                    if let average = averageTrackedPrice {
                        DetailRow(label: "历史均价", value: average.currencyString)
                    }
                    if let percentile = pricePercentile {
                        DetailRow(label: "当前价格分位", value: String(format: "%.0f%%", percentile * 100))
                    }
                }
            }

            // Platform Prices Section
            Section {
                if item.platformPrices.isEmpty {
                    Text("暂无平台价格")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(item.platformPrices) { price in
                        PlatformPriceRowView(price: price)
                    }
                    .onDelete(perform: deletePlatformPrices)
                }

                Button {
                    showingPlatformPriceSheet = true
                } label: {
                    Label("添加平台价格", systemImage: "plus.circle.fill")
                }
            } header: {
                Text("平台价格")
            }

            if !sortedPlatformPrices.isEmpty {
                Section("多平台对比") {
                    ForEach(sortedPlatformPrices) { price in
                        HStack {
                            Text(price.platform)
                            Spacer()
                            Text(price.price.currencyString)
                                .fontWeight(.semibold)
                                .foregroundStyle(price.id == sortedPlatformPrices.first?.id ? Color.profitGreen : .primary)
                        }
                    }

                    if let spread = platformPriceSpread {
                        HStack {
                            Text("平台价差")
                            Spacer()
                            Text(spread.currencyString)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("价格洞察（Beta）") {
                Button {
                    Task {
                        await fetchPriceInsight()
                    }
                } label: {
                    Label(isFetchingPriceInsight ? "同步中..." : "一键获取参考价格", systemImage: "sparkles")
                }
                .disabled(isFetchingPriceInsight)

                if let priceInsightMessage {
                    Text(priceInsightMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Price History Chart
            Section("价格走势") {
                if item.priceHistories.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        Text("还没有价格记录")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("记录第一条价格后，就能看到趋势变化")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                } else {
                    priceHistoryChartContent
                }

                Button {
                    showingPriceHistorySheet = true
                } label: {
                    Label(item.priceHistories.isEmpty ? "记录第一条价格" : "记录新价格", systemImage: "plus.circle.fill")
                }
            }

            Section("AI 购买建议（Beta）") {
                Text(aiSuggestionSummary)
                    .font(.subheadline)
                    .lineSpacing(2)
            }

            // Actions Section
            Section {
                Button {
                    item.isPurchased.toggle()
                    item.updatedAt = Date()
                    try? viewContext.save()
                } label: {
                    Label(
                        item.isPurchased ? "标记为未购买" : "标记为已购买",
                        systemImage: item.isPurchased ? "heart.slash" : "heart.fill"
                    )
                }

                if item.isPurchased {
                    Button {
                        convertToAsset()
                    } label: {
                        Label("转为资产", systemImage: "creditcard.fill")
                    }
                }
            }

            // Notes Section
            if let notes = item.notes, !notes.isEmpty {
                Section("备注") {
                    Text(notes)
                        .font(.body)
                }
            }
        }
        .navigationTitle("心愿详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("编辑") {
                    showingEditSheet = true
                }
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            WishlistFormView(mode: .edit(item))
        }
        .sheet(isPresented: $showingPlatformPriceSheet) {
            PlatformPriceFormView(item: item)
        }
        .sheet(isPresented: $showingPriceHistorySheet) {
            PriceHistoryFormView(item: item)
        }
    }

    private var priorityText: String {
        switch item.priority {
        case 1: return L10n.tr("最低")
        case 2: return L10n.tr("较低")
        case 3: return L10n.tr("中等")
        case 4: return L10n.tr("较高")
        case 5: return L10n.tr("最高")
        default: return L10n.tr("中等")
        }
    }

    @ViewBuilder
    private var priceHistoryChartContent: some View {
        #if canImport(Charts)
        if #available(iOS 16.0, *) {
            modernPriceHistoryChart
                .frame(height: 200)
        } else {
            priceHistoryFallbackView
        }
        #else
        priceHistoryFallbackView
        #endif
    }

    #if canImport(Charts)
    @available(iOS 16.0, *)
    private var modernPriceHistoryChart: some View {
        Chart(priceChartData, id: \.date) { data in
            LineMark(
                x: .value("日期", data.date),
                y: .value("价格", data.price)
            )
            .foregroundStyle(Color.warmTeal)
            .interpolationMethod(.catmullRom)

            PointMark(
                x: .value("日期", data.date),
                y: .value("价格", data.price)
            )
            .foregroundStyle(Color.warmTeal)
        }
        .chartYAxis {
            AxisMarks(position: .leading)
        }
    }
    #endif

    private var priceHistoryFallbackView: some View {
        let sorted = priceChartData.sorted { $0.date < $1.date }
        let minValue = sorted.map(\.price).min() ?? 0
        let maxValue = sorted.map(\.price).max() ?? 1
        let range = max(maxValue - minValue, 1)

        return VStack(alignment: .leading, spacing: 10) {
            ForEach(sorted, id: \.date) { point in
                let ratio = (point.price - minValue) / range
                HStack(spacing: 8) {
                    Text(point.date.formatted(as: "MM-dd"))
                        .font(.caption)
                        .frame(width: 42, alignment: .leading)

                    GeometryReader { proxy in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.warmTeal.opacity(0.24))
                            .frame(width: max(proxy.size.width * CGFloat(ratio), 2))
                    }
                    .frame(height: 8)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                    Text(point.price.currencyString)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 72, alignment: .trailing)
                }
            }
        }
        .frame(minHeight: 200, alignment: .top)
    }

    private func deletePlatformPrices(at offsets: IndexSet) {
        for index in offsets {
            let price = item.platformPrices[index]
            viewContext.delete(price)
        }
        try? viewContext.save()
    }

    private func convertToAsset() {
        let price = item.currentLowestPrice ?? item.targetPrice
        router.triggerWishToAsset(name: item.name, category: item.category, purchasePrice: price)
    }

    @MainActor
    private func fetchPriceInsight() async {
        isFetchingPriceInsight = true
        defer { isFetchingPriceInsight = false }

        do {
            let quotes = try await MockPriceInsightService.shared.fetchPlatformQuotes(for: item)
            let history = try await MockPriceInsightService.shared.fetchHistoricalPrices(for: item)

            for quote in quotes {
                if let existing = item.platformPrices.first(where: { $0.platform == quote.platform }) {
                    existing.price = quote.price
                    existing.lastUpdated = quote.recordedAt
                } else {
                    let newQuote = WishlistPlatformPrice(
                        context: viewContext,
                        platform: quote.platform,
                        price: quote.price,
                        lastUpdated: quote.recordedAt
                    )
                    newQuote.wishlistItem = item
                    item.platformPrices.append(newQuote)
                }
            }

            for point in history {
                let duplicate = item.priceHistories.contains { existing in
                    abs(existing.price - point.price) < 0.01 &&
                    Calendar.current.isDate(existing.recordedAt, inSameDayAs: point.date)
                }
                if duplicate { continue }

                let newPoint = WishlistPriceHistory(
                    context: viewContext,
                    price: point.price,
                    recordedAt: point.date
                )
                newPoint.wishlistItem = item
                item.priceHistories.append(newPoint)
            }

            item.updatedAt = Date()
            try viewContext.save()
            priceInsightMessage = "已更新参考价格与历史走势，你可以继续手动修正。"
        } catch {
            priceInsightMessage = "同步失败，请稍后重试。"
        }
    }
}

struct PlatformPriceRowView: View {
    let price: WishlistPlatformPrice

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(price.platform)
                    .font(.headline)
                Spacer()
                Text(price.price.currencyString)
                    .font(.callout)
                    .fontWeight(.semibold)
            }
            Text("更新时间: \(price.lastUpdated.mediumDateString)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    NavigationView {
        WishlistDetailView(item: WishlistItem(
            context: PersistenceController.preview.container.viewContext,
            name: "iPhone 16 Pro",
            category: "电子产品",
            targetPrice: 8000,
            priority: 5
        ))
    }
    .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
    .environmentObject(AppRouter())
}
