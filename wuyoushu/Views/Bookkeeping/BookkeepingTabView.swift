import SwiftUI
import CoreData

struct BookkeepingTabView: View {
    @EnvironmentObject private var router: AppRouter
    @Environment(\.managedObjectContext) private var viewContext

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \BookkeepingTransaction.date, ascending: false)],
        animation: .default
    )
    private var allTransactions: FetchedResults<BookkeepingTransaction>

    @State private var selectedSegment = 0  // 0=记账, 1=账单, 2=统计

    // Quick Record State
    @State private var amountString = ""
    @State private var selectedCategory: String?
    @State private var note = ""
    @State private var date = Date()
    @State private var transactionType: TransactionType = .expense
    @State private var notInBudget: Bool = false
    @State private var saveErrorMessage: String?

    private var isIncome: Bool { transactionType == .income }
    private var isTransfer: Bool { transactionType == .transfer }

    private var computedTotal: Double {
        evaluate(amountString)
    }

    private var todayTransactions: [BookkeepingTransaction] {
        let dayStart = Date().startOfDay
        let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(86_400)
        return allTransactions.filter { $0.date >= dayStart && $0.date < dayEnd }
    }

    private var todayExpense: Double {
        todayTransactions.filter(\.contributesToExpense).reduce(0) { $0 + $1.normalizedAmount }
    }

    private var todayIncome: Double {
        todayTransactions.filter(\.contributesToIncome).reduce(0) { $0 + $1.normalizedAmount }
    }

    private var todayBalance: Double {
        todayIncome - todayExpense
    }

    private var currentCategories: [BookkeepingCategory] {
        if isTransfer {
            return [BookkeepingCategory(key: "transfer", name: "转账", emoji: "↗️", colorHex: "546E7A", subcategories: [])]
        }
        return BookkeepingCategory.expenseCategories
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Segment: 记账 / 账单 / 统计
                Picker("视图", selection: $selectedSegment) {
                    Text("记账").tag(0)
                    Text("账单").tag(1)
                    Text("统计").tag(2)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                if selectedSegment == 0 {
                    recordContent
                } else if selectedSegment == 1 {
                    billListContent
                } else {
                    TransactionStatsView()
                }
            }
            .background(Color.appPageBackground)
            .navigationTitle("记账")
            .onAppear {
                loadDefaults()
            }
            .persistenceSaveErrorAlert($saveErrorMessage)
        }
    }

    // MARK: - 记账内容

    private var recordContent: some View {
        VStack(spacing: 0) {
            // Type toggle: 支出 / 收入 / 转账
            typeToggleSection
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 8)

            // Category grid
            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 70), spacing: 12)], spacing: 12) {
                    ForEach(currentCategories) { category in
                        categoryCell(category)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .frame(maxHeight: .infinity)

            // Amount display
            amountDisplayBar
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

            // Quick action row
            quickActionRow
                .padding(.horizontal, 16)
                .padding(.bottom, 6)

            // Calculator keyboard
            calculatorSection
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
        }
    }

    // MARK: - 账单列表内容

    private var billListContent: some View {
        ScrollView {
            if todayTransactions.isEmpty {
                EmptyStateView(
                    icon: "note.text",
                    title: "今日暂无记录",
                    message: "点击上方记账开始记录"
                )
                .padding(.top, 40)
            } else {
                VStack(spacing: 8) {
                    // 今日汇总 - 小票头部风格
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("今日支出")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(todayExpense.currencyString)
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(Color.warmCoral)
                        }
                        Spacer()
                        Text(Date().shortDateString)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.appCardBackground)
                    .cornerRadius(12)

                    // 交易列表 - 小票风格
                    VStack(spacing: 0) {
                        ForEach(Array(todayTransactions.enumerated()), id: \.element.id) { index, transaction in
                            billTransactionRow(transaction)
                            if index < todayTransactions.count - 1 {
                                Divider()
                                    .padding(.leading, 52)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.appCardBackground)
                    .cornerRadius(12)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
    }

    @ViewBuilder
    private func billTransactionRow(_ transaction: BookkeepingTransaction) -> some View {
        HStack(spacing: 12) {
            Text(transaction.categoryEmoji)
                .font(.system(size: 20))
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 1) {
                Text(transaction.categoryName)
                    .font(.system(size: 16, weight: .medium))
                if let note = transaction.note, !note.isEmpty {
                    Text(note)
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Text(transaction.amountDisplayText)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(
                    transaction.kind == .income
                        ? Color.profitGreen
                        : (transaction.kind == .transfer ? Color.secondary : Color.warmCoral)
                )
                .monospacedDigit()
        }
        .padding(.vertical, 13)
        .padding(.horizontal, 6)
    }

    // MARK: - Type Toggle

    private var typeToggleSection: some View {
        HStack(spacing: 0) {
            typeButton(title: "支出", isSelected: transactionType == .expense) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    transactionType = .expense
                    selectedCategory = nil
                }
            }
            typeButton(title: "收入", isSelected: transactionType == .income) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    transactionType = .income
                    selectedCategory = nil
                }
            }
            typeButton(title: "转账", isSelected: transactionType == .transfer) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    transactionType = .transfer
                    selectedCategory = "transfer"
                }
            }
        }
        .background(Color(.tertiarySystemGroupedBackground))
        .cornerRadius(8)
    }

    private func typeButton(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? .white : .secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(isSelected ? Color.warmTeal : Color.clear)
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Category Cell

    private func categoryCell(_ category: BookkeepingCategory) -> some View {
        let isSelected = selectedCategory == category.key
        return Button(action: {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedCategory = category.key
            }
            hapticFeedback()
        }) {
            VStack(spacing: 4) {
                Text(category.emoji)
                    .font(.system(size: 24))
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(Color(hex: category.colorHex))
                    )
                    .overlay(
                        Circle()
                            .stroke(isSelected ? Color.warmTeal : Color.clear, lineWidth: 2.5)
                    )
                Text(category.localizedName)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? .warmTeal : .secondary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Amount Display

    private var amountDisplayBar: some View {
        HStack(spacing: 10) {
            TextField("备注", text: $note)
                .font(.system(size: 16))
                .foregroundColor(.primary)
                .submitLabel(.done)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.appCardBackground.opacity(0.82))
                .cornerRadius(8)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("¥")
                    .font(.system(size: 20, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
                Text(displayAmount)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.appCardMutedBackground)
        .cornerRadius(12)
    }

    private var displayAmount: String {
        if amountString.isEmpty { return "0.00" }
        let evaluated = evaluate(amountString)
        return String(format: "%.2f", evaluated)
    }

    // MARK: - Quick Action Row

    private var quickActionRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                quickActionChip(icon: "calendar", title: dateText) {
                    // Date picker would go here
                }

                if let cat = selectedCategory, let catObj = BookkeepingCategory.find(key: cat) {
                    quickActionChip(icon: nil, title: catObj.localizedName) {}
                }

                Button(action: { notInBudget.toggle() }) {
                    HStack(spacing: 4) {
                        Image(systemName: notInBudget ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 11))
                        Text("不计入预算")
                            .font(.system(size: 12))
                    }
                    .foregroundColor(notInBudget ? Color.warmTeal : .secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(notInBudget ? Color.warmTeal.opacity(0.1) : Color(.tertiarySystemGroupedBackground))
                    .cornerRadius(14)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var dateText: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "今天" }
        if calendar.isDateInYesterday(date) { return "昨天" }
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("Md")
        return formatter.string(from: date)
    }

    private func quickActionChip(icon: String?, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 11))
                }
                Text(title)
                    .font(.system(size: 12))
                    .lineLimit(1)
            }
            .foregroundColor(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color(.tertiarySystemGroupedBackground))
            .cornerRadius(14)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Calculator Section

    private var calculatorSection: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                calcDigitButton("1")
                calcDigitButton("2")
                calcDigitButton("3")
                calcActionButton("⌫", color: .secondary) {
                    if !amountString.isEmpty { amountString.removeLast() }
                }
            }

            HStack(spacing: 6) {
                calcDigitButton("4")
                calcDigitButton("5")
                calcDigitButton("6")
                calcOperatorButton("+")
            }

            HStack(spacing: 6) {
                calcDigitButton("7")
                calcDigitButton("8")
                calcDigitButton("9")
                calcOperatorButton("−")
            }

            HStack(spacing: 6) {
                calcDecimalButton
                calcDigitButton("0")
                calcSaveButton
            }
        }
    }

    private func calcDigitButton(_ digit: String) -> some View {
        Button(action: {
            hapticFeedback()
            appendDigit(digit)
        }) {
            Text(digit)
                .font(.system(size: 22, weight: .medium, design: .rounded))
                .frame(maxWidth: .infinity, minHeight: 50, maxHeight: 50)
                .background(Color.appCardMutedBackground)
                .foregroundColor(.primary)
                .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }

    private var calcDecimalButton: some View {
        Button(action: {
            hapticFeedback()
            if !amountString.contains(".") && !amountString.isEmpty {
                amountString += "."
            }
        }) {
            Text(".")
                .font(.system(size: 22, weight: .medium, design: .rounded))
                .frame(maxWidth: .infinity, minHeight: 50, maxHeight: 50)
                .background(Color.appCardMutedBackground)
                .foregroundColor(.primary)
                .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }

    private func calcOperatorButton(_ op: String) -> some View {
        Button(action: {
            hapticFeedback()
            appendOperator(op)
        }) {
            Text(op)
                .font(.system(size: 22, weight: .medium, design: .rounded))
                .frame(maxWidth: .infinity, minHeight: 50, maxHeight: 50)
                .background(Color(.tertiarySystemGroupedBackground))
                .foregroundColor(Color.warmTeal)
                .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }

    private func calcActionButton(_ label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: {
            hapticFeedback()
            action()
        }) {
            Text(label)
                .font(.system(size: 18, weight: .medium, design: .rounded))
                .frame(maxWidth: .infinity, minHeight: 50, maxHeight: 50)
                .background(Color(.tertiarySystemGroupedBackground))
                .foregroundColor(color)
                .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }

    private var calcSaveButton: some View {
        Button(action: {
            saveAndDismiss()
        }) {
            Text("完成")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity, minHeight: 50, maxHeight: 50)
                .background(computedTotal > 0 ? Color.warmTeal : Color(.tertiarySystemGroupedBackground))
                .foregroundColor(computedTotal > 0 ? .white : Color(.quaternaryLabel))
                .cornerRadius(10)
        }
        .buttonStyle(.plain)
        .disabled(computedTotal <= 0)
    }

    // MARK: - Helpers

    private func appendDigit(_ digit: String) {
        let operators = CharacterSet(charactersIn: "+−×÷")
        let lastOpIndex = amountString.lastIndex(where: { char in
            String(char).rangeOfCharacter(from: operators) != nil
        })
        let currentSegment = lastOpIndex.map { String(amountString[amountString.index(after: $0)...]) } ?? amountString
        let newSegment = currentSegment + digit

        let parts = newSegment.components(separatedBy: ".")
        if let intPart = parts.first, intPart.count > 8 { return }
        if parts.count > 1, parts[1].count > 2 { return }

        amountString += digit
    }

    private func appendOperator(_ op: String) {
        guard !amountString.isEmpty else { return }
        let operators = CharacterSet(charactersIn: "+−×÷")
        if let last = amountString.last, String(last).rangeOfCharacter(from: operators) != nil {
            amountString.removeLast()
        }
        amountString += op
    }

    private func evaluate(_ expr: String) -> Double {
        guard !expr.isEmpty else { return 0 }

        var tokens: [String] = []
        var currentNumber = ""
        let operators = CharacterSet(charactersIn: "+−×÷")

        for char in expr {
            let s = String(char)
            if s.rangeOfCharacter(from: operators) != nil {
                if !currentNumber.isEmpty {
                    tokens.append(currentNumber)
                    currentNumber = ""
                }
                tokens.append(s)
            } else {
                currentNumber += s
            }
        }
        if !currentNumber.isEmpty {
            tokens.append(currentNumber)
        }

        guard !tokens.isEmpty else { return 0 }

        var numbers: [Double] = []
        var ops: [String] = []

        for (i, token) in tokens.enumerated() {
            if i % 2 == 0 {
                guard let n = Double(token) else { return 0 }
                numbers.append(n)
            } else {
                ops.append(token)
            }
        }

        // 表达式以运算符结尾（如 "100+"），忽略末尾运算符
        guard numbers.count > ops.count else { return numbers.first ?? 0 }

        var result = numbers.first ?? 0
        for j in 0..<ops.count {
            guard j + 1 < numbers.count else { break }
            let next = numbers[j + 1]
            result = ops[j] == "+" ? result + next : result - next
        }

        return result
    }

    private func hapticFeedback() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }

    private func loadDefaults() {
        selectedCategory = UserDefaults.standard.string(forKey: Constants.Bookkeeping.lastCategoryKey)
    }

    private func saveAndDismiss() {
        let amount = computedTotal
        guard amount > 0 else { return }

        let category = selectedCategory ?? (isTransfer ? "transfer" : "other")
        _ = BookkeepingTransaction(
            context: viewContext,
            amount: amount,
            categoryKey: category,
            subcategoryKey: nil,
            note: note.isEmpty ? nil : note,
            date: date,
            isIncome: isIncome,
            fundAccountKey: nil,
            notInBudget: notInBudget,
            billSource: nil,
            merchantName: nil
        )

        guard let error = PersistenceSaveCoordinator.save(viewContext) else {
            UserDefaults.standard.set(category, forKey: Constants.Bookkeeping.lastCategoryKey)
            amountString = ""
            note = ""
            hapticFeedback()
            return
        }
        saveErrorMessage = error
    }

    // MARK: - Today Summary Card

    // MARK: - Transaction Row

    private func transactionRow(_ transaction: BookkeepingTransaction) -> some View {
        HStack(spacing: 12) {
            Text(transaction.categoryEmoji)
                .font(.system(size: 20))
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.categoryName)
                    .font(.subheadline.weight(.medium))
                if let note = transaction.note, !note.isEmpty {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Text(transaction.amountDisplayText)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(
                    transaction.kind == .income
                        ? Color.profitGreen
                        : (transaction.kind == .transfer ? Color.secondary : Color.warmCoral)
                )
        }
        .padding(.vertical, 11)
    }
}

#Preview {
    BookkeepingTabView()
        .environmentObject(AppRouter())
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
