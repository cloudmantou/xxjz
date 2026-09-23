import SwiftUI
import CoreData

private struct TransactionDetailSheetItem: Identifiable {
    let objectID: NSManagedObjectID

    var id: URL { objectID.uriRepresentation() }
}

struct DashboardView: View {
    @EnvironmentObject private var router: AppRouter
    @Environment(\.managedObjectContext) private var viewContext
    @State private var showDatePicker = false
    @State private var detailSheetItem: TransactionDetailSheetItem?
    @State private var pendingDeleteTransaction: BookkeepingTransaction?
    @State private var showDeleteConfirm = false

    private var screenWidth: CGFloat {
        UIScreen.main.bounds.width
    }

    private var pageHorizontalPadding: CGFloat {
        Constants.Layout.pageHorizontalPadding(for: screenWidth)
    }

    /// Transactions for the selected receipt date (reactive to router.selectedReceiptDate).
    @FetchRequest private var dayTransactions: FetchedResults<BookkeepingTransaction>

    init() {
        let start = Date().startOfDay
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        _dayTransactions = FetchRequest(
            sortDescriptors: [
                NSSortDescriptor(keyPath: \BookkeepingTransaction.date, ascending: false),
                NSSortDescriptor(keyPath: \BookkeepingTransaction.createdAt, ascending: false)
            ],
            predicate: NSPredicate(format: "date >= %@ AND date < %@", start as NSDate, end as NSDate),
            animation: .default
        )
    }

    private var allDayTransactions: [BookkeepingTransaction] {
        dayTransactions.sorted { lhs, rhs in
            if lhs.date == rhs.date {
                return lhs.objectID.uriRepresentation().absoluteString > rhs.objectID.uriRepresentation().absoluteString
            }
            return lhs.date > rhs.date
        }
    }

    // MARK: - Computed Day Summary
    private var dayExpense: Double {
        allDayTransactions.filter { !$0.isIncome }.reduce(0) { $0 + $1.normalizedAmount }
    }
    private var dayIncome: Double {
        allDayTransactions.filter { $0.isIncome }.reduce(0) { $0 + $1.normalizedAmount }
    }

    var body: some View {
        NavigationView {
            ZStack {
                heroBackground
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    topHeroSection

                    PersistentReceiptView(
                        selectedDayTransactions: allDayTransactions,
                        isTodayContext: router.isViewingToday,
                        forcePrintTriggerID: router.receiptPrintTrigger,
                        forcePrintTargetURI: router.receiptPrintTargetURI,
                        onRowTap: { tx in
                            detailSheetItem = TransactionDetailSheetItem(objectID: tx.objectID)
                        },
                        onDeleteRow: { tx in
                            pendingDeleteTransaction = tx
                            showDeleteConfirm = true
                        }
                    )
                    .padding(.top, 2)
                    .layoutPriority(1)
                }
            }
            .navigationBarHidden(true)
        }
        .onChange(of: router.selectedReceiptDate) { newDate in
            updatePredicate(for: newDate)
        }
        .onAppear {
            updatePredicate(for: router.selectedReceiptDate)
        }
        .onChange(of: router.selectedTab) { newTab in
            if newTab == .home {
                router.goToToday()
            }
        }
        .sheet(isPresented: $showDatePicker) {
            DatePickerSheet(selectedDate: $router.selectedReceiptDate)
        }
        .sheet(item: $detailSheetItem) { item in
            NavigationView {
                BillDetailView(transactionID: item.objectID)
            }
        }
        .confirmationDialog("确定删除这条记录？", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                if let tx = pendingDeleteTransaction {
                    deleteTransaction(tx)
                }
            }
        }
    }

    private func deleteTransaction(_ tx: BookkeepingTransaction) {
        viewContext.delete(tx)
        do {
            try viewContext.save()
        } catch {
            print("[DashboardView] delete failed: \(error)")
        }
        pendingDeleteTransaction = nil
    }

    private func updatePredicate(for date: Date) {
        let start = date.startOfDay
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        dayTransactions.nsPredicate = NSPredicate(
            format: "date >= %@ AND date < %@",
            start as NSDate,
            end as NSDate
        )
    }

    // MARK: - Background
    private var heroBackground: some View {
        ZStack(alignment: .top) {
            Color.appPageBackground

            LinearGradient(
                colors: [Color.homeHeroGradientTop, Color.homeHeroGradientBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .frame(height: 290)
            .overlay(
                LinearGradient(
                    colors: [Color.clear, Color.appPageBackground],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }

    // MARK: - Hero Section（重设计版）
    private var topHeroSection: some View {
        VStack(spacing: 0) {
            // ── 顶部：账本标题 + 日期导航 ──
            HStack(alignment: .center) {
                // 左：账本名 + 切换
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Text("默认账本")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.82))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color.white.opacity(0.6))
                    }
                    Text(router.isViewingToday ? "今天" : router.selectedReceiptDate.formatted(as: "M月d日"))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.white)
                }

                Spacer()

                // 右：日期导航器
                homeDateNavigator
            }
            .padding(.horizontal, pageHorizontalPadding)
            .padding(.top, 12)
            .padding(.bottom, 10)
        }
    }

    // MARK: - Date Navigator
    private var homeDateNavigator: some View {
        HStack(spacing: 6) {
            Button(action: { router.goToPreviousDay() }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.9))
                    .frame(width: 30, height: 30)
                    .background(Color.white.opacity(0.18))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            Button(action: { showDatePicker = true }) {
                VStack(spacing: 1) {
                    Text(router.selectedReceiptDate.formatted(as: "dd"))
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundStyle(Color.white)
                    Text(router.selectedReceiptDate.formatted(as: "MM.dd"))
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.75))
                }
                .frame(width: 42, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.2))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.white.opacity(0.35), lineWidth: 0.5)
                        )
                )
            }
            .buttonStyle(.plain)

            Button(action: { router.goToNextDay() }) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.9))
                    .frame(width: 30, height: 30)
                    .background(Color.white.opacity(0.18))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .shadow(color: Color.black.opacity(0.1), radius: 4, y: 2)
    }

}

// MARK: - Date Picker Sheet

private struct DatePickerSheet: View {
    @Binding var selectedDate: Date
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                DatePicker(
                    "选择日期",
                    selection: $selectedDate,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .tint(.warmTeal)
                .padding(.horizontal, 8)

                Button(action: { selectedDate = Date() }) {
                    Text("回到今天")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(
                            LinearGradient(colors: [Color.heroGradientTop, Color.heroGradientBottom],
                                           startPoint: .leading, endPoint: .trailing)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: CardRadius.medium, style: .continuous))
                }
                .padding(.horizontal, 20)

                Spacer()
            }
            .navigationTitle("选择日期")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.warmTeal)
                }
            }
        }
    }
}

#Preview {
    DashboardView()
        .environmentObject(AppRouter())
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
