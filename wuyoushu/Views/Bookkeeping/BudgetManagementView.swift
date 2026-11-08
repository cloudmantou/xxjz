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
        ScrollView {
            VStack(spacing: 16) {
                // Month navigator
                HStack {
                    Button(action: { changeMonth(-1) }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.warmTeal)
                            .frame(width: 34, height: 34)
                            .background(Color.warmTeal.opacity(0.12))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Text(viewModel.selectedMonth.monthYearString)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)

                    Spacer()

                    Button(action: { changeMonth(1) }) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.warmTeal)
                            .frame(width: 34, height: 34)
                            .background(Color.warmTeal.opacity(0.12))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                // Total budget overview
                totalBudgetCard

                // Category budgets
                if !viewModel.budgetEntries.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("分类预算")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundColor(.primary)
                            .padding(.horizontal, 16)

                        ForEach(viewModel.budgetEntries, id: \.categoryKey) { entry in
                            if let cat = BookkeepingCategory.find(key: entry.categoryKey) {
                                warmBudgetRow(
                                    emoji: cat.emoji,
                                    name: cat.name,
                                    color: cat.color,
                                    spent: entry.spent,
                                    budget: entry.budget
                                )
                                .padding(.horizontal, 16)
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
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(.warmTeal)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.warmTeal.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
        .background(Color.appPageBackground)
        .navigationTitle("预算管理")
        .navigationBarTitleDisplayMode(.inline)
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
            if ratio >= 1.0 { return Color.lossRed }
            if ratio >= 0.8 { return Color.warningOrange }
            return Color.warmTeal
        }()

        return ZStack {
            // Background track
            Circle()
                .stroke(Color.secondary.opacity(0.12), lineWidth: 8)
                .frame(width: 96, height: 96)

            // Progress circle
            Circle()
                .trim(from: 0, to: CGFloat(progress))
                .stroke(
                    LinearGradient(
                        colors: [color, color.opacity(0.85)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .frame(width: 96, height: 96)
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.5), value: progress)

            // Center text
            VStack(spacing: 2) {
                Text(String(format: "%.0f%%", progress * 100))
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.primary)
                Text("已使用")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Warm Budget Row

    private func warmBudgetRow(emoji: String, name: String, color: Color, spent: Double, budget: Double) -> some View {
        let progress = budget > 0 ? min(spent / budget, 1.0) : 0.0
        let barColor: Color = {
            let ratio = budget > 0 ? spent / budget : 0
            if ratio >= 1.0 { return Color.lossRed }
            if ratio >= 0.8 { return Color.warningOrange }
            return Color.warmTeal
        }()

        return VStack(spacing: 10) {
            HStack(spacing: 10) {
                Text(emoji)
                    .font(.system(size: 18))
                    .frame(width: 36, height: 36)
                    .background(Color.appPillBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(.primary)
                    Text("\(spent.currencyString) / \(budget.currencyString)")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }

                Spacer()

                if spent > budget {
                    HStack(spacing: 3) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                        Text("超支")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(Color.lossRed)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.lossRed.opacity(0.12))
                    .clipShape(Capsule())
                }
            }

            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.1))
                        .frame(height: 6)

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [barColor, barColor.opacity(0.85)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width * CGFloat(progress), height: 6)
                        .animation(.easeInOut(duration: 0.35), value: progress)
                }
            }
            .frame(height: 6)
        }
        .padding(14)
        .cardStyle(variant: .default, radius: CardRadius.medium)
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
