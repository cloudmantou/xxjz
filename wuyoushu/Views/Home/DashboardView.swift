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
    @State private var saveErrorMessage: String?
    @Namespace private var dayNamespace

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
        allDayTransactions.filter(\.contributesToExpense).reduce(0) { $0 + $1.normalizedAmount }
    }
    private var dayIncome: Double {
        allDayTransactions.filter(\.contributesToIncome).reduce(0) { $0 + $1.normalizedAmount }
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
        .persistenceSaveErrorAlert($saveErrorMessage)
    }

    private func deleteTransaction(_ tx: BookkeepingTransaction) {
        viewContext.delete(tx)
        saveErrorMessage = PersistenceSaveCoordinator.save(viewContext)
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
        Color.appPageBackground
    }

    // MARK: - Header
    private var topHeroSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(headerOverline)
                        .font(.dsOverline)
                        .foregroundStyle(Color.textTertiary)
                    Text(router.isViewingToday ? "今天" : router.selectedReceiptDate.formatted(as: "M月d日"))
                        .font(.dsLargeTitle)
                        .foregroundStyle(Color.textPrimary)
                }

                Spacer()

                HStack(spacing: DS.Space.xs) {
                    if !router.isViewingToday {
                        Button {
                            Haptics.selection()
                            withAnimation(DS.Motion.snappy) { router.goToToday() }
                        } label: {
                            Text("回到今天")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color.brandPrimary500)
                                .padding(.horizontal, 12)
                                .frame(height: 34)
                                .background(Capsule().fill(Color.brandPrimary500.opacity(0.12)))
                        }
                        .buttonStyle(.pressable)
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                    }

                    DSIconButton(systemName: "calendar", size: 36) {
                        showDatePicker = true
                    }
                }
            }

            weekStrip

            daySummary
        }
        .padding(.horizontal, pageHorizontalPadding)
        .padding(.top, DS.Space.xs)
        .padding(.bottom, DS.Space.s)
        .animation(DS.Motion.snappy, value: router.isViewingToday)
    }

    private var headerOverline: String {
        let weekday = router.selectedReceiptDate.formatted(as: "EEEE")
        return "默认账本 · \(weekday)"
    }

    // MARK: - Week Strip

    private var weekDays: [Date] {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        let selected = router.selectedReceiptDate.startOfDay
        let weekday = calendar.component(.weekday, from: selected)
        let offset = (weekday - calendar.firstWeekday + 7) % 7
        guard let monday = calendar.date(byAdding: .day, value: -offset, to: selected) else { return [selected] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: monday) }
    }

    private var weekStrip: some View {
        HStack(spacing: 4) {
            ForEach(weekDays, id: \.self) { day in
                dayCell(day)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.appCardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.borderSoft, lineWidth: 0.8)
                )
        )
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    guard abs(value.translation.width) > abs(value.translation.height),
                          abs(value.translation.width) > 40 else { return }
                    shiftWeek(value.translation.width < 0 ? 1 : -1)
                }
        )
    }

    private func dayCell(_ day: Date) -> some View {
        let calendar = Calendar.current
        let isSelected = calendar.isDate(day, inSameDayAs: router.selectedReceiptDate)
        let isToday = calendar.isDateInToday(day)
        let isFuture = day.startOfDay > Date().startOfDay

        return Button {
            guard !isSelected else { return }
            Haptics.selection()
            withAnimation(DS.Motion.snappy) {
                router.selectedReceiptDate = day
            }
        } label: {
            VStack(spacing: 4) {
                Text(day.formatted(as: "EEEEE"))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.8) : Color.textTertiary)
                Text(day.formatted(as: "d"))
                    .font(.dsAmount(16, weight: isSelected ? .bold : .semibold))
                    .foregroundStyle(isSelected ? Color.white : (isFuture ? Color.textTertiary : Color.textPrimary))
                Circle()
                    .fill(isSelected ? Color.white : Color.brandPrimary500)
                    .frame(width: 4, height: 4)
                    .opacity(isToday ? 1 : 0)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.brandPrimary500)
                        .matchedGeometryEffect(id: "selectedDay", in: dayNamespace)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle(scale: 0.92))
        .accessibilityLabel(day.formatted(as: "M月d日 EEEE"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func shiftWeek(_ direction: Int) {
        guard let target = Calendar.current.date(byAdding: .day, value: 7 * direction, to: router.selectedReceiptDate) else { return }
        Haptics.soft()
        withAnimation(DS.Motion.smooth) {
            router.selectedReceiptDate = target
        }
    }

    // MARK: - Day Summary

    private var daySummary: some View {
        HStack(spacing: 0) {
            summaryItem(title: "支出", value: dayExpense, color: .textPrimary)
            Rectangle()
                .fill(Color.borderSoft)
                .frame(width: 1, height: 28)
            summaryItem(title: "收入", value: dayIncome, color: .incomeGreen)
            Rectangle()
                .fill(Color.borderSoft)
                .frame(width: 1, height: 28)
            summaryItem(title: "笔数", text: "\(allDayTransactions.count)", color: .textPrimary)
        }
        .padding(.vertical, 2)
    }

    private func summaryItem(title: String, value: Double? = nil, text: String? = nil, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.dsCaption)
                .foregroundStyle(Color.textSecondary)
            Text(text ?? String(format: "¥%.2f", value ?? 0))
                .font(.dsAmount(17, weight: .semibold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
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
                .tint(.brandPrimary500)
                .padding(.horizontal, 8)

                Button {
                    Haptics.selection()
                    selectedDate = Date()
                } label: {
                    Text("回到今天")
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, 20)

                Spacer()
            }
            .navigationTitle("选择日期")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.brandPrimary500)
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
