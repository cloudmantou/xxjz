import SwiftUI

struct TransactionStatsView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var viewModel = BookkeepingViewModel()

    var body: some View {
        LazyVStack(spacing: 16) {

            // Month navigator (warm style)
            HStack {
                Button(action: { changeMonth(-1) }) {
                    Image(systemName: "chevron.left")
                        .foregroundColor(.warmTeal)
                }
                Spacer()
                Text(viewModel.selectedMonth.monthYearString)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
                Spacer()
                Button(action: { changeMonth(1) }) {
                    Image(systemName: "chevron.right")
                        .foregroundColor(.warmTeal)
                }
            }
            .padding(.horizontal)

            // Summary cards row
            HStack(spacing: 10) {
                warmStatMiniCard(
                    title: "支出",
                    value: viewModel.monthlyExpense.currencyString,
                    color: Color.warmCoral
                )
                warmStatMiniCard(
                    title: "收入",
                    value: viewModel.monthlyIncome.currencyString,
                    color: Color.profitGreen
                )
                warmStatMiniCard(
                    title: "结余",
                    value: viewModel.monthlyNet.currencyString,
                    color: viewModel.monthlyNet >= 0 ? Color.profitGreen : Color.warmCoral
                )
            }
            .padding(.horizontal)

            // Category breakdown chart
            if !viewModel.categoryBreakdown.isEmpty {
                warmChartContainer {
                    PieChartCard(
                        title: "支出分类",
                        data: viewModel.categoryBreakdown.enumerated().map { index, item in
                            let cat = BookkeepingCategory.find(key: item.category)
                            return (
                                name: cat?.localizedName ?? L10n.tr(item.category),
                                value: item.amount,
                                color: Color.chartColor(at: index)
                            )
                        }
                    )
                }
            }

            // Daily spending chart
            if !viewModel.dailySpending.isEmpty {
                warmChartContainer {
                    BarChartCard(
                        title: "每日支出",
                        data: viewModel.dailySpending.map { item in
                            (name: item.day.shortDateString, value: item.amount)
                        }
                    )
                }
            }

            // Monthly trend chart
            if !viewModel.monthlyTrend.isEmpty {
                warmChartContainer {
                    LineChartCard(
                        title: "月度趋势",
                        data: viewModel.monthlyTrend.map { item in
                            (date: item.month, value: item.expense)
                        }
                    )
                }
            }
        }
        .onAppear {
            viewModel.loadStatistics(from: viewContext)
        }
    }

    // MARK: - Components

    private func warmStatMiniCard(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.system(size: 11, design: .rounded))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .cardStyle()
    }

    private func warmChartContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal)
    }

    private func changeMonth(_ offset: Int) {
        let calendar = Calendar.current
        if let newMonth = calendar.date(byAdding: .month, value: offset, to: viewModel.selectedMonth) {
            viewModel.selectedMonth = newMonth
            viewModel.loadStatistics(from: viewContext)
        }
    }
}

#Preview {
    TransactionStatsView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
