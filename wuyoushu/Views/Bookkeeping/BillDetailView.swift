import SwiftUI
import CoreData

/// 账单详情 / 编辑页 — 默认直编
/// 支持修改金额、类目、备注、日期、资金账户、预算标记、来源
/// 支持删除和退款（按原单方向反向冲销）
@MainActor
struct BillDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext

    let transactionID: NSManagedObjectID

    @State private var transaction: BookkeepingTransaction?

    @State private var editAmount: String = ""
    @State private var editNote: String = ""
    @State private var editDate: Date = Date()
    @State private var editIsIncome: Bool = false
    @State private var editCategoryKey: String = ""
    @State private var editFundAccountKey: String = ""
    @State private var editNotInBudget: Bool = false
    @State private var editBillSource: String = ""

    @State private var showDeleteConfirm = false
    @State private var showRefundConfirm = false
    @State private var isCommitting = false
    @State private var saveErrorMessage: String?

    private var categoryEmoji: String {
        BookkeepingCategory.find(key: editCategoryKey)?.emoji ?? "📦"
    }

    private var fundAccountEmoji: String {
        guard !editFundAccountKey.isEmpty else { return "💰" }
        return FundAccount.find(key: editFundAccountKey)?.emoji ?? "💰"
    }

    private var editableCategories: [BookkeepingCategory] {
        editIsIncome ? BookkeepingCategory.incomeCategories : BookkeepingCategory.expenseCategories
    }

    private var canSave: Bool {
        guard transaction != nil else { return false }
        guard let amount = Double(editAmount) else { return false }
        return amount > 0 && !isCommitting
    }

    var body: some View {
        Group {
            if transaction != nil {
                ScrollView {
                    VStack(spacing: 0) {
                        headerCard
                            .padding(.horizontal, 16)
                            .padding(.top, 12)

                        detailList
                            .padding(.top, 16)

                        actionButtons
                            .padding(.top, 24)
                            .padding(.bottom, 40)
                    }
                }
            } else {
                missingRecordState
            }
        }
        .background(Color.appPageBackground)
        .navigationTitle("账单详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("关闭") { dismiss() }
                    .disabled(isCommitting)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("保存") { saveChanges() }
                    .font(.body.weight(.semibold))
                    .disabled(!canSave)
            }
        }
        .confirmationDialog("确定删除这条记录？", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("删除", role: .destructive) { deleteTransaction() }
        }
        .confirmationDialog("生成退款冲销记录？", isPresented: $showRefundConfirm, titleVisibility: .visible) {
            Button("退款", role: .destructive) { createRefund() }
        }
        .persistenceSaveErrorAlert($saveErrorMessage)
        .onAppear { loadTransaction() }
    }

    // MARK: - States

    private var missingRecordState: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("记录不存在或已删除")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.primary)
            Text("请返回列表后重试")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
    }

    // MARK: - Header

    private var headerCard: some View {
        VStack(spacing: 12) {
            Text(categoryEmoji)
                .font(.system(size: 40))

            HStack(spacing: 4) {
                Text("¥")
                    .font(.system(size: 28, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                TextField("0.00", text: $editAmount)
                    .font(.system(size: 36, weight: .black, design: .rounded))
                    .multilineTextAlignment(.center)
                    .keyboardType(.decimalPad)
            }
            .foregroundStyle(editIsIncome ? Color.profitGreen : .primary)

            HStack(spacing: 8) {
                typeToggleButton(label: "支出", active: !editIsIncome)
                    .onTapGesture { switchIncome(false) }
                typeToggleButton(label: "收入", active: editIsIncome)
                    .onTapGesture { switchIncome(true) }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.appCardBackground)
        )
    }

    private func typeToggleButton(label: String, active: Bool) -> some View {
        Text(label)
            .font(.system(size: 14, weight: active ? .bold : .medium))
            .foregroundStyle(active ? .white : .secondary)
            .padding(.horizontal, 20)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(active ? Color.warmTeal : Color(UIColor.secondarySystemFill))
            )
    }

    // MARK: - Detail List

    private var detailList: some View {
        VStack(spacing: 0) {
            categoryPickerRow
            editNoteRow
            editDateRow
            fundAccountPickerRow
            toggleRow(icon: "🎯", label: "不计入预算", isOn: $editNotInBudget)
            editSourceRow

            if let transaction {
                detailRow(icon: "🆔", label: "账单ID", value: transaction.id.uuidString.prefix(8).description + "…")
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.appCardBackground)
        )
        .padding(.horizontal, 16)
    }

    private func detailRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 12) {
            Text(icon)
                .font(.system(size: 18))
                .frame(width: 28)

            Text(label)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .overlay(alignment: .bottom) {
            Divider().padding(.leading, 56)
        }
    }

    private var editNoteRow: some View {
        HStack(spacing: 12) {
            Text("📝")
                .font(.system(size: 18))
                .frame(width: 28)
            Text("备注")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            Spacer()
            TextField("添加备注", text: $editNote)
                .font(.system(size: 14))
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .overlay(alignment: .bottom) {
            Divider().padding(.leading, 56)
        }
    }

    private var editDateRow: some View {
        HStack(spacing: 12) {
            Text("📅")
                .font(.system(size: 18))
                .frame(width: 28)
            Text("日期")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            Spacer()
            DatePicker("", selection: $editDate, displayedComponents: [.date, .hourAndMinute])
                .labelsHidden()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) {
            Divider().padding(.leading, 56)
        }
    }

    private var categoryPickerRow: some View {
        HStack(spacing: 12) {
            Text(categoryEmoji)
                .font(.system(size: 18))
                .frame(width: 28)
            Text("类目")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            Spacer()
            Picker("类目", selection: $editCategoryKey) {
                ForEach(editableCategories, id: \.key) { category in
                    Text("\(category.emoji) \(category.localizedName)")
                        .tag(category.key)
                }
            }
            .pickerStyle(.menu)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) {
            Divider().padding(.leading, 56)
        }
    }

    private var fundAccountPickerRow: some View {
        HStack(spacing: 12) {
            Text(fundAccountEmoji)
                .font(.system(size: 18))
                .frame(width: 28)
            Text("资金账户")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            Spacer()
            Picker("资金账户", selection: $editFundAccountKey) {
                Text("未设置").tag("")
                ForEach(FundAccount.all, id: \.key) { account in
                    Text("\(account.emoji) \(account.name)").tag(account.key)
                }
            }
            .pickerStyle(.menu)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) {
            Divider().padding(.leading, 56)
        }
    }

    private var editSourceRow: some View {
        HStack(spacing: 12) {
            Text("📱")
                .font(.system(size: 18))
                .frame(width: 28)
            Text("来源")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            Spacer()
            TextField("手动录入", text: $editBillSource)
                .font(.system(size: 14))
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .overlay(alignment: .bottom) {
            Divider().padding(.leading, 56)
        }
    }

    private func toggleRow(icon: String, label: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            Text(icon)
                .font(.system(size: 18))
                .frame(width: 28)
            Text(label)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) {
            Divider().padding(.leading, 56)
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button(action: { showRefundConfirm = true }) {
                HStack {
                    Image(systemName: "arrow.uturn.backward")
                    Text("退款冲销")
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(hex: "E67E22"))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(hex: "E67E22").opacity(0.1))
                )
            }
            .disabled(isCommitting || transaction == nil)

            Button(action: { showDeleteConfirm = true }) {
                HStack {
                    Image(systemName: "trash")
                    Text("删除记录")
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(hex: "E94C57"))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(hex: "E94C57").opacity(0.1))
                )
            }
            .disabled(isCommitting || transaction == nil)
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Actions

    private func loadTransaction() {
        do {
            guard let fetched = try viewContext.existingObject(with: transactionID) as? BookkeepingTransaction else {
                transaction = nil
                return
            }
            transaction = fetched

            editAmount = String(format: "%.2f", fetched.normalizedAmount)
            editNote = fetched.note ?? ""
            editDate = fetched.date
            editIsIncome = fetched.isIncome
            editCategoryKey = fetched.categoryKey
            editFundAccountKey = fetched.fundAccountKey ?? ""
            editNotInBudget = fetched.notInBudget
            editBillSource = fetched.billSource ?? ""

            if editCategoryKey.isEmpty {
                editCategoryKey = editableCategories.first?.key ?? ""
            }
        } catch {
            transaction = nil
            print("[BillDetailView] load failed: \(error)")
        }
    }

    private func switchIncome(_ income: Bool) {
        guard !isCommitting else { return }
        editIsIncome = income
        if !editableCategories.contains(where: { $0.key == editCategoryKey }) {
            editCategoryKey = editableCategories.first?.key ?? ""
        }
    }

    private func saveChanges() {
        guard let transaction, let amount = Double(editAmount), amount > 0 else { return }
        guard !isCommitting else { return }

        isCommitting = true

        transaction.amount = amount
        transaction.note = editNote.isEmpty ? nil : editNote
        transaction.date = editDate
        transaction.isIncome = editIsIncome
        transaction.categoryKey = editCategoryKey
        transaction.fundAccountKey = editFundAccountKey.isEmpty ? nil : editFundAccountKey
        transaction.notInBudget = editNotInBudget
        transaction.billSource = editBillSource.isEmpty ? nil : editBillSource

        saveErrorMessage = PersistenceSaveCoordinator.save(viewContext)
        isCommitting = false
    }

    private func deleteTransaction() {
        guard let transaction else { return }
        guard !isCommitting else { return }

        isCommitting = true
        viewContext.delete(transaction)

        if let error = PersistenceSaveCoordinator.save(viewContext) {
            saveErrorMessage = error
            isCommitting = false
            return
        }
        self.transaction = nil
        dismiss()
    }

    private func createRefund() {
        guard let transaction else { return }
        guard !isCommitting else { return }

        isCommitting = true

        let originalID = transaction.id.uuidString
        let reversedIncome = !transaction.isIncome
        _ = BookkeepingTransaction(
            context: viewContext,
            amount: transaction.normalizedAmount,
            categoryKey: transaction.categoryKey,
            note: "退款冲销(原单\(String(originalID.prefix(8)))): \(transaction.note ?? transaction.categoryName)",
            date: Date(),
            isIncome: reversedIncome,
            fundAccountKey: transaction.fundAccountKey,
            notInBudget: transaction.notInBudget,
            billSource: "refund_of:\(originalID)",
            merchantName: transaction.merchantName
        )

        if let error = PersistenceSaveCoordinator.save(viewContext) {
            saveErrorMessage = error
            isCommitting = false
            return
        }
        dismiss()
    }
}
