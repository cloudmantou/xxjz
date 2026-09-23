import Foundation
import CoreData

final class BookkeepingViewModel: ObservableObject {

    // MARK: - Monthly Stats
    @Published var monthlyIncome: Double = 0
    @Published var monthlyExpense: Double = 0
    @Published var transactionCount: Int = 0
    @Published var selectedMonth = Date()

    // MARK: - Category Breakdown
    @Published var categoryBreakdown: [(category: String, amount: Double, count: Int)] = []

    // MARK: - Daily Spending
    @Published var dailySpending: [(day: Date, amount: Double)] = []

    // MARK: - Monthly Trend
    @Published var monthlyTrend: [(month: Date, income: Double, expense: Double)] = []

    // MARK: - Budget Data
    @Published var totalBudget: Double = 0
    @Published var budgetEntries: [(categoryKey: String, budget: Double, spent: Double)] = []

    var monthlyNet: Double {
        monthlyIncome - monthlyExpense
    }

    var remainingDaysInMonth: Int {
        let calendar = Calendar.current
        let now = Date()
        let endOfMonth = now.endOfMonth
        return calendar.dateComponents([.day], from: now, to: endOfMonth).day ?? 0
    }

    var dailyAverageRemaining: Double {
        guard remainingDaysInMonth > 0 else { return 0 }
        let remaining = totalBudget - monthlyExpense
        return max(0, remaining) / Double(remainingDaysInMonth)
    }

    // MARK: - Load Statistics

    func loadStatistics(from context: NSManagedObjectContext) {
        let startOfMonth = selectedMonth.startOfMonth
        let endOfMonth = selectedMonth.endOfMonth

        let request: NSFetchRequest<BookkeepingTransaction> = BookkeepingTransaction.fetchRequest()
        request.predicate = NSPredicate(
            format: "date >= %@ AND date <= %@",
            startOfMonth as NSDate,
            endOfMonth as NSDate
        )

        do {
            let transactions = try context.fetch(request)
            monthlyIncome = transactions.filter { $0.isIncome && $0.categoryKey != "transfer" }.reduce(0) { $0 + $1.normalizedAmount }
            monthlyExpense = transactions.filter { !$0.isIncome && !$0.notInBudget && $0.categoryKey != "transfer" }.reduce(0) { $0 + $1.normalizedAmount }
            transactionCount = transactions.count

            // Category breakdown (expenses only, excluding notInBudget)
            var catMap: [String: (amount: Double, count: Int)] = [:]
            for t in transactions where !t.isIncome && !t.notInBudget && t.categoryKey != "transfer" {
                let current = catMap[t.categoryKey] ?? (0, 0)
                catMap[t.categoryKey] = (current.amount + t.normalizedAmount, current.count + 1)
            }
            categoryBreakdown = catMap.map { ($0.key, $0.value.amount, $0.value.count) }
                .sorted { $0.amount > $1.amount }

            // Daily spending (excluding notInBudget)
            var dailyMap: [Date: Double] = [:]
            for t in transactions where !t.isIncome && !t.notInBudget && t.categoryKey != "transfer" {
                let dayStart = t.date.startOfDay
                dailyMap[dayStart, default: 0] += t.normalizedAmount
            }
            dailySpending = dailyMap.map { ($0.key, $0.value) }
                .sorted { $0.day < $1.day }

        } catch {
            print("Failed to load statistics: \(error)")
        }

        loadMonthlyTrend(from: context)
    }

    // MARK: - Load Monthly Trend

    private func loadMonthlyTrend(from context: NSManagedObjectContext) {
        let calendar = Calendar.current
        var trend: [(month: Date, income: Double, expense: Double)] = []

        for offset in (0..<6).reversed() {
            guard let month = calendar.date(byAdding: .month, value: -offset, to: Date()) else { continue }
            let start = month.startOfMonth
            let end = month.endOfMonth

            let request: NSFetchRequest<BookkeepingTransaction> = BookkeepingTransaction.fetchRequest()
            request.predicate = NSPredicate(format: "date >= %@ AND date <= %@", start as NSDate, end as NSDate)

            do {
                let transactions = try context.fetch(request)
                let income = transactions.filter { $0.isIncome && $0.categoryKey != "transfer" }.reduce(0) { $0 + $1.normalizedAmount }
                let expense = transactions.filter { !$0.isIncome && !$0.notInBudget && $0.categoryKey != "transfer" }.reduce(0) { $0 + $1.normalizedAmount }
                trend.append((start, income, expense))
            } catch {
                trend.append((start, 0, 0))
            }
        }
        monthlyTrend = trend
    }

    // MARK: - Load Budget

    func loadBudget(from context: NSManagedObjectContext) {
        let startOfMonth = selectedMonth.startOfMonth

        let request: NSFetchRequest<BudgetEntry> = BudgetEntry.fetchRequest()
        request.predicate = NSPredicate(format: "month == %@", startOfMonth as NSDate)

        do {
            let entries = try context.fetch(request)
            totalBudget = entries.reduce(0) { $0 + $1.monthlyAmount }

            // Calculate spent per category
            let endOfMonth = selectedMonth.endOfMonth
            let txRequest: NSFetchRequest<BookkeepingTransaction> = BookkeepingTransaction.fetchRequest()
            txRequest.predicate = NSPredicate(
                format: "date >= %@ AND date <= %@ AND isIncome == NO",
                startOfMonth as NSDate,
                endOfMonth as NSDate
            )

            let transactions = try context.fetch(txRequest)
            var spentMap: [String: Double] = [:]
            for t in transactions where !t.isIncome && !t.notInBudget && t.categoryKey != "transfer" {
                spentMap[t.categoryKey, default: 0] += t.normalizedAmount
            }

            budgetEntries = entries.map { entry in
                (entry.categoryKey, entry.monthlyAmount, spentMap[entry.categoryKey] ?? 0)
            }.sorted { $0.budget > $1.budget }

        } catch {
            print("Failed to load budget: \(error)")
        }
    }
}
