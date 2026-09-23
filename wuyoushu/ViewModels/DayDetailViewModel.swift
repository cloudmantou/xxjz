import Foundation
import CoreData

final class DayDetailViewModel: ObservableObject {

    @Published var selectedDate: Date
    @Published var transactions: [BookkeepingTransaction] = []
    @Published var categoryBreakdown: [(emoji: String, name: String, amount: Double, percent: Int, barWidth: CGFloat)] = []
    @Published var saveErrorMessage: String?

    var dayIncome: Double { transactions.filter(\.contributesToIncome).reduce(0) { $0 + $1.normalizedAmount } }
    var dayExpense: Double { transactions.filter(\.contributesToExpense).reduce(0) { $0 + $1.normalizedAmount } }
    var dayBalance: Double { dayIncome - dayExpense }
    var transactionCount: Int { transactions.count }

    init(date: Date) {
        self.selectedDate = date.startOfDay
    }

    func loadData(from context: NSManagedObjectContext) {
        let dayStart = selectedDate.startOfDay
        let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(86_400)

        let request: NSFetchRequest<BookkeepingTransaction> = BookkeepingTransaction.fetchRequest()
        request.predicate = NSPredicate(format: "date >= %@ AND date < %@", dayStart as NSDate, dayEnd as NSDate)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \BookkeepingTransaction.date, ascending: false)]

        do {
            transactions = try context.fetch(request)
            computeCategoryBreakdown()
        } catch {
            print("Failed to load day transactions: \(error)")
            transactions = []
            categoryBreakdown = []
        }
    }

    @MainActor
    func deleteTransaction(_ transaction: BookkeepingTransaction, context: NSManagedObjectContext) {
        context.delete(transaction)
        if let error = PersistenceSaveCoordinator.save(context) {
            saveErrorMessage = error
            return
        }
        saveErrorMessage = nil
        transactions.removeAll { $0.objectID == transaction.objectID }
        computeCategoryBreakdown()
    }

    private func computeCategoryBreakdown() {
        let expenses = transactions.filter(\.contributesToExpense)
        let totalExpense = expenses.reduce(0) { $0 + $1.normalizedAmount }

        guard totalExpense > 0 else {
            categoryBreakdown = []
            return
        }

        var map: [String: Double] = [:]
        for t in expenses {
            map[t.categoryKey, default: 0] += t.normalizedAmount
        }

        let maxAmount = map.values.max() ?? 1
        let sorted = map.sorted { $0.value > $1.value }

        categoryBreakdown = sorted.map { key, amount in
            let cat = BookkeepingCategory.find(key: key)
            let percent = Int(round(amount / totalExpense * 100))
            let barWidth = CGFloat(amount / maxAmount)
            return (emoji: cat?.emoji ?? "📦", name: cat?.localizedName ?? key, amount: amount, percent: percent, barWidth: barWidth)
        }
    }

    var dateTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        if selectedDate.isToday {
            formatter.dateFormat = "M月d日"
            return "今天 \(formatter.string(from: selectedDate))"
        }
        formatter.dateFormat = "M月d日 EEEE"
        return formatter.string(from: selectedDate)
    }

    var dateSubtitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年"
        return formatter.string(from: selectedDate)
    }

    func moveDate(by days: Int, context: NSManagedObjectContext) {
        guard let newDate = Calendar.current.date(byAdding: .day, value: days, to: selectedDate) else { return }
        selectedDate = newDate.startOfDay
        loadData(from: context)
    }
}
