import SwiftUI

struct CustomCategoryFormView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: CustomCategoryStore
    let isIncome: Bool
    let existingCategory: CustomCategory?

    @State private var name = ""
    @State private var selectedEmoji = "📝"
    @State private var selectedColorIndex = 0

    private var screenWidth: CGFloat {
        UIScreen.main.bounds.width
    }

    private var isCompactPhoneWidth: Bool {
        screenWidth <= 350
    }

    private var formHorizontalPadding: CGFloat {
        isCompactPhoneWidth ? 12 : 16
    }

    private var emojiColumnCount: Int {
        if screenWidth <= 350 { return 6 }
        if screenWidth <= 390 { return 7 }
        return 8
    }

    private var colorColumnCount: Int {
        isCompactPhoneWidth ? 5 : 6
    }

    private let colors = [
        "FFF8E1", "FCE4EC", "E8F5E9", "E3F2FD",
        "F3E5F5", "FFF3E0", "E0F2F1", "FFEBEE",
        "E0F7FA", "F5F5F5"
    ]

    private let emojiGroups: [(String, [String])] = [
        ("常用", [
            "📝", "💡", "🏷️", "📦", "🎯", "⭐", "🔥", "💎",
            "🎨", "🎪", "🎭", "🎵", "🎼", "🎹", "🎸", "🎺"
        ]),
        ("餐饮", [
            "🍽️", "🥐", "🍱", "🍲", "🍫", "🧋", "🛵", "🍜",
            "🎉", "🍕", "🍔", "🍟", "🌭", "🥗", "🍣", "🧁"
        ]),
        ("出行", [
            "🚗", "🚌", "🚇", "🚕", "🚲", "⛽", "🅿️", "🚄",
            "✈️", "🛵", "🚢", "🚁", "🚀", "🛸", "⛵", "🚤"
        ]),
        ("购物", [
            "🛍️", "👕", "👟", "👜", "🧴", "📱", "🏠", "💍",
            "🧥", "👗", "👒", "🩰", "🎒", "🧣", "👓", "💄"
        ]),
        ("生活", [
            "🏠", "💧", "🏢", "📶", "🔧", "🏥", "💊", "🩺",
            "💪", "🦷", "📚", "🎓", "📝", "📋", "🎁", "🧧"
        ]),
        ("其他", [
            "💸", "💰", "📈", "💼", "🔄", "💎", "🎮", "🎬",
            "⚽", "🎤", "🎲", "🧩", "🎰", "🎳", "🎯", "🏆"
        ])
    ]

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Preview
                    previewSection

                    // Name input
                    nameInputSection

                    // Emoji picker
                    emojiPickerSection

                    // Color picker
                    colorPickerSection
                }
                .padding(formHorizontalPadding)
            }
            .background(Color.appPageBackground)
            .navigationTitle(existingCategory == nil ? L10n.tr("添加分类") : L10n.tr("编辑分类"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }
                        .foregroundColor(.secondary)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") { save() }
                        .foregroundColor(name.isEmpty ? .secondary : Color.warmTeal)
                        .disabled(name.isEmpty)
                }
            }
        }
    }

    // MARK: - Preview

    private var previewSection: some View {
        VStack(spacing: 8) {
            Text("预览")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)

            HStack(spacing: 12) {
                Text(selectedEmoji)
                    .font(.system(size: 32))
                    .frame(width: 56, height: 56)
                    .background(
                        Circle().fill(Color(hex: colors[selectedColorIndex]))
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(name.isEmpty ? "分类名称" : name)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(name.isEmpty ? .secondary : .primary)
                    Text(isIncome ? L10n.tr("收入") : L10n.tr("支出"))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
            .padding(16)
            .background(Color.appCardMutedBackground)
            .cornerRadius(12)
        }
    }

    // MARK: - Name Input

    private var nameInputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("分类名称")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondary)

            TextField("例如：宠物、健身、美甲", text: $name)
                .font(.system(size: 16))
                .padding(12)
                .background(Color.appCardMutedBackground)
                .cornerRadius(10)
        }
    }

    // MARK: - Emoji Picker

    private var emojiPickerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("选择图标")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondary)

            ForEach(emojiGroups, id: \.0) { groupName, emojis in
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.tr(groupName))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: emojiColumnCount), spacing: 8) {
                        ForEach(emojis, id: \.self) { emoji in
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    selectedEmoji = emoji
                                }
                            }) {
                                Text(emoji)
                                    .font(.system(size: isCompactPhoneWidth ? 22 : 24))
                                    .frame(width: isCompactPhoneWidth ? 34 : 38, height: isCompactPhoneWidth ? 34 : 38)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(selectedEmoji == emoji ? Color.warmTeal.opacity(0.15) : Color.appCardMutedBackground)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(selectedEmoji == emoji ? Color.warmTeal : Color.clear, lineWidth: 2)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Color Picker

    private var colorPickerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("背景颜色")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondary)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: colorColumnCount), spacing: 10) {
                ForEach(Array(colors.enumerated()), id: \.offset) { index, hex in
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedColorIndex = index
                        }
                    }) {
                        Circle()
                            .fill(Color(hex: hex))
                            .frame(width: 32, height: 32)
                            .overlay(
                                Circle()
                                    .stroke(selectedColorIndex == index ? Color.warmTeal : Color(.separator), lineWidth: selectedColorIndex == index ? 2.5 : 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    // MARK: - Save

    private func save() {
        guard !name.isEmpty else { return }
        let category = CustomCategory(
            id: existingCategory?.id ?? UUID().uuidString,
            name: name,
            emoji: selectedEmoji,
            colorHex: colors[selectedColorIndex],
            isIncome: isIncome
        )

        if existingCategory != nil {
            store.update(category)
        } else {
            store.add(category)
        }
        dismiss()
    }
}
