import SwiftUI
import CoreData

struct BudgetManagementView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var viewModel = BookkeepingViewModel()

    @State private var showAddBudgetSheet = false
    @State private var newCategoryKey = ""
    @State private var newAmount = ""
    @State private var saveErrorMessage: String?

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

            // Total budget overview (circular progress)
            totalBudgetCard

            // Category budgets
            if !viewModel.budgetEntries.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("分类预算")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(.primary)
                        .padding(.horizontal)

                    ForEach(viewModel.budgetEntries, id: \.categoryKey) { entry in
                        if let cat = BookkeepingCategory.find(key: entry.categoryKey) {
                            warmBudgetRow(
                                emoji: cat.emoji,
                                name: cat.name,
                                color: cat.color,
                                spent: entry.spent,
                                budget: entry.budget
                            )
                            .padding(.horizontal)
                        }
                    }
                }
            }

            // Add budget button
            Button(action: {
                showAddBudgetSheet = true
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                    Text("设置分类预算")
                }
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(.warmTeal)
            }
            .padding(.horizontal)
        }
        .sheet(isPresented: $showAddBudgetSheet) {
            addBudgetSheet
        }
        .onAppear {
            viewModel.loadBudget(from: viewContext)
            viewModel.loadStatistics(from: viewContext)
        }
    }

    // MARK: - Total Budget Card

    private var totalBudgetCard: some View {
        VStack(spacing: 16) {
            HStack {
                Text("月度总预算")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundColor(.secondary)
                Spacer()
                Text(viewModel.totalBudget.currencyString)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
            }

            // Circular progress
            circularProgress(
                spent: viewModel.monthlyExpense,
                budget: viewModel.totalBudget
            )

            if viewModel.totalBudget > 0 {
                HStack {
                    Text("剩余日均可用")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(viewModel.dailyAverageRemaining.currencyString)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(viewModel.dailyAverageRemaining > 0 ? .profitGreen : .warmCoral)
                }
            }
        }
        .padding(20)
        .cardStyle()
        .padding(.horizontal)
    }

    // MARK: - Circular Progress

    private func circularProgress(spent: Double, budget: Double) -> some View {
        let progress = budget > 0 ? min(spent / budget, 1.0) : 0.0
        let color: Color = {
            let ratio = budget > 0 ? spent / budget : 0
            if ratio >= 1.0 { return Color.warmCoral }
            if ratio >= 0.8 { return Color.warningOrange }
            return Color.warmTeal
        }()

        return ZStack {
            // Background circle
            Circle()
                .stroke(Color.warmMintDark, lineWidth: 10)
                .frame(width: 100, height: 100)

            // Progress circle
            Circle()
                .trim(from: 0, to: CGFloat(progress))
                .stroke(color, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .frame(width: 100, height: 100)
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.5), value: progress)

            // Center text
            VStack(spacing: 2) {
                Text(String(format: "%.0f%%", progress * 100))
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                Text("已使用")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Warm Budget Row

    private func warmBudgetRow(emoji: String, name: String, color: Color, spent: Double, budget: Double) -> some View {
        let progress = budget > 0 ? min(spent / budget, 1.0) : 0.0
        let barColor: Color = {
            let ratio = budget > 0 ? spent / budget : 0
            if ratio >= 1.0 { return Color.warmCoral }
            if ratio >= 0.8 { return Color.warningOrange }
            return Color.warmTeal
        }()

        return VStack(spacing: 8) {
            HStack(spacing: 10) {
                Text(emoji)
                    .font(.system(size: 20))
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(color.opacity(0.5)))

                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(.primary)
                    Text("\(spent.currencyString) / \(budget.currencyString)")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundColor(.secondary)
                }

                Spacer()

                if spent > budget {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(Color.warmCoral)
                        .font(.system(size: 14))
                }
            }

            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.warmMint)
                        .frame(height: 6)
                        .cornerRadius(3)

                    Rectangle()
                        .fill(barColor)
                        .frame(width: geometry.size.width * CGFloat(progress), height: 6)
                        .cornerRadius(3)
                        .animation(.easeInOut(duration: 0.3), value: progress)
                }
            }
            .frame(height: 6)
        }
        .padding(14)
        .cardStyle()
    }

    // MARK: - Add Budget Sheet

    private var addBudgetSheet: some View {
        NavigationView {
            Form {
                Section(header: Text("选择分类")) {
                    Picker("分类", selection: $newCategoryKey) {
                        Text("请选择").tag("")
                        ForEach(BookkeepingCategory.expenseCategories) { cat in
                            Text("\(cat.emoji) \(cat.name)").tag(cat.key)
                        }
                    }
                }

                Section(header: Text("月度预算金额")) {
                    TextField("例如：2000", text: $newAmount)
                        .keyboardType(.decimalPad)
                }
            }
            .navigationTitle("添加预算")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        showAddBudgetSheet = false
                    }
                    .foregroundColor(.warmTeal)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") {
                        if saveBudget() {
                            showAddBudgetSheet = false
                        }
                    }
                    .foregroundColor(.warmTeal)
                    .disabled(newCategoryKey.isEmpty || Double(newAmount) == nil)
                }
            }
            .persistenceSaveErrorAlert($saveErrorMessage)
        }
    }

    // MARK: - Actions

    private func changeMonth(_ offset: Int) {
        let calendar = Calendar.current
        if let newMonth = calendar.date(byAdding: .month, value: offset, to: viewModel.selectedMonth) {
            viewModel.selectedMonth = newMonth
            viewModel.loadBudget(from: viewContext)
            viewModel.loadStatistics(from: viewContext)
        }
    }

    private func saveBudget() -> Bool {
        guard let amount = Double(newAmount), !newCategoryKey.isEmpty else { return false }

        let month = viewModel.selectedMonth.startOfMonth

        let request: NSFetchRequest<BudgetEntry> = BudgetEntry.fetchRequest()
        request.predicate = NSPredicate(
            format: "categoryKey == %@ AND month == %@",
            newCategoryKey,
            month as NSDate
        )

        do {
            let existing = try viewContext.fetch(request)
            if let entry = existing.first {
                entry.monthlyAmount = amount
            } else {
                _ = BudgetEntry(
                    context: viewContext,
                    categoryKey: newCategoryKey,
                    monthlyAmount: amount,
                    month: month
                )
            }
        } catch {
            viewContext.rollback()
            saveErrorMessage = error.localizedDescription
            return false
        }

        guard let error = PersistenceSaveCoordinator.save(viewContext) else {
            viewModel.loadBudget(from: viewContext)
            newCategoryKey = ""
            newAmount = ""
            return true
        }
        saveErrorMessage = error
        return false
    }
}

#Preview {
    BudgetManagementView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
