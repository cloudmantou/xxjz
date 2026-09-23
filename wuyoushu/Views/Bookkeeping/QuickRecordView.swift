import SwiftUI
import CoreData
import UIKit

enum TransactionType: String, CaseIterable {
    case expense
    case income
    case transfer
}

struct QuickRecordView: View {
    private static var lastPendingDebugSignature: String?

    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var router: AppRouter
    @ObservedObject private var customCategoryStore = CustomCategoryStore.shared

    @State private var amountString = ""
    @State private var selectedCategory: String?
    @State private var selectedSubcategory: String?
    @State private var note = ""
    @State private var date = Date()
    @State private var transactionType: TransactionType = .expense
    @State private var showDetails = false
    @State private var isRecognizingImage = false
    @State private var showAddCategory = false
    @State private var selectedFundAccount: String?
    @State private var notInBudget: Bool = false
    @State private var autoDetectedBillSource: BillSource = .unknown
    @State private var autoDetectedMerchantName: String?
    @State private var suppressTypeReset = false
    @State private var parsedCandidates: [ParsedTransactionCandidatePayload] = []
    @State private var selectedCandidateIDs: Set<String> = []
    @State private var showCandidateSheet = false
    @State private var showDatePickerOverlay = false
    @State private var isCommittingTransaction = false
    @State private var importedShortcutEventID: String?
    @State private var isShortcutImportedContext = false
    @State private var saveErrorMessage: String?

    @FocusState private var isNoteFocused: Bool

    private let showBackButton: Bool
    private let onDismiss: (() -> Void)?

    init(showBackButton: Bool = false, onDismiss: (() -> Void)? = nil) {
        self.showBackButton = showBackButton
        self.onDismiss = onDismiss
    }

    private var isIncome: Bool { transactionType == .income }
    private var isTransfer: Bool { transactionType == .transfer }

    private var screenWidth: CGFloat {
        sanitizedDimension(UIScreen.main.bounds.width, fallback: 390, lower: 320, upper: 1024)
    }

    private var layoutBucket: Constants.LayoutBucket {
        Constants.Layout.bucket(for: screenWidth)
    }

    private var categoryColumnCount: Int {
        Constants.Layout.categoryColumnCount(for: screenWidth)
    }

    private var categoryColumns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: layoutBucket == .legacyCompact ? 8 : 10),
            count: categoryColumnCount
        )
    }

    private var contentHorizontalPadding: CGFloat {
        Constants.Layout.pageHorizontalPadding(for: screenWidth)
    }

    private var categoryGridHorizontalPadding: CGFloat {
        contentHorizontalPadding
    }

    private var calculatorHorizontalPadding: CGFloat {
        sanitizedDimension(layoutBucket == .legacyCompact ? 8 : 10, fallback: 10, lower: 6, upper: 18)
    }

    private var categoryIconSize: CGFloat {
        sanitizedDimension(Constants.Layout.categoryIconSize(for: screenWidth), fallback: 48, lower: 36, upper: 64)
    }

    private var calculatorButtonHeight: CGFloat {
        sanitizedDimension(layoutBucket == .legacyCompact ? 48 : 54, fallback: 54, lower: 40, upper: 72)
    }

    private var typeToggleHeight: CGFloat {
        sanitizedDimension(Constants.Layout.typeToggleHeight(for: screenWidth), fallback: 40, lower: 32, upper: 56)
    }

    private var typeToggleCornerRadius: CGFloat {
        sanitizedDimension(layoutBucket == .legacyCompact ? 10 : 11, fallback: 10, lower: 8, upper: 16)
    }

    private var typeToggleFontSize: CGFloat {
        layoutBucket == .legacyCompact ? 11 : 12
    }

    private var categoryEmojiFontSize: CGFloat {
        switch layoutBucket {
        case .legacyCompact: return 22
        case .standard: return 24
        case .large: return 26
        case .max: return 28
        }
    }

    private var categoryLabelFontSize: CGFloat {
        layoutBucket == .legacyCompact ? 10 : 11
    }

    private var keypadNumberTextColor: Color {
        Color.primary
    }

    private var keypadSecondaryTextColor: Color {
        Color.secondary
    }

    private var keypadOperatorTextColor: Color {
        Color(hex: "#4cb7ae")
    }

    private var displayAmount: String {
        if amountString.isEmpty { return "0.00" }
        // Show the raw expression while typing
        // Evaluate for display if it ends with an operator, show current number
        let evaluated = evaluate(amountString)
        let safeValue = evaluated.isFinite ? evaluated : 0
        return String(format: "%.2f", safeValue)
    }

    private var computedTotal: Double {
        let evaluated = evaluate(amountString)
        return evaluated.isFinite ? evaluated : 0
    }

    private var safeDatePickerWidth: CGFloat {
        sanitizedDimension(screenWidth - 28, fallback: 332, lower: 260, upper: 360)
    }

    private func sanitizedDimension(_ value: CGFloat, fallback: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        guard value.isFinite else { return fallback }
        return min(max(value, lower), upper)
    }

    private var currentCategories: [BookkeepingCategory] {
        if isTransfer {
            return [BookkeepingCategory(key: "transfer", name: "转账", emoji: "↗️", colorHex: "546E7A", subcategories: [])]
        }
        let builtIn: [BookkeepingCategory] = isIncome ? BookkeepingCategory.incomeCategories : BookkeepingCategory.expenseCategories
        let customs: [BookkeepingCategory] = (isIncome ? customCategoryStore.incomeCategories : customCategoryStore.expenseCategories).map { $0.toBookkeepingCategory() }
        return builtIn + customs
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Type toggle: 支出 / 收入
                typeToggleSection
                    .padding(.horizontal, contentHorizontalPadding)
                    .padding(.top, 6)
                    .padding(.bottom, 4)

                // Category grid (vertical scroll, 4 columns) — hidden for transfer
                if isTransfer {
                    VStack(spacing: 6) {
                        Text("↗️")
                            .font(.system(size: 32))
                        Text("转账")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVGrid(columns: categoryColumns, spacing: 10) {
                            ForEach(currentCategories) { category in
                                categoryCell(category)
                            }
                            // Add custom category button
                            addCategoryButton
                        }
                        .padding(.horizontal, categoryGridHorizontalPadding)
                        .padding(.vertical, 6)
                    }
                    .frame(maxHeight: .infinity)
                }

                // Amount display area
                amountDisplayBar
                    .padding(.horizontal, contentHorizontalPadding)
                    .padding(.top, 6)
                    .padding(.bottom, 8)

                // Quick action row
                quickActionRow
                    .padding(.horizontal, contentHorizontalPadding)
                    .padding(.bottom, 6)

                // Calculator keyboard (系统键盘优先：备注聚焦时隐藏)
                if !isNoteFocused {
                    calculatorSection
                        .padding(.horizontal, calculatorHorizontalPadding)
                        .padding(.bottom, 8)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: isNoteFocused)
            .background(Color.appPageBackground)

            if showDatePickerOverlay {
                datePickerOverlay
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .zIndex(10)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("记一笔")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.primary)
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                if showBackButton {
                    Button(action: handleDismiss) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                    }
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完成") {
                    isNoteFocused = false
                }
            }
        }
        .onAppear {
            loadDefaults()
            loadPendingParams()
        }
        .sheet(isPresented: $showDetails) {
            RecordDetailsView(
                note: $note,
                date: $date,
                transactionType: $transactionType,
                selectedCategory: $selectedCategory,
                selectedSubcategory: $selectedSubcategory
            )
        }
        .sheet(isPresented: $showAddCategory) {
            CustomCategoryFormView(
                store: customCategoryStore,
                isIncome: isIncome,
                existingCategory: nil
            )
        }
        .sheet(isPresented: $showCandidateSheet) {
            candidateSelectionSheet
        }
        .persistenceSaveErrorAlert($saveErrorMessage)
        .onChange(of: transactionType) { _ in
            guard !suppressTypeReset else { return }
            selectedCategory = nil
            selectedSubcategory = nil
            if isTransfer {
                selectedCategory = "transfer"
            }
        }
    }

    // MARK: - Type Toggle (支出 / 收入 / 转账)

    @Namespace private var typeToggleNamespace

    private var typeToggleSection: some View {
        HStack(spacing: 0) {
            typeButton(title: "支出", type: .expense)
            typeButton(title: "收入", type: .income)
            typeButton(title: "转账", type: .transfer)
        }
        .frame(height: typeToggleHeight)
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: typeToggleCornerRadius, style: .continuous)
                .fill(Color.appCardMutedBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: typeToggleCornerRadius, style: .continuous)
                        .stroke(Color.borderSoft, lineWidth: 0.8)
                )
        )
    }

    private func typeButton(title: String, type: TransactionType) -> some View {
        let isSelected = transactionType == type
        return Button(action: {
            isNoteFocused = false
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                transactionType = type
            }
        }) {
            ZStack {
                if isSelected {
                    RoundedRectangle(cornerRadius: max(typeToggleCornerRadius - 2, 8), style: .continuous)
                        .fill(Color.warmTeal)
                        .overlay(
                            RoundedRectangle(cornerRadius: max(typeToggleCornerRadius - 2, 8), style: .continuous)
                                .stroke(Color.warmTeal.opacity(0.35), lineWidth: 1)
                        )
                        .matchedGeometryEffect(id: "typeToggle", in: typeToggleNamespace)
                }
                Text(title)
                    .font(.system(size: typeToggleFontSize, weight: .medium))
                    .foregroundColor(isSelected ? .white : Color.primary)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Category Grid (4 columns, vertical scroll)

    private func categoryCell(_ category: BookkeepingCategory) -> some View {
        let isSelected = selectedCategory == category.key
        return Button(action: {
            isNoteFocused = false
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedCategory = category.key
                selectedSubcategory = nil
            }
            hapticFeedback()
        }) {
            VStack(spacing: 5) {
                Text(category.emoji)
                    .font(.system(size: categoryEmojiFontSize))
                    .frame(width: categoryIconSize, height: categoryIconSize)
                    .background(
                        Circle()
                            .fill(Color(hex: category.colorHex))
                    )
                    .overlay(
                        Circle()
                            .stroke(isSelected ? Color.warmTeal : Color.clear, lineWidth: 2.5)
                    )
                    .shadow(color: isSelected ? Color.warmTeal.opacity(0.3) : Color.clear, radius: 4, y: 2)
                Text(category.localizedName)
                    .font(.system(size: categoryLabelFontSize, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? Color.warmTeal : .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Add Category Button

    private var addCategoryButton: some View {
        Button(action: {
            isNoteFocused = false
            showAddCategory = true
        }) {
            VStack(spacing: 5) {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .medium))
                    .frame(width: categoryIconSize, height: categoryIconSize)
                    .background(
                        Circle()
                            .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [4]))
                            .foregroundColor(Color.secondary)
                    )
                Text("自定义")
                    .font(.system(size: categoryLabelFontSize))
                    .foregroundColor(Color.secondary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Amount Display Bar

    private var amountDisplayBar: some View {
        HStack(spacing: 10) {
            // Camera icon
            Button(action: {}) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.secondary)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color(.tertiarySystemGroupedBackground)))
            }
            .buttonStyle(.plain)

            TextField("备注（自动识别或手动输入）", text: $note)
                .font(.system(size: 16))
                .foregroundColor(.primary)
                .submitLabel(.done)
                .lineLimit(1)
                .focused($isNoteFocused)
                .onSubmit { isNoteFocused = false }
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

    // MARK: - Quick Action Row

    private var quickActionRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if isRecognizingImage {
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.75)
                        Text("识别截图中…")
                            .font(.system(size: 12))
                    }
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color(.tertiarySystemGroupedBackground))
                    .cornerRadius(14)
                }

                quickActionChip(icon: "calendar", title: dateText) {
                    isNoteFocused = false
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showDatePickerOverlay = true
                    }
                }
                if let cat = selectedCategory, let catObj = BookkeepingCategory.find(key: cat) {
                    quickActionChip(icon: nil, title: catObj.localizedName) {
                        isNoteFocused = false
                        showDetails = true
                    }
                }
                // Budget toggle
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

    private var datePickerOverlay: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showDatePickerOverlay = false
                    }
                }

            VStack(spacing: 12) {
                HStack {
                    Text("选择日期")
                        .font(.system(size: 17, weight: .semibold))
                    Spacer()
                    Button("今天") {
                        date = Date()
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.warmTeal)
                }

                DatePicker(
                    "",
                    selection: $date,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .labelsHidden()
                .tint(.warmTeal)

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showDatePickerOverlay = false
                    }
                } label: {
                    Text("确认")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.warmTeal)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .frame(maxWidth: safeDatePickerWidth)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.appCardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.borderSoft, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.12), radius: 18, y: 8)
            .padding(.horizontal, 14)
        }
    }

    private var dateText: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return L10n.tr("今天") }
        if calendar.isDateInYesterday(date) { return L10n.tr("昨天") }
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

    // MARK: - Calculator Keyboard

    private var calculatorSection: some View {
        VStack(spacing: 6) {
            // Row 1: 1, 2, 3, ⌫
            HStack(spacing: 6) {
                calcDigitButton("1")
                calcDigitButton("2")
                calcDigitButton("3")
                calcActionButton("⌫", color: .secondary) {
                    if !amountString.isEmpty { amountString.removeLast() }
                }
            }

            // Row 2: 4, 5, 6, +
            HStack(spacing: 6) {
                calcDigitButton("4")
                calcDigitButton("5")
                calcDigitButton("6")
                calcOperatorButton("+")
            }

            // Row 3: 7, 8, 9, −
            HStack(spacing: 6) {
                calcDigitButton("7")
                calcDigitButton("8")
                calcDigitButton("9")
                calcOperatorButton("−")
            }

            // Row 4: ., 0, 完成
            HStack(spacing: 6) {
                calcDecimalButton()
                calcDigitButton("0")
                calcSaveButton()
            }
        }
    }

    // MARK: - Calculator Buttons

    private func calcDigitButton(_ digit: String) -> some View {
        Button(action: {
            isNoteFocused = false
            hapticFeedback()
            appendDigit(digit)
        }) {
            Text(digit)
                .font(.system(size: 22, weight: .medium, design: .rounded))
                .frame(maxWidth: .infinity, minHeight: calculatorButtonHeight, maxHeight: calculatorButtonHeight)
                .background(Color.appCardMutedBackground)
                .foregroundColor(keypadNumberTextColor)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: Color.black.opacity(0.04), radius: 2, y: 1)
        }
        .buttonStyle(.plain)
    }

    private func calcDecimalButton() -> some View {
        Button(action: {
            isNoteFocused = false
            hapticFeedback()
            if !amountString.contains(".") && !amountString.isEmpty {
                amountString += "."
            }
        }) {
            Text(".")
                .font(.system(size: 22, weight: .medium, design: .rounded))
                .frame(maxWidth: .infinity, minHeight: calculatorButtonHeight, maxHeight: calculatorButtonHeight)
                .background(Color.appCardMutedBackground)
                .foregroundColor(keypadNumberTextColor)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: Color.black.opacity(0.04), radius: 2, y: 1)
        }
        .buttonStyle(.plain)
    }

    private func calcOperatorButton(_ op: String) -> some View {
        Button(action: {
            isNoteFocused = false
            hapticFeedback()
            appendOperator(op)
        }) {
            Text(op)
                .font(.system(size: 22, weight: .medium, design: .rounded))
                .frame(maxWidth: .infinity, minHeight: calculatorButtonHeight, maxHeight: calculatorButtonHeight)
                .background(Color.warmTeal.opacity(0.1))
                .foregroundColor(keypadOperatorTextColor)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func calcActionButton(_ label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: {
            isNoteFocused = false
            hapticFeedback()
            action()
        }) {
            Text(label)
                .font(.system(size: 18, weight: .medium, design: .rounded))
                .frame(maxWidth: .infinity, minHeight: calculatorButtonHeight, maxHeight: calculatorButtonHeight)
                .background(Color(.tertiarySystemGroupedBackground))
                .foregroundColor(colorScheme == .dark ? keypadSecondaryTextColor : color)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func calcSaveButton() -> some View {
        let canSave = computedTotal > 0 && !isCommittingTransaction
        return Button(action: {
            isNoteFocused = false
            saveAndDismiss()
        }) {
            ZStack {
                if canSave {
                    LinearGradient(
                        colors: [Color.heroGradientTop, Color.heroGradientBottom],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.tertiarySystemGroupedBackground))
                }

                Text(isCommittingTransaction ? "保存中..." : "完成")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundColor(canSave ? .white : Color(.quaternaryLabel))
            }
            .frame(maxWidth: .infinity, minHeight: calculatorButtonHeight, maxHeight: calculatorButtonHeight)
            .shadow(color: canSave ? Color.heroGradientBottom.opacity(0.3) : .clear, radius: 6, y: 3)
        }
        .buttonStyle(.plain)
        .disabled(!canSave)
    }

    // MARK: - Helpers

    private func appendDigit(_ digit: String) {
        // Get the current number segment (after last operator)
        let operators = CharacterSet(charactersIn: "+−×÷")
        let lastOpIndex = amountString.lastIndex(where: { char in
            String(char).rangeOfCharacter(from: operators) != nil
        })
        let currentSegment = lastOpIndex.map { String(amountString[amountString.index(after: $0)...]) } ?? amountString
        let newSegment = currentSegment + digit

        // Limit digits
        let parts = newSegment.components(separatedBy: ".")
        if let intPart = parts.first, intPart.count > Constants.Bookkeeping.maxAmountDigits { return }
        if parts.count > 1, parts[1].count > 2 { return }

        amountString += digit
    }

    private func appendOperator(_ op: String) {
        guard !amountString.isEmpty else { return }
        // If last char is already an operator, replace it
        let operators = CharacterSet(charactersIn: "+−×÷")
        if let last = amountString.last, String(last).rangeOfCharacter(from: operators) != nil {
            amountString.removeLast()
        }
        amountString += op
    }

    /// Evaluate a math expression like "1000+500−200×3÷2"
    private func evaluate(_ expr: String) -> Double {
        guard !expr.isEmpty else { return 0 }

        // Tokenize
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

        // If starts with operator or first token isn't a number
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

        // Process × and ÷ first (higher precedence)
        var i = 0
        while i < ops.count {
            if ops[i] == "×" || ops[i] == "÷" {
                let left = numbers[i]
                let right = numbers[i + 1]
                let result = ops[i] == "×" ? left * right : (right != 0 ? left / right : 0)
                numbers[i] = result
                numbers.remove(at: i + 1)
                ops.remove(at: i)
            } else {
                i += 1
            }
        }

        // Process + and −
        var result = numbers.first ?? 0
        for j in 0..<ops.count {
            guard j + 1 < numbers.count else { break }
            let next = numbers[j + 1]
            result = ops[j] == "+" ? result + next : result - next
        }

        return result
    }

    // MARK: - Candidate Selection

    @ViewBuilder
    private var candidateSelectionSheet: some View {
        NavigationView {
            VStack(spacing: 0) {
                if parsedCandidates.isEmpty {
                    EmptyStateView(
                        icon: "list.bullet.rectangle",
                        title: "暂无候选",
                        message: "请返回继续识别截图"
                    )
                    .padding(.top, 40)
                } else {
                    List {
                        ForEach(parsedCandidates) { candidate in
                            candidateRow(candidate)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    toggleCandidateSelection(candidate.id)
                                }
                        }
                    }
                    .listStyle(.plain)

                    VStack(spacing: 10) {
                        Button(action: fillCurrentFromSelectedCandidate) {
                            Text("填入当前编辑（单笔）")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .background(Color.warmTeal)
                                .cornerRadius(12)
                        }

                        Button(action: batchImportSelectedCandidates) {
                            Text("批量入账（多笔）")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(Color.warmTeal)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .background(Color.warmTeal.opacity(0.12))
                                .cornerRadius(12)
                        }
                        .disabled(selectedCandidateIDs.isEmpty)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 18)
                    .background(Color.appCardBackground)
                }
            }
            .navigationTitle("识别候选")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("关闭") { showCandidateSheet = false }
                }
            }
        }
    }

    private func candidateRow(_ candidate: ParsedTransactionCandidatePayload) -> some View {
        let isSelected = selectedCandidateIDs.contains(candidate.id)
        let amount = candidate.amount ?? 0
        let source = BillSource(rawValue: candidate.billSourceRaw) ?? .unknown

        return HStack(spacing: 10) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isSelected ? .warmTeal : .secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text(candidate.merchantName ?? candidate.toBiz ?? candidate.note ?? "未识别商户")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(source.displayName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                    if let category = candidate.categoryKey {
                        Text(category)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    if let dateText = candidate.dateISO8601,
                       let parsedDate = ISO8601DateFormatter().date(from: dateText) {
                        Text(parsedDate.shortDateString)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            Text(candidate.isIncome ? "+\(amount.currencyString)" : "-\(amount.currencyString)")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(candidate.isIncome ? .profitGreen : .warmCoral)
        }
        .padding(.vertical, 6)
    }

    private func toggleCandidateSelection(_ id: String) {
        if selectedCandidateIDs.contains(id) {
            selectedCandidateIDs.remove(id)
        } else {
            selectedCandidateIDs.insert(id)
        }
    }

    private func handleDismiss() {
        isNoteFocused = false
        if let onDismiss {
            onDismiss()
        } else {
            router.dismissQuickRecord(printTargetURI: nil)
        }
    }

    private func hapticFeedback() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }

    // MARK: - Actions

    /// 保存并直接返回（参考AChai的doneAction:isContinuous:直接完成模式）
    private func saveAndDismiss() {
        guard !isCommittingTransaction else { return }
        let amount = computedTotal
        guard amount > 0 else { return }
        isCommittingTransaction = true

        if let eventID = importedShortcutEventID,
           ShortcutStorage.hasConsumedRecordEvent(eventID),
           isShortcutImportedContext {
            let existingURI = ShortcutStorage.consumedRecordTransactionURI(for: eventID)
            router.completeQuickRecordAndReturnHome(printTargetURI: existingURI)
            isCommittingTransaction = false
            return
        }

        let category = selectedCategory ?? (isTransfer ? "transfer" : "other")
        let sourceRaw = autoDetectedBillSource == .unknown ? nil : autoDetectedBillSource.rawValue

        if isShortcutImportedContext,
           let duplicate = findLikelyDuplicateTransaction(
                amount: amount,
                isIncome: isIncome,
                date: date,
                categoryKey: category,
                merchantOrNote: autoDetectedMerchantName ?? note
           ) {
            if let eventID = importedShortcutEventID {
                ShortcutStorage.markRecordEventConsumed(eventID, transactionURI: duplicate.objectID.uriRepresentation())
            }
            router.completeQuickRecordAndReturnHome(
                printTargetURI: duplicate.objectID.uriRepresentation()
            )
            isCommittingTransaction = false
            return
        }

        let transaction = BookkeepingTransaction(
            context: viewContext,
            amount: amount,
            categoryKey: category,
            subcategoryKey: selectedSubcategory,
            note: note.isEmpty ? nil : note,
            date: date,
            isIncome: isIncome,
            fundAccountKey: selectedFundAccount,
            notInBudget: notInBudget,
            billSource: sourceRaw,
            merchantName: autoDetectedMerchantName
        )

        if let error = PersistenceSaveCoordinator.save(viewContext) {
            saveErrorMessage = error
            isCommittingTransaction = false
            return
        }

        saveDefaults(category: category)
        updateWidgetData()

        hapticFeedback()
        showDetails = false
        showAddCategory = false
        showCandidateSheet = false
        if let eventID = importedShortcutEventID {
            ShortcutStorage.markRecordEventConsumed(
                eventID,
                transactionURI: transaction.objectID.uriRepresentation()
            )
        }
        router.completeQuickRecordAndReturnHome(
            printTargetURI: transaction.objectID.uriRepresentation()
        )
        isCommittingTransaction = false
    }

    private func fillCurrentFromSelectedCandidate() {
        guard let candidate = selectedCandidates().first ?? parsedCandidates.first else { return }
        applyCandidatePayload(candidate, overwriteExisting: true, fallbackText: candidate.note)
        showCandidateSheet = false
    }

    private func batchImportSelectedCandidates() {
        guard !isCommittingTransaction else { return }
        let selected = selectedCandidates()
        guard !selected.isEmpty else { return }
        isCommittingTransaction = true

        if let eventID = importedShortcutEventID,
           ShortcutStorage.hasConsumedRecordEvent(eventID),
           isShortcutImportedContext {
            let existingURI = ShortcutStorage.consumedRecordTransactionURI(for: eventID)
            router.completeQuickRecordAndReturnHome(printTargetURI: existingURI)
            isCommittingTransaction = false
            return
        }

        var topmostInsertedTransaction: BookkeepingTransaction?

        for payload in selected {
            let parsed = payload.toParsedTransaction()
            let amount = max(0, parsed.amount ?? 0)
            guard amount > 0 else { continue }

            let category = parsed.categoryKey ?? (parsed.isIncome ? "other_income" : "other")
            let sourceRaw = parsed.billSource == .unknown ? nil : parsed.billSource.rawValue
            let fundKey = mapFundNameToFundAccountKey(parsed.fundName ?? "")
            let importedDate = resolvedImportedTransactionDate(from: parsed.date)
            let merchantOrNote = (parsed.merchantName ?? parsed.toBiz ?? parsed.note)?.trimmingCharacters(in: .whitespacesAndNewlines)

            if isShortcutImportedContext,
               findLikelyDuplicateTransaction(
                    amount: amount,
                    isIncome: parsed.isIncome,
                    date: importedDate,
                    categoryKey: category,
                    merchantOrNote: merchantOrNote
               ) != nil {
                continue
            }

            let transaction = BookkeepingTransaction(
                context: viewContext,
                amount: amount,
                categoryKey: category,
                subcategoryKey: nil,
                note: merchantOrNote,
                date: importedDate,
                isIncome: parsed.isIncome,
                fundAccountKey: fundKey,
                notInBudget: false,
                billSource: sourceRaw,
                merchantName: parsed.merchantName ?? parsed.toBiz
            )
            if let currentTop = topmostInsertedTransaction {
                let shouldPromote: Bool
                if transaction.date == currentTop.date {
                    shouldPromote = transaction.objectID.uriRepresentation().absoluteString > currentTop.objectID.uriRepresentation().absoluteString
                } else {
                    shouldPromote = transaction.date > currentTop.date
                }
                if shouldPromote {
                    topmostInsertedTransaction = transaction
                }
            } else {
                topmostInsertedTransaction = transaction
            }
        }

        if let error = PersistenceSaveCoordinator.save(viewContext) {
            saveErrorMessage = error
            isCommittingTransaction = false
            return
        }

        updateWidgetData()
        hapticFeedback()
        showCandidateSheet = false
        showDetails = false
        showAddCategory = false
        if let eventID = importedShortcutEventID {
            ShortcutStorage.markRecordEventConsumed(
                eventID,
                transactionURI: topmostInsertedTransaction?.objectID.uriRepresentation()
            )
        }
        router.completeQuickRecordAndReturnHome(
            printTargetURI: topmostInsertedTransaction?.objectID.uriRepresentation()
        )
        isCommittingTransaction = false
    }

    private func selectedCandidates() -> [ParsedTransactionCandidatePayload] {
        parsedCandidates.filter { selectedCandidateIDs.contains($0.id) }
    }

    private func handleParsedTransactions(
        _ parsedTransactions: [ParsedTransaction],
        fallbackText: String,
        overwriteExisting: Bool
    ) {
        guard !parsedTransactions.isEmpty else { return }

        let payloads = parsedTransactions.map(ParsedTransactionCandidatePayload.init(transaction:))
        parsedCandidates = payloads
        selectedCandidateIDs = Set(payloads.prefix(1).map(\.id))

        if let first = payloads.first {
            applyCandidatePayload(first, overwriteExisting: overwriteExisting, fallbackText: fallbackText)
        }

        showCandidateSheet = payloads.count > 1
    }

    private func applyCandidatePayload(
        _ payload: ParsedTransactionCandidatePayload,
        overwriteExisting: Bool,
        fallbackText: String?
    ) {
        let parsed = payload.toParsedTransaction()

        if overwriteExisting || amountString.isEmpty, let amount = parsed.amount {
            amountString = amountInputString(from: amount)
        }

        if overwriteExisting || selectedCategory == nil {
            if let categoryKey = parsed.categoryKey, !categoryKey.isEmpty {
                selectedCategory = categoryKey
                selectedSubcategory = nil
            }
        }

        if overwriteExisting || note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let preferredCounterparty = preferredCounterparty(from: parsed), !preferredCounterparty.isEmpty {
                note = preferredCounterparty
            } else if let parsedNote = parsed.note,
                      !parsedNote.isEmpty,
                      !OCRSemanticFilter.isLikelyNoiseNote(parsedNote) {
                note = parsedNote
            } else if let fallbackText, let compact = compactNote(from: fallbackText) {
                note = compact
            }
        }

        applyAutoTransactionType(parsed.isIncome)

        if overwriteExisting || selectedFundAccount == nil {
            if let fund = resolvedFundAccountKey(from: parsed, rawText: fallbackText ?? "") {
                selectedFundAccount = fund
            }
        }

        if let parsedDate = parsed.date, shouldApplyParsedDate(parsedDate) {
            date = parsedDate
        }

        autoDetectedBillSource = parsed.billSource
        autoDetectedMerchantName = preferredCounterparty(from: parsed)
    }

    private func loadDefaults() {
        let defaults = UserDefaults.standard
        selectedCategory = defaults.string(forKey: Constants.Bookkeeping.lastCategoryKey)
        selectedSubcategory = defaults.string(forKey: Constants.Bookkeeping.lastSubcategoryKey)
        selectedFundAccount = defaults.string(forKey: Constants.Bookkeeping.lastFundAccountKey)
        autoDetectedBillSource = .unknown
        autoDetectedMerchantName = nil
        parsedCandidates = []
        selectedCandidateIDs = []
        showCandidateSheet = false
    }

    private func saveDefaults(category: String) {
        let defaults = UserDefaults.standard
        defaults.set(category, forKey: Constants.Bookkeeping.lastCategoryKey)
        defaults.set(selectedSubcategory, forKey: Constants.Bookkeeping.lastSubcategoryKey)
        defaults.set(selectedFundAccount, forKey: Constants.Bookkeeping.lastFundAccountKey)

        let recentKey = isIncome
            ? Constants.Bookkeeping.recentIncomeCategoryKeys
            : Constants.Bookkeeping.recentExpenseCategoryKeys
        var recent = defaults.stringArray(forKey: recentKey) ?? []
        recent.removeAll { $0 == category }
        recent.insert(category, at: 0)
        if recent.count > Constants.Bookkeeping.maxRecentCategoryHistory {
            recent = Array(recent.prefix(Constants.Bookkeeping.maxRecentCategoryHistory))
        }
        defaults.set(recent, forKey: recentKey)

        let frequencyKey = isIncome
            ? Constants.Bookkeeping.incomeCategoryFrequencyMap
            : Constants.Bookkeeping.expenseCategoryFrequencyMap
        var frequency = defaults.dictionary(forKey: frequencyKey) as? [String: Int] ?? [:]
        frequency[category, default: 0] += 1
        defaults.set(frequency, forKey: frequencyKey)

        let contextPrefix = isIncome
            ? Constants.Bookkeeping.incomeCategoryContextFrequencyPrefix
            : Constants.Bookkeeping.expenseCategoryContextFrequencyPrefix
        let contextKey = contextPrefix + usageContextKey(for: date)
        var contextFrequency = defaults.dictionary(forKey: contextKey) as? [String: Int] ?? [:]
        contextFrequency[category, default: 0] += 1
        defaults.set(contextFrequency, forKey: contextKey)
    }

    private func usageContextKey(for date: Date) -> String {
        let calendar = Calendar.current
        let isWeekend = calendar.isDateInWeekend(date)
        let hour = calendar.component(.hour, from: date)
        let period = (6..<18).contains(hour) ? "day" : "night"
        return "\(isWeekend ? "weekend" : "weekday").\(period)"
    }

    private func loadPendingParams() {
        #if DEBUG
        let debugSignature = "\(router.pendingRecordParams != nil)|\(ShortcutStorage.pendingAction?.rawValue ?? "nil")|\(ShortcutStorage.pendingRecordImagePath ?? "nil")"
        if debugSignature != Self.lastPendingDebugSignature {
            print("[QuickRecord] loadPendingParams state changed: pendingRecordParams=\(router.pendingRecordParams != nil), pendingAction=\(ShortcutStorage.pendingAction?.rawValue ?? "nil"), pendingImagePath=\(ShortcutStorage.pendingRecordImagePath ?? "nil")")
            Self.lastPendingDebugSignature = debugSignature
        }
        #endif
        importedShortcutEventID = nil
        isShortcutImportedContext = false

        // Priority 1: params already passed through router (iOS 16+ in-process or deep link)
        if let params = router.pendingRecordParams {
            importedShortcutEventID = params.eventID
            if let amount = params.amount {
                amountString = amountInputString(from: amount)
            }
            if let income = params.isIncome {
                applyAutoTransactionType(income)
            }
            if let key = params.categoryKey {
                selectedCategory = key
                selectedSubcategory = nil
            }
            if let parsedDate = params.date, shouldApplyParsedDate(parsedDate) {
                date = parsedDate
            }
            if let noteValue = params.note {
                note = noteValue
            }
            if let candidates = params.candidates, !candidates.isEmpty {
                parsedCandidates = candidates
                selectedCandidateIDs = Set(candidates.prefix(1).map(\.id))
                if let first = candidates.first {
                    applyCandidatePayload(first, overwriteExisting: true, fallbackText: params.note)
                }
                showCandidateSheet = candidates.count > 1

                let imagePath = params.imagePath ?? ShortcutStorage.pendingRecordImagePath
                if let imagePath, !imagePath.isEmpty {
                    cleanupPendingImage(at: imagePath)
                    ShortcutStorage.pendingRecordImagePath = nil
                }
                router.pendingRecordParams = nil
                ShortcutStorage.clearPendingAction()
                return
            }

            let imagePath = params.imagePath ?? ShortcutStorage.pendingRecordImagePath
            router.pendingRecordParams = nil
            ShortcutStorage.clearPendingAction()
            if let imagePath, !imagePath.isEmpty {
                isShortcutImportedContext = true
                recognizePendingImage(at: imagePath)
            } else if let ocrText = params.note, !ocrText.isEmpty,
                      params.amount == nil, params.categoryKey == nil {
                // iOS 15 legacy: shortcut passed OCR text via note field — parse it
                isShortcutImportedContext = true
                parseAndFillFromText(ocrText)
            } else {
                // No image from shortcut — just open empty record page
                isShortcutImportedContext = true
            }
            return
        }

        // Priority 2: fallback — read directly from ShortcutStorage
        // This covers iOS 15 legacy intent where the text/image is persisted to App Group
        // and the router may have already consumed the action before this view loads.
        var didLoad = false
        var loadedCandidates = false

        if let storageParams = ShortcutStorage.pendingRecordParams {
            importedShortcutEventID = storageParams.eventID
            if let amount = storageParams.amount {
                amountString = amountInputString(from: amount)
                didLoad = true
            }
            if let income = storageParams.isIncome {
                applyAutoTransactionType(income)
                didLoad = true
            }
            if let key = storageParams.categoryKey {
                selectedCategory = key
                selectedSubcategory = nil
                didLoad = true
            }
            if let noteValue = storageParams.note {
                note = noteValue
                didLoad = true
            }
            if let dateString = storageParams.date,
               let parsedDate = ISO8601DateFormatter().date(from: dateString),
               shouldApplyParsedDate(parsedDate) {
                date = parsedDate
                didLoad = true
            }
            if let candidates = storageParams.candidates, !candidates.isEmpty {
                parsedCandidates = candidates
                selectedCandidateIDs = Set(candidates.prefix(1).map(\.id))
                if let first = candidates.first {
                    applyCandidatePayload(first, overwriteExisting: true, fallbackText: storageParams.note)
                }
                showCandidateSheet = candidates.count > 1
                didLoad = true
                loadedCandidates = true
            }
        }

        if !loadedCandidates,
           let imagePath = ShortcutStorage.pendingRecordImagePath, !imagePath.isEmpty {
            ShortcutStorage.pendingRecordImagePath = nil
            isShortcutImportedContext = true
            recognizePendingImage(at: imagePath)
            didLoad = true
        } else if loadedCandidates,
                  let imagePath = ShortcutStorage.pendingRecordImagePath, !imagePath.isEmpty {
            ShortcutStorage.pendingRecordImagePath = nil
            isShortcutImportedContext = true
            cleanupPendingImage(at: imagePath)
        } else if !loadedCandidates,
                  let storageParams = ShortcutStorage.pendingRecordParams,
                  let ocrText = storageParams.note, !ocrText.isEmpty,
                  storageParams.amount == nil, storageParams.categoryKey == nil {
            // iOS 15 legacy: shortcut passed OCR text — parse it for amount/category
            ShortcutStorage.clearPendingAction()
            isShortcutImportedContext = true
            parseAndFillFromText(ocrText)
            return
        } else if ShortcutStorage.pendingAction == .addRecord {
            // Shortcut triggered "addRecord" but no image path — open empty record page
            ShortcutStorage.clearPendingAction()
            isShortcutImportedContext = true
            return
        }

        if didLoad {
            ShortcutStorage.clearPendingAction()
        }
    }

    private func recognizePendingImage(at path: String) {
        guard !path.isEmpty else { return }
        #if DEBUG
        print("[QuickRecord] recognizePendingImage at: \(path)")
        #endif
        isRecognizingImage = true

        Task {
            defer {
                Task { @MainActor in
                    isRecognizingImage = false
                }
                cleanupPendingImage(at: path)
            }

            guard let image = UIImage(contentsOfFile: path) else {
                #if DEBUG
                print("[QuickRecord] Failed to load image from path: \(path)")
                #endif
                return
            }
            #if DEBUG
            print("[QuickRecord] Image loaded, size: \(image.size), running OCR...")
            #endif

            do {
                let ocrResult = try await ProductionOCRService.shared.recognizeTextWithDetails(from: image)
                let parser = ProductionTransactionParserService()
                let parsedTransactions = parser.parse(ocrResult)
                let parsed = parser.bestCandidate(from: parsedTransactions)

                await MainActor.run {
                    handleParsedTransactions(
                        parsedTransactions,
                        fallbackText: ocrResult.fullText,
                        overwriteExisting: false
                    )

                    if parsedTransactions.isEmpty, let parsed {
                        applyCandidatePayload(
                            ParsedTransactionCandidatePayload(transaction: parsed),
                            overwriteExisting: false,
                            fallbackText: ocrResult.fullText
                        )
                    }
                }
            } catch {
                // Keep silent to avoid interrupting quick-entry flow.
            }
        }
    }

    private func cleanupPendingImage(at path: String) {
        guard !path.isEmpty else { return }
        try? FileManager.default.removeItem(atPath: path)
    }

    /// Parse OCR text (passed from shortcut's "Extract Text" action) to fill amount/category/note.
    private func parseAndFillFromText(_ text: String) {
        #if DEBUG
        print("[QuickRecord] parseAndFillFromText: \(text.prefix(80))...")
        #endif
        isRecognizingImage = true
        let parser = ProductionTransactionParserService()
        let parsedTransactions = parser.parse(text)
        handleParsedTransactions(parsedTransactions, fallbackText: text, overwriteExisting: false)

        if parsedTransactions.isEmpty {
            if let compact = compactNote(from: text) {
                note = compact
            }
        }

        isRecognizingImage = false
    }

    private func preferredCounterparty(from parsed: ParsedTransaction?) -> String? {
        guard let parsed else { return nil }

        let merchant = parsed.merchantName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !merchant.isEmpty, OCRSemanticFilter.isLikelyMerchantText(merchant) {
            return merchant
        }

        let toBiz = parsed.toBiz?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !toBiz.isEmpty, OCRSemanticFilter.isLikelyMerchantText(toBiz) {
            return toBiz
        }
        return nil
    }

    private func resolvedFundAccountKey(from parsed: ParsedTransaction?, rawText: String) -> String? {
        guard let parsed else { return nil }

        if let fundName = parsed.fundName,
           let mapped = mapFundNameToFundAccountKey(fundName) {
            return mapped
        }

        guard parsed.billSource != .unknown else { return nil }
        return BillSource.inferFundAccount(from: parsed.billSource, rawText: rawText)
    }

    private func mapFundNameToFundAccountKey(_ fundName: String) -> String? {
        let normalized = fundName.lowercased()

        if normalized.contains("花呗") { return "huabei" }
        if normalized.contains("信用卡") { return "credit" }
        if normalized.contains("借记卡") || normalized.contains("储蓄卡") || normalized.contains("银行卡") {
            return "debit"
        }
        if normalized.contains("零钱") || normalized.contains("微信") {
            return "wechat"
        }
        if normalized.contains("余额宝") || normalized.contains("支付宝") || normalized.contains("余额") {
            return "alipay"
        }

        return nil
    }

    private func applyAutoTransactionType(_ isIncomeValue: Bool) {
        let targetType: TransactionType = isIncomeValue ? .income : .expense
        guard transactionType != targetType else { return }

        suppressTypeReset = true
        transactionType = targetType
        DispatchQueue.main.async {
            suppressTypeReset = false
        }
    }

    private func compactNote(from text: String) -> String? {
        OCRSemanticFilter.firstMeaningfulNoteLine(from: text, maxLength: 40)
    }

    private func amountInputString(from amount: Double) -> String {
        guard amount.isFinite else { return "0" }
        if amount == floor(amount) {
            return String(format: "%.0f", amount)
        }

        let fixed = String(format: "%.2f", amount)
        if fixed.hasSuffix("0") {
            return String(fixed.dropLast())
        }
        return fixed
    }

    private func shouldApplyParsedDate(_ parsedDate: Date) -> Bool {
        // 快捷导入默认使用账单真实时间；是否展示由首页日期筛选控制。
        let year = Calendar.current.component(.year, from: parsedDate)
        return (2000...2100).contains(year)
    }

    private func resolvedImportedTransactionDate(from parsedDate: Date?) -> Date {
        guard let parsedDate else { return Date() }
        return shouldApplyParsedDate(parsedDate) ? parsedDate : Date()
    }

    private func findLikelyDuplicateTransaction(
        amount: Double,
        isIncome: Bool,
        date: Date,
        categoryKey: String,
        merchantOrNote: String?
    ) -> BookkeepingTransaction? {
        let window: TimeInterval = 180
        let lower = date.addingTimeInterval(-window)
        let upper = date.addingTimeInterval(window)
        let roundedAmount = (amount * 100).rounded() / 100

        let request: NSFetchRequest<BookkeepingTransaction> = BookkeepingTransaction.fetchRequest()
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \BookkeepingTransaction.date, ascending: false),
            NSSortDescriptor(keyPath: \BookkeepingTransaction.createdAt, ascending: false)
        ]
        request.fetchLimit = 20
        request.predicate = NSPredicate(
            format: "date >= %@ AND date <= %@ AND isIncome == %@ AND amount >= %f AND amount <= %f",
            lower as NSDate,
            upper as NSDate,
            NSNumber(value: isIncome),
            roundedAmount - 0.01,
            roundedAmount + 0.01
        )

        guard let matches = try? viewContext.fetch(request), !matches.isEmpty else {
            return nil
        }

        let normalizedTargetText = normalizeDedupText(merchantOrNote)
        if normalizedTargetText.isEmpty {
            return matches.first { $0.categoryKey == categoryKey } ?? matches.first
        }

        return matches.first { tx in
            guard tx.categoryKey == categoryKey else { return false }
            let noteText = normalizeDedupText(tx.note)
            let merchantText = normalizeDedupText(tx.merchantName)
            return noteText == normalizedTargetText || merchantText == normalizedTargetText
        } ?? matches.first
    }

    private func normalizeDedupText(_ text: String?) -> String {
        guard let text else { return "" }
        return text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
    }

    private func updateWidgetData() {
        guard let defaults = UserDefaults(suiteName: Constants.Bookkeeping.widgetSuiteName) else { return }

        let today = Date()
        let dayStart = today.startOfDay
        let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(86_400)
        let request: NSFetchRequest<BookkeepingTransaction> = BookkeepingTransaction.fetchRequest()
        request.predicate = NSPredicate(
            format: "date >= %@ AND date < %@ AND isIncome == NO AND categoryKey != %@",
            dayStart as NSDate,
            dayEnd as NSDate,
            "transfer"
        )

        do {
            let transactions = try viewContext.fetch(request)
            let totalExpense = transactions.reduce(0.0) { $0 + $1.normalizedAmount }
            let summary = TodaySummary(
                totalExpense: totalExpense,
                transactionCount: transactions.count,
                dateString: today.shortDateString
            )
            if let data = try? JSONEncoder().encode(summary) {
                defaults.set(data, forKey: Constants.Bookkeeping.widgetTodaySummaryKey)
            }
        } catch {
            // Silent
        }
    }
}

// MARK: - Record Details Sheet

struct RecordDetailsView: View {
    @Binding var note: String
    @Binding var date: Date
    @Binding var transactionType: TransactionType
    @Binding var selectedCategory: String?
    @Binding var selectedSubcategory: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("类型")) {
                    Picker("类型", selection: $transactionType) {
                        Text("支出").tag(TransactionType.expense)
                        Text("收入").tag(TransactionType.income)
                        Text("转账").tag(TransactionType.transfer)
                    }
                    .pickerStyle(.segmented)
                }

                Section(header: Text("日期")) {
                    DatePicker("日期", selection: $date, displayedComponents: .date)
                }

                Section(header: Text("备注")) {
                    TextField("添加备注（可选）", text: $note)
                }
            }
            .navigationTitle("账单详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                        .foregroundColor(.warmTeal)
                }
            }
        }
    }
}

// MARK: - Voice Record View

struct VoiceRecordView: View {
    @Binding var amountString: String
    @Binding var note: String
    @Binding var selectedCategory: String?
    @Binding var isIncome: Bool
    @Environment(\.dismiss) private var dismiss

    @State private var inputText = ""
    @State private var isRecording = false
    @State private var errorMessage: String?

    private let speechService = SpeechRecognitionService()

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("输入描述，自动识别金额和分类")
                        .font(.subheadline)
                        .foregroundColor(.textSecondary)

                    TextField("例如：午餐35元", text: $inputText)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
                .padding(.horizontal)

                Button(action: {
                    if isRecording {
                        stopRecording()
                    } else {
                        startRecording()
                    }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: isRecording ? "stop.circle.fill" : "mic.circle.fill")
                            .font(.title2)
                        Text(isRecording ? "停止录音" : "语音输入")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(isRecording ? Color.warmCoral : Color.warmTeal)
                    .foregroundColor(.white)
                    .cornerRadius(20)
                }
                .padding(.horizontal)

                if isRecording {
                    Text("正在聆听...")
                        .font(.subheadline)
                        .foregroundColor(.warmTeal)
                }

                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.warmCoral)
                        .padding(.horizontal)
                }

                Button(action: parseAndFill) {
                    Text("识别并填入")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.warmYellow)
                        .foregroundColor(.primary)
                        .cornerRadius(20)
                }
                .disabled(inputText.isEmpty)
                .padding(.horizontal)

                Spacer()
            }
            .padding()
            .background(Color.warmMint.opacity(0.3))
            .navigationTitle("智能记账")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                        .foregroundColor(.warmTeal)
                }
            }
        }
    }

    private func startRecording() {
        Task {
            do {
                let authorized = await speechService.requestAuthorization()
                guard authorized else {
                    errorMessage = "请授权语音识别"
                    return
                }
                isRecording = true
                errorMessage = nil
                let text = try await speechService.startRecording()
                isRecording = false
                if !text.isEmpty {
                    inputText = text
                }
            } catch {
                isRecording = false
                errorMessage = "识别失败：\(error.localizedDescription)"
            }
        }
    }

    private func stopRecording() {
        speechService.stopRecording()
        isRecording = false
    }

    private func parseAndFill() {
        let parser = MockTransactionParserService()
        guard let result = parser.bestCandidate(from: parser.parse(inputText)) else { return }
        if let amount = result.amount {
            amountString = String(format: "%.0f", amount)
        }
        if let category = result.categoryKey {
            selectedCategory = category
        }
        if let noteValue = result.note {
            note = noteValue
        }
        if result.isIncome {
            isIncome = true
        }
        dismiss()
    }
}

#Preview {
    NavigationView {
        QuickRecordView(showBackButton: true)
            .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
            .environmentObject(AppRouter())
    }
    .navigationViewStyle(.stack)
}
