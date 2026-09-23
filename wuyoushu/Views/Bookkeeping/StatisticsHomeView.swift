import SwiftUI
import CoreData

private enum StatisticsSection: String, CaseIterable, Identifiable {
    case trend = "趋势"
    case ranking = "排行"
    case calendar = "日历"

    var id: Self { self }

    var index: Int {
        switch self {
        case .trend: return 0
        case .ranking: return 1
        case .calendar: return 2
        }
    }
}

private enum StatisticsRankType: String, CaseIterable, Identifiable {
    case expense = "支出"
    case income = "收入"

    var id: Self { self }
}

struct StatisticsHomeView: View {
    @Environment(\.bottomBarInset) private var bottomBarInset: CGFloat
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var viewModel = BookkeepingViewModel()

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \BookkeepingTransaction.date, ascending: false)],
        animation: .default
    )
    private var allTransactions: FetchedResults<BookkeepingTransaction>

    @State private var selectedSection: StatisticsSection = .trend
    @State private var previousSection: StatisticsSection = .trend
    @State private var selectedRankType: StatisticsRankType = .expense
    @Namespace private var selectorNamespace

    private var screenWidth: CGFloat {
        UIScreen.main.bounds.width
    }

    private var pageHorizontalPadding: CGFloat {
        Constants.Layout.pageHorizontalPadding(for: screenWidth)
    }

    private var sectionSpacing: CGFloat {
        Constants.Layout.sectionSpacing(for: screenWidth)
    }

    private var isLegacyCompactLayout: Bool {
        Constants.Layout.bucket(for: screenWidth) == .legacyCompact
    }

    private var heroCardMinHeight: CGFloat {
        Constants.Layout.heroCardMinHeight(for: screenWidth)
    }

    private var chartLegendMinWidth: CGFloat {
        Constants.Layout.chartLegendMinWidth(for: screenWidth)
    }

    private var monthTransactions: [BookkeepingTransaction] {
        let start = viewModel.selectedMonth.startOfMonth
        let end = viewModel.selectedMonth.endOfMonth
        return allTransactions.filter { $0.date >= start && $0.date <= end }
    }

    private var rankTransactions: [BookkeepingTransaction] {
        switch selectedRankType {
        case .expense:
            return monthTransactions.filter { !$0.isIncome && !$0.notInBudget && $0.categoryKey != "transfer" }
        case .income:
            return monthTransactions.filter { $0.isIncome }
        }
    }

    private var rankCategoryRows: [(name: String, amount: Double, count: Int)] {
        var amountMap: [String: Double] = [:]
        var countMap: [String: Int] = [:]

        for tx in rankTransactions {
            amountMap[tx.categoryKey, default: 0] += tx.normalizedAmount
            countMap[tx.categoryKey, default: 0] += 1
        }

        return amountMap
            .map { key, amount in
                let category = BookkeepingCategory.find(key: key)
                return (
                    name: category?.localizedName ?? key,
                    amount: amount,
                    count: countMap[key, default: 0]
                )
            }
            .sorted { $0.amount > $1.amount }
    }

    private var topTransactions: [BookkeepingTransaction] {
        rankTransactions.sorted { $0.normalizedAmount > $1.normalizedAmount }
    }

    private var currentMonthDays: Int {
        let range = Calendar.current.range(of: .day, in: .month, for: viewModel.selectedMonth)
        return range?.count ?? 30
    }

    private var leadingEmptyDays: Int {
        var calendar = Calendar.current
        calendar.firstWeekday = 2 // Monday
        let weekday = calendar.component(.weekday, from: viewModel.selectedMonth.startOfMonth)
        return (weekday - calendar.firstWeekday + 7) % 7
    }

    private var monthExpenseByDay: [Int: Double] {
        var map: [Int: Double] = [:]
        let calendar = Calendar.current

        for tx in monthTransactions where !tx.isIncome && !tx.notInBudget {
            let day = calendar.component(.day, from: tx.date)
            map[day, default: 0] += tx.normalizedAmount
        }
        return map
    }

    private var peakExpenseDay: (day: Int, amount: Double)? {
        monthExpenseByDay.max { $0.value < $1.value }.map { ($0.key, $0.value) }
    }

    private var dailySpendingData: [(date: Date, value: Double)] {
        let calendar = Calendar.current
        var dailyMap: [Date: Double] = [:]

        for tx in monthTransactions where !tx.isIncome && !tx.notInBudget {
            let dayStart = calendar.startOfDay(for: tx.date)
            dailyMap[dayStart, default: 0] += tx.normalizedAmount
        }

        return dailyMap
            .map { (date: $0.key, value: $0.value) }
            .sorted { $0.date < $1.date }
    }

    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(spacing: 0) {
                    // 月份导航 + 快速统计
                    monthNavigatorWithSummary
                        .padding(.horizontal, pageHorizontalPadding)
                        .padding(.top, 8)
                        .padding(.bottom, 10)

                    // 流畅滑块选择器
                    smoothSectionSelector
                        .padding(.horizontal, pageHorizontalPadding)
                        .padding(.bottom, 12)

                    // 内容区域（带方向动画）
                    ZStack {
                        switch selectedSection {
                        case .trend:
                            trendSection
                                .transition(sectionTransition(to: .trend))
                        case .ranking:
                            rankingSection
                                .transition(sectionTransition(to: .ranking))
                        case .calendar:
                            calendarSection
                                .transition(sectionTransition(to: .calendar))
                        }
                    }
                    .animation(.spring(response: 0.38, dampingFraction: 0.82), value: selectedSection)
                    .padding(.horizontal, pageHorizontalPadding)
                    .padding(.bottom, 20 + bottomBarInset)
                }
            }
            .background(Color.appPageBackground)
            .navigationTitle("统计")
            .onAppear {
                reloadStatistics()
            }
            .onChange(of: viewModel.selectedMonth) { _ in
                reloadStatistics()
            }
            .onChange(of: allTransactions.count) { _ in
                reloadStatistics()
            }
        }
    }

    // MARK: - 月份导航 + 快速统计合并头部

    private var monthNavigatorWithSummary: some View {
        VStack(spacing: 0) {
            // ── 渐变 Hero 卡 ──
            ZStack {
                // 背景渐变
                RoundedRectangle(cornerRadius: CardRadius.large, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.heroGradientTop, Color.heroGradientBottom],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                VStack(spacing: 14) {
                    // 月份导航行
                    HStack(spacing: 0) {
                        Button(action: { changeMonth(-1) }) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.white.opacity(0.9))
                                .frame(width: 36, height: 36)
                                .background(Color.white.opacity(0.18))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        VStack(spacing: 3) {
                            Text(viewModel.selectedMonth.monthYearString)
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                            Text("\(viewModel.transactionCount) 笔记录")
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundColor(.white.opacity(0.72))
                        }

                        Spacer()

                        Button(action: { changeMonth(1) }) {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.white.opacity(0.9))
                                .frame(width: 36, height: 36)
                                .background(Color.white.opacity(0.18))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }

                    // 三栏数字摘要
                    HStack(spacing: 0) {
                        heroMetric(
                            title: "支出",
                            value: viewModel.monthlyExpense,
                            icon: "arrow.down.circle.fill",
                            isExpense: true
                        )

                        Rectangle()
                            .fill(Color.white.opacity(0.22))
                            .frame(width: 0.5)
                            .frame(height: 44)

                        heroMetric(
                            title: "收入",
                            value: viewModel.monthlyIncome,
                            icon: "arrow.up.circle.fill",
                            isIncome: true
                        )

                        Rectangle()
                            .fill(Color.white.opacity(0.22))
                            .frame(width: 0.5)
                            .frame(height: 44)

                        heroMetricNet(
                            title: "结余",
                            value: viewModel.monthlyNet
                        )
                    }
                    .padding(.bottom, 4)
                }
                .padding(.horizontal, pageHorizontalPadding)
                .padding(.vertical, 16)
            }
            .frame(minHeight: heroCardMinHeight)
        }
    }

    private func heroMetric(title: String, value: Double, icon: String,
                            isExpense: Bool = false, isIncome: Bool = false) -> some View {
        VStack(spacing: 5) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.7))
                Text(title)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))
            }
            AnimatedCurrencyText(
                value: value,
                color: isExpense ? Color(hex: "FFD8D8") : (isIncome ? Color(hex: "D7F4E1") : .white)
            )
        }
        .frame(maxWidth: .infinity)
    }

    private func heroMetricNet(title: String, value: Double) -> some View {
        VStack(spacing: 5) {
            HStack(spacing: 3) {
                Image(systemName: "equal.circle.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.7))
                Text(title)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))
            }
            AnimatedCurrencyText(
                value: value,
                color: value >= 0 ? Color(hex: "D7F4E1") : Color(hex: "FFD8D8")
            )
        }
        .frame(maxWidth: .infinity)
    }

    private func animatedSummaryMetric(title: String, value: Double, color: Color, icon: String) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundColor(color.opacity(0.7))
                Text(title)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
            }
            AnimatedCurrencyText(value: value, color: color)
        }
    }

    // MARK: - 流畅滑块选择器（matchedGeometryEffect）

    private var smoothSectionSelector: some View {
        HStack(spacing: 0) {
            ForEach(StatisticsSection.allCases) { section in
                Button {
                    let wasSection = selectedSection
                    previousSection = wasSection
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        selectedSection = section
                    }
                } label: {
                    ZStack {
                        if selectedSection == section {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.warmTeal)
                                .matchedGeometryEffect(id: "selectorBackground", in: selectorNamespace)
                                .shadow(color: Color.warmTeal.opacity(0.18), radius: 10, y: 4)
                        }

                        Text(section.rawValue)
                            .font(.system(size: 13, weight: selectedSection == section ? .semibold : .regular, design: .rounded))
                            .foregroundColor(selectedSection == section ? .white : .textSecondary)
                            .scaleEffect(selectedSection == section ? 1.02 : 1.0)
                            .padding(.vertical, 9)
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.statisticsCardBackground)
        )
    }

    private func sectionTransition(to target: StatisticsSection) -> AnyTransition {
        let insertFromTrailing = target.index > previousSection.index
        return AnyTransition.asymmetric(
            insertion: .move(edge: insertFromTrailing ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: insertFromTrailing ? .leading : .trailing).combined(with: .opacity)
        )
    }

    // MARK: - 趋势 Tab

    private var trendSection: some View {
        VStack(spacing: sectionSpacing) {
            if !viewModel.categoryBreakdown.isEmpty {
                // 左右分布的 Donut 图
                VStack(alignment: .leading, spacing: 12) {
                    Label("支出分类", systemImage: "chart.pie.fill")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(.primary)

                    if isLegacyCompactLayout {
                        VStack(spacing: 14) {
                            donutChartView
                                .frame(width: 148, height: 148)
                                .frame(maxWidth: .infinity)

                            donutLegendView
                        }
                    } else {
                        HStack(alignment: .center, spacing: 16) {
                            donutChartView
                                .frame(width: 140, height: 140)

                            donutLegendView
                                .frame(minWidth: chartLegendMinWidth, maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(Constants.UI.cardPadding)
                .frame(minHeight: isLegacyCompactLayout ? 244 : 198, alignment: .top)
                .background(Color.statisticsCardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
            }

            if !dailySpendingData.isEmpty {
                LineChartCard(
                    title: "每日支出",
                    data: dailySpendingData,
                    budgetLine: viewModel.dailyAverageRemaining > 0 ? viewModel.dailyAverageRemaining : nil,
                    cardBackgroundColor: .statisticsCardBackground
                )
            }

            if !viewModel.monthlyTrend.isEmpty {
                LineChartCard(
                    title: "近六月支出趋势",
                    data: viewModel.monthlyTrend.map { item in
                        (date: item.month, value: item.expense)
                    },
                    cardBackgroundColor: .statisticsCardBackground
                )
            }

            if viewModel.categoryBreakdown.isEmpty && dailySpendingData.isEmpty && viewModel.monthlyTrend.isEmpty {
                emptyCard(message: "本月暂无可统计数据")
            }
        }
    }

    private var donutChartView: some View {
        DonutChartView(
            data: viewModel.categoryBreakdown.enumerated().map { index, item in
                let cat = BookkeepingCategory.find(key: item.category)
                return (
                    name: cat?.localizedName ?? item.category,
                    value: item.amount,
                    color: Color.chartColor(at: index)
                )
            },
            total: viewModel.monthlyExpense
        )
    }

    private var donutLegendView: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(viewModel.categoryBreakdown.prefix(5).enumerated()), id: \.offset) { index, item in
                let cat = BookkeepingCategory.find(key: item.category)
                let name = cat?.localizedName ?? item.category
                let pct = viewModel.monthlyExpense > 0 ? item.amount / viewModel.monthlyExpense * 100 : 0

                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.chartColor(at: index))
                        .frame(width: 8, height: 8)

                    Text(name)
                        .font(.system(size: 12, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    Spacer(minLength: 8)

                    Text(String(format: "%.0f%%", pct))
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                        .frame(width: 34, alignment: .trailing)
                }
            }
        }
    }

    // MARK: - 排行 Tab

    private var rankingSection: some View {
        VStack(spacing: sectionSpacing) {
            // 类型切换胶囊
            HStack(spacing: 6) {
                ForEach(StatisticsRankType.allCases) { type in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            selectedRankType = type
                        }
                    } label: {
                        Text(type.rawValue)
                            .font(.system(size: 13, weight: selectedRankType == type ? .semibold : .regular, design: .rounded))
                            .foregroundColor(selectedRankType == type ? .white : .secondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(
                                Capsule()
                                    .fill(selectedRankType == type ? Color.warmTeal : Color.statisticsCardBackground)
                            )
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }

            // 快报卡片（3 格横向）
            if !rankCategoryRows.isEmpty {
                rankQuickStats
            }

            if rankCategoryRows.isEmpty {
                emptyCard(message: "当前维度暂无排行数据")
            } else {
                // 分类排行（带入场动画）
                VStack(alignment: .leading, spacing: 12) {
                    Label("分类排行", systemImage: "list.number")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))

                    ForEach(Array(rankCategoryRows.prefix(6).enumerated()), id: \.offset) { index, row in
                        AnimatedRankingRow(
                            index: index + 1,
                            name: row.name,
                            amount: row.amount,
                            count: row.count,
                            maxAmount: rankCategoryRows.first?.amount ?? row.amount,
                            animationDelay: Double(index) * 0.07
                        )
                    }
                }
                .padding(14)
                .background(Color.statisticsCardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
            }

            if !topTransactions.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Label("大额记录", systemImage: "arrow.up.right.circle.fill")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))

                    ForEach(Array(topTransactions.prefix(5).enumerated()), id: \.element.id) { index, tx in
                        HStack(spacing: 10) {
                            Text("#\(index + 1)")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundColor(.secondary)
                                .frame(width: 26, alignment: .leading)

                            Text(tx.categoryEmoji)
                                .font(.system(size: 18))

                            VStack(alignment: .leading, spacing: 1) {
                                Text(tx.categoryName)
                                    .font(.system(size: 14, weight: .medium, design: .rounded))
                                Text(tx.date.formatted(as: "MM-dd"))
                                    .font(.system(size: 11, design: .rounded))
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Text(tx.normalizedAmount.currencyString)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundColor(selectedRankType == .expense ? Color.lossRed : .profitGreen)
                        }

                        if index < min(topTransactions.count - 1, 4) {
                            Divider()
                        }
                    }
                }
                .padding(14)
                .background(Color.statisticsCardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
            }
        }
    }

    /// 3格快报横向卡片
    private var rankQuickStats: some View {
        let max = rankCategoryRows.first
        let min = rankCategoryRows.last
        let total = rankTransactions.count

        return HStack(spacing: 0) {
            quickStatCell(title: "最多", value: max?.name ?? "-", sub: max.map { $0.amount.compactCurrencyString } ?? "", color: Color.lossRed)
            Divider().frame(height: 36)
            quickStatCell(title: "最少", value: min?.name ?? "-", sub: min.map { $0.amount.compactCurrencyString } ?? "", color: Color(hex: "78909C"))
            Divider().frame(height: 36)
            quickStatCell(title: "笔数", value: "\(total)", sub: "笔", color: Color.warmTeal)
        }
        .padding(.vertical, 10)
        .background(Color.statisticsCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.03), radius: 4, y: 1)
    }

    private func quickStatCell(title: String, value: String, sub: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Text(title)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(sub)
                .font(.system(size: 10, design: .rounded))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 日历 Tab

    private var calendarSection: some View {
        VStack(spacing: sectionSpacing) {
            // 顶部双 badge
            HStack(spacing: 8) {
                calendarBadge(
                    title: "本月支出",
                    value: viewModel.monthlyExpense.currencyString,
                    color: Color.lossRed,
                    bg: Color.pastelRed
                )
                calendarBadge(
                    title: "本月收入",
                    value: viewModel.monthlyIncome.currencyString,
                    color: .profitGreen,
                    bg: Color.pastelGreen
                )
            }

            VStack(alignment: .leading, spacing: 10) {
                Label("月历视图", systemImage: "calendar")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 8) {
                    ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) { weekday in
                        Text(weekday)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                    }

                    ForEach(0..<leadingEmptyDays, id: \.self) { _ in
                        Color.clear
                            .frame(height: 54)
                    }

                    ForEach(1...currentMonthDays, id: \.self) { day in
                        calendarDayCell(day: day, expense: monthExpenseByDay[day] ?? 0)
                    }
                }
            }
            .padding(14)
            .background(Color.statisticsCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.04), radius: 6, y: 2)

            HStack(spacing: 10) {
                calendarSummaryBadge(
                    title: "日均支出",
                    value: averageDailyExpense.currencyString,
                    color: .warmTeal
                )

                if let peak = peakExpenseDay {
                    calendarSummaryBadge(
                        title: "峰值日期",
                        value: "\(peak.day)日 \(peak.amount.compactCurrencyString)",
                        color: Color.lossRed
                    )
                }
            }

            if monthTransactions.isEmpty {
                emptyCard(message: "本月暂无账单记录")
            }
        }
    }

    private func calendarBadge(title: String, value: String, color: Color, bg: Color) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color.opacity(0.8))
                .frame(width: 6, height: 6)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(color)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(bg)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func calendarDayCell(day: Int, expense: Double) -> some View {
        PulsingCalendarDayCell(
            day: day,
            expense: expense,
            month: viewModel.selectedMonth
        )
    }

    private func calendarSummaryBadge(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.statisticsCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var averageDailyExpense: Double {
        guard currentMonthDays > 0 else { return 0 }
        return viewModel.monthlyExpense / Double(currentMonthDays)
    }

    private func emptyCard(message: String) -> some View {
        Text(message)
            .font(.subheadline)
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, minHeight: 100)
            .padding(.horizontal, 12)
            .background(Color.statisticsCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func changeMonth(_ offset: Int) {
        let calendar = Calendar.current
        if let newMonth = calendar.date(byAdding: .month, value: offset, to: viewModel.selectedMonth) {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                viewModel.selectedMonth = newMonth
            }
        }
    }

    private func reloadStatistics() {
        viewModel.loadStatistics(from: viewContext)
        viewModel.loadBudget(from: viewContext)
    }
}

// MARK: - AnimatedCurrencyText（数字动画）

private struct AnimatedCurrencyText: View {
    let value: Double
    let color: Color

    @State private var displayValue: Double = 0

    var body: some View {
        Text(displayValue.compactCurrencyString)
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .foregroundColor(color)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .onAppear {
                withAnimation(.easeOut(duration: 0.55)) {
                    displayValue = value
                }
            }
            .onChange(of: value) { newValue in
                withAnimation(.easeOut(duration: 0.45)) {
                    displayValue = newValue
                }
            }
    }
}

// MARK: - AnimatedRankingRow（进度条 stagger 动画）

private struct AnimatedRankingRow: View {
    let index: Int
    let name: String
    let amount: Double
    let count: Int
    let maxAmount: Double
    let animationDelay: Double

    @State private var animatedRatio: CGFloat = 0

    private var ratio: CGFloat {
        maxAmount > 0 ? CGFloat(amount / maxAmount) : 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(index <= 3 ? Color.warmTeal.opacity(0.15) : Color.clear)
                        .frame(width: 22, height: 22)
                    Text("\(index)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(index <= 3 ? .warmTeal : .secondary)
                }
                .frame(width: 22)

                Text(name)
                    .font(.system(size: 14, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8) // Ensure text scales down if too long

                Spacer()

                Text("\(count)笔")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundColor(.secondary)

                Text(amount.compactCurrencyString)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.secondary.opacity(0.08))

                    RoundedRectangle(cornerRadius: 3)
                        .fill(
                            LinearGradient(
                                colors: [Color.warmTeal, Color.warmTeal.opacity(0.6)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: proxy.size.width * animatedRatio)
                }
            }
            .frame(height: 6)
            .clipShape(RoundedRectangle(cornerRadius: 3))
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.6).delay(animationDelay)) {
                animatedRatio = ratio
            }
        }
        .onChange(of: amount) { _ in
            animatedRatio = 0
            withAnimation(.easeOut(duration: 0.5).delay(animationDelay)) {
                animatedRatio = ratio
            }
        }
    }
}

// MARK: - PulsingCalendarDayCell（今日脉冲）

private struct PulsingCalendarDayCell: View {
    let day: Int
    let expense: Double
    let month: Date

    @State private var pulse = false

    private var isToday: Bool {
        let calendar = Calendar.current
        guard let date = calendar.date(bySetting: .day, value: day, of: month.startOfMonth) else { return false }
        return calendar.isDateInToday(date)
    }

    var body: some View {
        VStack(spacing: 3) {
            Text("\(day)")
                .font(.system(size: 13, weight: isToday ? .bold : .regular, design: .rounded))
                .foregroundColor(isToday ? .warmTeal : .primary)

            if expense > 0 {
                Text(expense >= 1000 ? expense.compactCurrencyString : String(format: "¥%.0f", expense))
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundColor(Color.lossRed)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else {
                Text(" ")
                    .font(.system(size: 9))
            }
        }
        .frame(height: 54)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isToday ? Color.warmTealLight : Color.statisticsCardBackground)
                .scaleEffect(pulse ? 1.04 : 1.0)
        )
        .onAppear {
            if isToday {
                withAnimation(
                    .easeInOut(duration: 1.2)
                    .repeatForever(autoreverses: true)
                    .delay(0.3)
                ) {
                    pulse = true
                }
            }
        }
    }
}

// MARK: - DonutChartView（新 Donut 图，带入场动画）

private struct DonutChartView: View {
    let data: [(name: String, value: Double, color: Color)]
    let total: Double

    @State private var animationProgress: CGFloat = 0

    private var segmentData: [(startAngle: CGFloat, endAngle: CGFloat, color: Color)] {
        let t = max(total, 1)
        var result: [(startAngle: CGFloat, endAngle: CGFloat, color: Color)] = []
        var currentAngle: CGFloat = 0
        for item in data {
            let proportion = CGFloat(item.value / t)
            let angle = proportion * 360
            result.append((currentAngle, currentAngle + angle, item.color))
            currentAngle += angle
        }
        return result
    }

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height) * 0.9 // Reduce size to avoid overflow
            let lineWidth = size * 0.18 // Adjust line width proportionally

            ZStack {
                // 背景圆环
                Circle()
                    .stroke(Color.secondary.opacity(0.08), lineWidth: lineWidth)

                // 各分段（带动画进度）
                ForEach(Array(segmentData.enumerated()), id: \ .offset) { _, segment in
                    let clampedEnd = segment.startAngle + (segment.endAngle - segment.startAngle) * animationProgress
                    Circle()
                        .trim(
                            from: segment.startAngle / 360,
                            to: max(segment.startAngle / 360, clampedEnd / 360)
                        )
                        .stroke(segment.color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                        .rotationEffect(.degrees(-90))
                }

                // 中心文字
                VStack(spacing: 1) {
                    Text(total.abbreviated)
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .foregroundColor(.primary)
                    Text("本月支出")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: size, height: size)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.75)) {
                animationProgress = 1.0
            }
        }
        .onChange(of: total) { _ in
            animationProgress = 0
            withAnimation(.easeOut(duration: 0.6)) {
                animationProgress = 1.0
            }
        }
    }
}

#Preview {
    StatisticsHomeView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
