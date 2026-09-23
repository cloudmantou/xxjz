import SwiftUI

struct CategoryPickerView: View {
    @Binding var selectedCategory: String?
    @Binding var selectedSubcategory: String?
    let isIncome: Bool
    let categories: [BookkeepingCategory]
    let minimalMode: Bool
    @State private var showAllCategories = false
    @State private var showSubcategoriesInMinimalMode = false
    private let quickAccessLimit = 3

    private let subcategoryColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        VStack(spacing: 10) {
            if !quickAccessCategories.isEmpty {
                quickAccessRow
            }

            // Level 1: Horizontal category tabs
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(displayedCategories) { category in
                        categoryTab(category)
                    }

                    if showsMoreCategoryButton {
                        moreCategoryButton
                    }
                }
                .padding(.horizontal, 8)
            }

            if !isIncome {
                subcategorySection
            }
        }
        .onAppear {
            syncCategoryExpansionState()
        }
        .onChange(of: selectedCategory) { _ in
            syncCategoryExpansionState()
            if minimalMode {
                showSubcategoriesInMinimalMode = false
            }
        }
        .onChange(of: isIncome) { newValue in
            if !newValue {
                showAllCategories = false
            }
        }
    }

    private var currentCategory: BookkeepingCategory? {
        guard let key = selectedCategory else {
            return nil
        }
        return orderedCategories.first { $0.key == key }
    }

    private var categoryLimit: Int {
        isIncome ? orderedCategories.count : Constants.Bookkeeping.maxPinnedCategories
    }

    private var recentCategoryKeys: [String] {
        let defaults = UserDefaults.standard
        let recentKey = isIncome
            ? Constants.Bookkeeping.recentIncomeCategoryKeys
            : Constants.Bookkeeping.recentExpenseCategoryKeys
        return defaults.stringArray(forKey: recentKey) ?? []
    }

    private var categoryIndexMap: [String: Int] {
        Dictionary(uniqueKeysWithValues: categories.enumerated().map { ($0.element.key, $0.offset) })
    }

    private var frequencyMap: [String: Int] {
        let defaults = UserDefaults.standard
        let frequencyKey = isIncome
            ? Constants.Bookkeeping.incomeCategoryFrequencyMap
            : Constants.Bookkeeping.expenseCategoryFrequencyMap
        guard let raw = defaults.dictionary(forKey: frequencyKey) else { return [:] }

        var map: [String: Int] = [:]
        for (key, value) in raw {
            if let intValue = value as? Int {
                map[key] = intValue
            }
        }
        return map
    }

    private var contextFrequencyMap: [String: Int] {
        let defaults = UserDefaults.standard
        let contextPrefix = isIncome
            ? Constants.Bookkeeping.incomeCategoryContextFrequencyPrefix
            : Constants.Bookkeeping.expenseCategoryContextFrequencyPrefix
        let contextKey = contextPrefix + usageContextKey(for: Date())
        guard let raw = defaults.dictionary(forKey: contextKey) else { return [:] }

        var map: [String: Int] = [:]
        for (key, value) in raw {
            if let intValue = value as? Int {
                map[key] = intValue
            }
        }
        return map
    }

    private func usageContextKey(for date: Date) -> String {
        let calendar = Calendar.current
        let isWeekend = calendar.isDateInWeekend(date)
        let hour = calendar.component(.hour, from: date)
        let period = (6..<18).contains(hour) ? "day" : "night"
        return "\(isWeekend ? "weekend" : "weekday").\(period)"
    }

    private func usageContextDisplayName(for date: Date) -> String {
        let calendar = Calendar.current
        let isWeekend = calendar.isDateInWeekend(date)
        let hour = calendar.component(.hour, from: date)
        let period = (6..<18).contains(hour) ? L10n.tr("白天") : L10n.tr("晚间")
        return "\(isWeekend ? L10n.tr("周末") : L10n.tr("工作日"))\(period)"
    }

    private func weightedScore(for key: String) -> Double {
        let base = Double(frequencyMap[key] ?? 0)
        let context = Double(contextFrequencyMap[key] ?? 0)
        return base + (context * 1.8)
    }

    private var sortedFrequencyKeys: [String] {
        let validKeys = Set(categories.map(\.key))
        return validKeys
            .filter { weightedScore(for: $0) > 0 }
            .sorted { lhs, rhs in
                let lhsScore = weightedScore(for: lhs)
                let rhsScore = weightedScore(for: rhs)
                if lhsScore != rhsScore { return lhsScore > rhsScore }
                return (categoryIndexMap[lhs] ?? Int.max) < (categoryIndexMap[rhs] ?? Int.max)
            }
    }

    private var smartPriorityKeys: [String] {
        let recent = recentCategoryKeys.filter { categoryIndexMap[$0] != nil }
        let frequent = sortedFrequencyKeys
        var used = Set<String>()
        var merged: [String] = []
        var i = 0
        var j = 0

        while merged.count < Constants.Bookkeeping.maxPinnedCategories && (i < recent.count || j < frequent.count) {
            if i < recent.count {
                let key = recent[i]
                i += 1
                if used.insert(key).inserted {
                    merged.append(key)
                }
            }

            if j < frequent.count {
                let key = frequent[j]
                j += 1
                if used.insert(key).inserted {
                    merged.append(key)
                }
            }
        }

        return merged
    }

    private var orderedCategories: [BookkeepingCategory] {
        let byKey = Dictionary(uniqueKeysWithValues: categories.map { ($0.key, $0) })
        var prioritized: [BookkeepingCategory] = []
        var usedKeys = Set<String>()

        for key in smartPriorityKeys {
            guard let category = byKey[key], !usedKeys.contains(key) else { continue }
            prioritized.append(category)
            usedKeys.insert(key)
        }

        if prioritized.isEmpty {
            return categories
        }

        let remaining = categories.filter { !usedKeys.contains($0.key) }
        return prioritized + remaining
    }

    private var displayedCategories: [BookkeepingCategory] {
        if showAllCategories || orderedCategories.count <= categoryLimit {
            return orderedCategories
        }
        return Array(orderedCategories.prefix(categoryLimit))
    }

    private var showsMoreCategoryButton: Bool {
        !showAllCategories && orderedCategories.count > categoryLimit
    }

    private var moreCategoryButton: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                showAllCategories = true
            }
        }) {
            HStack(spacing: 4) {
                Image(systemName: "ellipsis.circle")
                Text("更多")
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(Color.warmTeal)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.warmTealLight.opacity(0.7))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.warmTeal.opacity(0.2), lineWidth: 1)
            )
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }

    private func syncCategoryExpansionState() {
        guard let key = selectedCategory else { return }
        if !displayedCategories.contains(where: { $0.key == key }) {
            showAllCategories = true
        }
    }

    @ViewBuilder
    private var subcategorySection: some View {
        if let current = currentCategory, !current.subcategories.isEmpty {
            if minimalMode {
                VStack(spacing: 8) {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showSubcategoriesInMinimalMode.toggle()
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "square.grid.2x2")
                            Text(showSubcategoriesInMinimalMode ? L10n.tr("收起细分") : L10n.tr("细分分类"))
                            if let selectedSubcategory {
                                Text("· \(BookkeepingCategory.findSubcategory(key: selectedSubcategory)?.localizedName ?? "")")
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: showSubcategoriesInMinimalMode ? "chevron.up" : "chevron.down")
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.warmTeal)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color.warmTealLight.opacity(0.6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.warmTeal.opacity(0.2), lineWidth: 1)
                        )
                        .cornerRadius(10)
                        .padding(.horizontal, 8)
                    }
                    .buttonStyle(.plain)

                    if showSubcategoriesInMinimalMode {
                        LazyVGrid(columns: subcategoryColumns, spacing: 10) {
                            ForEach(current.subcategories) { sub in
                                subcategoryItem(sub)
                            }
                        }
                        .padding(.horizontal, 8)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            } else {
                LazyVGrid(columns: subcategoryColumns, spacing: 10) {
                    ForEach(current.subcategories) { sub in
                        subcategoryItem(sub)
                    }
                }
                .padding(.horizontal, 8)
                .animation(.easeInOut(duration: 0.2), value: selectedCategory)
            }
        } else {
            HStack(spacing: 6) {
                Image(systemName: "hand.tap")
                Text("先选一个分类，再看细分选项")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.vertical, 2)
        }
    }

    private var quickAccessCategories: [BookkeepingCategory] {
        let byKey = Dictionary(uniqueKeysWithValues: categories.map { ($0.key, $0) })
        return smartPriorityKeys
            .prefix(quickAccessLimit)
            .compactMap { byKey[$0] }
    }

    private var quickAccessExplainText: String {
        if contextFrequencyMap.values.contains(where: { $0 > 0 }) {
            return "\(L10n.tr("本时段常用")) · \(usageContextDisplayName(for: Date()))"
        }
        return L10n.tr("最近 + 高频")
    }

    private var quickAccessContextShortText: String {
        if contextFrequencyMap.values.contains(where: { $0 > 0 }) {
            return usageContextDisplayName(for: Date())
        }
        return L10n.tr("最近 + 高频")
    }

    private var quickAccessRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if minimalMode {
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.fill")
                        Text("\(L10n.tr("常用")) · \(quickAccessContextShortText)")
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 8)
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.fill")
                        Text("常用")
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 8)

                    Text(quickAccessExplainText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color(.tertiarySystemFill))
                        .cornerRadius(9)
                }

                ForEach(quickAccessCategories) { category in
                    quickCategoryChip(category)
                }
            }
            .padding(.horizontal, 8)
        }
    }

    private func quickCategoryChip(_ category: BookkeepingCategory) -> some View {
        let isSelected = selectedCategory == category.key
        return Button(action: {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedCategory = category.key
                selectedSubcategory = nil
            }
        }) {
            HStack(spacing: 4) {
                Text(category.emoji)
                    .font(.caption)
                Text(category.localizedName)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(isSelected ? Color.warmTeal : .secondary)
            .background(isSelected ? Color.warmTealLight : Color(.tertiarySystemFill))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.warmTeal.opacity(0.28) : Color.clear, lineWidth: 1)
            )
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Category Tab

    private func categoryTab(_ category: BookkeepingCategory) -> some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedCategory = category.key
                selectedSubcategory = nil
            }
        }) {
            VStack(spacing: 4) {
                Text(category.emoji)
                    .font(.system(size: 24))
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(selectedCategory == category.key
                                  ? category.color
                                  : category.color.opacity(0.5))
                    )
                    .overlay(
                        Circle()
                            .stroke(selectedCategory == category.key
                                    ? Color.warmTeal
                                    : Color.clear,
                                    lineWidth: 2)
                    )
                    .scaleEffect(selectedCategory == category.key ? 1.1 : 1.0)

                Text(category.localizedName)
                    .font(.system(size: 11))
                    .fontWeight(selectedCategory == category.key ? .semibold : .regular)
                    .foregroundColor(selectedCategory == category.key ? .warmTeal : .textSecondary)
            }
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Subcategory Item

    private func subcategoryItem(_ sub: BookkeepingSubcategory) -> some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedSubcategory = sub.key
            }
        }) {
            VStack(spacing: 3) {
                Text(sub.emoji)
                    .font(.system(size: 22))
                    .frame(width: 40, height: 40)
                    .background(
                        Circle()
                            .fill(selectedSubcategory == sub.key
                                  ? Color.warmTealLight
                                  : Color(.tertiarySystemFill))
                    )
                    .overlay(
                        Circle()
                            .stroke(selectedSubcategory == sub.key
                                    ? Color.warmTeal
                                    : Color.clear,
                                    lineWidth: 1.5)
                    )

                Text(sub.localizedName)
                    .font(.system(size: 10))
                    .fontWeight(selectedSubcategory == sub.key ? .semibold : .regular)
                    .foregroundColor(selectedSubcategory == sub.key ? .warmTeal : .textSecondary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State private var selectedCategory: String?
        @State private var selectedSubcategory: String?

        var body: some View {
            CategoryPickerView(
                selectedCategory: $selectedCategory,
                selectedSubcategory: $selectedSubcategory,
                isIncome: false,
                categories: BookkeepingCategory.expenseCategories,
                minimalMode: false
            )
            .padding()
        }
    }
    return PreviewWrapper()
}
