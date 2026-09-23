import SwiftUI
import CoreData

enum WishlistFormMode {
    case add
    case edit(WishlistItem)
}

struct WishlistFormView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    let mode: WishlistFormMode

    @State private var name: String = ""
    @State private var category: String = WishlistItem.categories.first ?? ""
    @State private var targetPrice: String = ""
    @State private var targetDailyCost: String = ""
    @State private var priority: Int = 3
    @State private var notes: String = ""
    @State private var showingPhotoPicker = false
    @State private var imageData: Data?
    @State private var isRecognizing = false
    @State private var recognitionMessage: String?
    @State private var saveErrorMessage: String?

    var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    var item: WishlistItem? {
        if case .edit(let i) = mode { return i }
        return nil
    }

    var isValid: Bool {
        !name.isEmpty &&
        !category.isEmpty &&
        Double(targetPrice) != nil &&
        (Double(targetPrice) ?? 0) > 0
    }

    var body: some View {
        NavigationView {
            Form {
                Section("基本信息") {
                    TextField("物品名称", text: $name)

                    Picker("分类", selection: $category) {
                        ForEach(WishlistItem.categories, id: \.self) { cat in
                            Text(L10n.tr(cat)).tag(cat)
                        }
                    }

                    Picker("优先级", selection: $priority) {
                        ForEach(WishlistItem.priorities, id: \.0) { p in
                            HStack {
                                ForEach(0..<5) { index in
                                    Circle()
                                        .fill(index < p.0 ? Color.warningOrange : Color.gray.opacity(0.3))
                                        .frame(width: 8, height: 8)
                                }
                                Text(L10n.tr(p.1))
                            }
                            .tag(p.0)
                        }
                    }
                }

                Section("价格信息") {
                    HStack {
                        Text("目标价格")
                        Spacer()
                        TextField("0.00", text: $targetPrice)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }

                    HStack {
                        Text("目标日均价格")
                        Spacer()
                        TextField("0.00", text: $targetDailyCost)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                }

                Section("照片") {
                    Button {
                        showingPhotoPicker = true
                    } label: {
                        if let imageData = imageData, let uiImage = UIImage(data: imageData) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                                .frame(height: 200)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        } else {
                            Label("选择照片", systemImage: "photo.badge.plus")
                        }
                    }
                    .buttonStyle(.plain)
                    .sheet(isPresented: $showingPhotoPicker) {
                        LegacyPhotoPicker { data in
                            showingPhotoPicker = false
                            guard let data else { return }
                            imageData = data
                            Task {
                                await recognizeAndAutofill()
                            }
                        }
                    }

                    if imageData != nil {
                        Button("移除照片", role: .destructive) {
                            imageData = nil
                            recognitionMessage = nil
                        }
                    }
                }

                if imageData != nil {
                    Section("图片识别") {
                        Button {
                            Task {
                                await recognizeAndAutofill()
                            }
                        } label: {
                            Label(isRecognizing ? "识别中..." : "重新识别并自动填入", systemImage: "text.viewfinder")
                        }
                        .disabled(isRecognizing)

                        if let recognitionMessage {
                            Text(recognitionMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("备注") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 100)
                }
            }
            .navigationTitle(isEditing ? "编辑心愿" : "添加心愿")
            .navigationBarTitleDisplayMode(.inline)
            .persistenceSaveErrorAlert($saveErrorMessage)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        save()
                    }
                    .disabled(!isValid)
                }
            }
            .onAppear {
                loadData()
            }
        }
    }

    private func loadData() {
        if let item = item {
            name = item.name
            category = item.category
            targetPrice = String(item.targetPrice)
            targetDailyCost = item.targetDailyCost > 0 ? String(item.targetDailyCost) : ""
            priority = Int(item.priority)
            notes = item.notes ?? ""
            imageData = item.imageData
        }
    }

    private func save() {
        let priceValue = Double(targetPrice) ?? 0
        let dailyCostValue = Double(targetDailyCost) ?? 0

        if let item = item {
            // Update existing
            item.name = name
            item.category = category
            item.targetPrice = priceValue
            item.targetDailyCost = dailyCostValue
            item.priority = Int16(priority)
            item.notes = notes.isEmpty ? nil : notes
            item.imageData = imageData
            item.updatedAt = Date()
        } else {
            // Create new
            _ = WishlistItem(
                context: viewContext,
                name: name,
                category: category,
                targetPrice: priceValue,
                targetDailyCost: dailyCostValue,
                priority: priority,
                notes: notes.isEmpty ? nil : notes,
                imageData: imageData
            )
        }

        guard let error = PersistenceSaveCoordinator.save(viewContext) else {
            dismiss()
            return
        }
        saveErrorMessage = error
    }

    @MainActor
    private func recognizeAndAutofill() async {
        guard let imageData, let image = UIImage(data: imageData) else { return }
        isRecognizing = true
        defer { isRecognizing = false }

        do {
            let text = try await ProductionOCRService.shared.recognizeText(from: image)

            if let candidateName = parseItemName(from: text), name.isEmpty {
                name = candidateName
            }
            if let candidatePrice = parsePrice(from: text), targetPrice.isEmpty {
                // 给用户一个更容易成交的默认目标价（识别价打 9 折）
                targetPrice = String(format: "%.2f", candidatePrice * 0.9)
            }
            if !name.isEmpty {
                if let suggestedCategory = try? await MockAIAnalysisService.shared.suggestCategory(itemName: name),
                   WishlistItem.categories.contains(suggestedCategory) {
                    category = suggestedCategory
                }
            }

            recognitionMessage = "已自动填入名称和价格建议，可继续微调。"
        } catch {
            recognitionMessage = "识别失败，请手动输入或更换清晰图片。"
        }
    }

    private func parseItemName(from text: String) -> String? {
        let patterns = [
            #"商品名称[:：]\s*([^\n]+)"#,
            #"品名[:：]\s*([^\n]+)"#,
            #"名称[:：]\s*([^\n]+)"#
        ]

        for pattern in patterns {
            if let match = firstRegexMatch(pattern: pattern, in: text)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !match.isEmpty {
                return match
            }
        }

        return text
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty && $0.count <= 40 })
    }

    private func parsePrice(from text: String) -> Double? {
        let pattern = #"(?:¥|￥)?\s*([0-9]{1,7}(?:\.[0-9]{1,2})?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))

        let candidates = matches.compactMap { match -> Double? in
            guard match.numberOfRanges > 1 else { return nil }
            return Double(nsText.substring(with: match.range(at: 1)))
        }
        .filter { $0 > 0 }

        return candidates.max()
    }

    private func firstRegexMatch(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsText = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: nsText.length)),
              match.numberOfRanges > 1 else {
            return nil
        }
        return nsText.substring(with: match.range(at: 1))
    }
}

#Preview("Add") {
    WishlistFormView(mode: .add)
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}

#Preview("Edit") {
    WishlistFormView(mode: .edit(WishlistItem(
        context: PersistenceController.preview.container.viewContext,
        name: "iPhone 16 Pro",
        category: "电子产品",
        targetPrice: 8000,
        priority: 5
    )))
    .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
