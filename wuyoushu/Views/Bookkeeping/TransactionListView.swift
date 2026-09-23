import SwiftUI
import CoreData

struct TransactionListView: View {
    @Environment(\.bottomBarInset) private var bottomBarInset: CGFloat
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \BookkeepingTransaction.date, ascending: false)],
        animation: .default
    )
    private var allTransactions: FetchedResults<BookkeepingTransaction>

    @State private var searchText = ""
    @State private var selectedFilter = "全部"
    @State private var showIncomeOnly = false

    private let filterOptions = ["全部", "餐饮", "交通", "购物", "娱乐", "居住", "医疗", "教育", "人情", "转账", "其他"]

    private var filteredTransactions: [BookkeepingTransaction] {
        var result = Array(allTransactions)

        if showIncomeOnly {
            result = result.filter { $0.isIncome }
        } else if selectedFilter != "全部" {
            let key = filterKey(from: selectedFilter)
            result = result.filter { $0.categoryKey == key }
        }

        if !searchText.isEmpty {
            result = result.filter { t in
                (t.note?.contains(searchText) ?? false) ||
                t.categoryName.contains(searchText)
            }
        }

        return result
    }

    private var groupedByDate: [(date: Date, transactions: [BookkeepingTransaction])] {
        var groups: [Date: [BookkeepingTransaction]] = [:]
        for t in filteredTransactions {
            let dayStart = t.date.startOfDay
            groups[dayStart, default: []].append(t)
        }
        return groups.map { ($0.key, $0.value) }
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                searchBar

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(filterOptions, id: \.self) { option in
                            filterChip(
                                title: option,
                                isSelected: selectedFilter == option && !showIncomeOnly,
                                action: {
                                    showIncomeOnly = false
                                    selectedFilter = option
                                }
                            )
                        }

                        filterChip(
                            title: "收入",
                            isSelected: showIncomeOnly,
                            action: {
                                showIncomeOnly = true
                                selectedFilter = "全部"
                            }
                        )
                    }
                    .padding(.horizontal, 16)
                }

                if groupedByDate.isEmpty {
                    EmptyStateView(
                        icon: "doc.text.magnifyingglass",
                        title: "没有记录",
                        message: "暂无匹配的交易记录"
                    )
                    .padding(.top, 40)
                }

                ForEach(groupedByDate, id: \.date) { group in
                    dayCard(date: group.date, transactions: group.transactions)
                }
            }
            .padding(.bottom, bottomBarInset)
        }
    }

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("搜索备注或分类", text: $searchText)
                .font(.subheadline)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.appCardMutedBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.black.opacity(0.04), lineWidth: 1)
        )
        .padding(.horizontal, 16)
    }

    private func filterChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(isSelected ? .semibold : .regular))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.warmTeal : Color.appCardMutedBackground)
                )
                .overlay(
                    Capsule()
                        .stroke(Color.black.opacity(isSelected ? 0 : 0.06), lineWidth: 1)
                )
                .foregroundStyle(isSelected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }

    private func dayCard(date: Date, transactions: [BookkeepingTransaction]) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(formatDate(date))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                let dayExpense = transactions.filter(\.contributesToExpense).reduce(0) { $0 + $1.normalizedAmount }
                if dayExpense > 0 {
                    Text("-\(dayExpense.currencyString)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.lossRed)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 6)

            ForEach(Array(transactions.enumerated()), id: \.element.id) { index, transaction in
                transactionRow(transaction)
                if index < transactions.count - 1 {
                    Divider()
                        .padding(.leading, 54)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.appCardMutedBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.black.opacity(0.04), lineWidth: 1)
        )
        .padding(.horizontal, 16)
    }

    private func transactionRow(_ transaction: BookkeepingTransaction) -> some View {
        HStack(spacing: 10) {
            Text(transaction.categoryEmoji)
                .font(.system(size: 19))
                .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.categoryName)
                    .font(.subheadline.weight(.medium))
                HStack(spacing: 4) {
                    if let fundKey = transaction.fundAccountKey,
                       let fund = FundAccount.find(key: fundKey) {
                        Text(fund.emoji)
                            .font(.system(size: 10))
                    }
                    if let note = transaction.note, !note.isEmpty {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            Text(transaction.amountDisplayText)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(
                    transaction.kind == .income
                        ? Color.profitGreen
                        : (transaction.kind == .transfer ? Color.secondary : Color.lossRed)
                )
        }
        .padding(.vertical, 8)
    }

    private func formatDate(_ date: Date) -> String {
        if date.isToday {
            return "今天"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日 EEEE"
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: date)
    }

    private func filterKey(from name: String) -> String {
        switch name {
        case "餐饮": return "dining"
        case "交通": return "transport"
        case "购物": return "shopping"
        case "娱乐": return "entertainment"
        case "居住": return "housing"
        case "医疗": return "medical"
        case "教育": return "education"
        case "人情": return "social"
        case "转账": return "transfer"
        case "其他": return "other"
        default: return ""
        }
    }
}

#Preview {
    TransactionListView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
