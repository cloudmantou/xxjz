import SwiftUI
import CoreData

enum AssetFormMode {
    case add
    case edit(AssetItem)
    case addFromWish(name: String, category: String, purchasePrice: Double)
}

struct AssetFormView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    let mode: AssetFormMode

    @State private var name: String = ""
    @State private var category: String = Constants.AssetCategory.all.first ?? ""
    @State private var purchaseDate: Date = Date()
    @State private var purchasePrice: String = ""
    @State private var currentValue: String = ""
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

    var isFromWish: Bool {
        if case .addFromWish = mode { return true }
        return false
    }

    var asset: AssetItem? {
        if case .edit(let item) = mode { return item }
        return nil
    }

    private var trimmedCurrentValue: String {
        currentValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isValid: Bool {
        !name.isEmpty &&
        !category.isEmpty &&
        Double(purchasePrice) != nil &&
        (trimmedCurrentValue.isEmpty || Double(trimmedCurrentValue) != nil)
    }

    var body: some View {
        NavigationView {
            Form {
                Section("基本信息") {
                    TextField("资产名称", text: $name)

                    Picker("分类", selection: $category) {
                        ForEach(Constants.AssetCategory.all, id: \.self) { cat in
                            Text(L10n.tr(cat)).tag(cat)
                        }
                    }

                    DatePicker("购买日期", selection: $purchaseDate, displayedComponents: .date)
                }

                Section {
                    HStack {
                        Text("购买价格")
                        Spacer()
                        TextField("0.00", text: $purchasePrice)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }

                    HStack {
                        Text("当前价值")
                        Spacer()
                        TextField("0.00", text: $currentValue)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                } header: {
                    Text("价格信息")
                } footer: {
                    Text("当前价值可不填，留空时默认使用购买价格。")
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
            .navigationTitle(isEditing ? "编辑资产" : (isFromWish ? "心愿转为资产" : "添加资产"))
            .navigationBarTitleDisplayMode(.inline)
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
            .alert("保存失败", isPresented: Binding(
                get: { saveErrorMessage != nil },
                set: { newValue in
                    if !newValue { saveErrorMessage = nil }
                }
            )) {
                Button("知道了", role: .cancel) {
                    saveErrorMessage = nil
                }
            } message: {
                Text(saveErrorMessage ?? "请稍后重试")
            }
        }
    }

    private func loadData() {
        if let asset = asset {
            name = asset.name
            category = asset.category
            purchaseDate = asset.purchaseDate
            purchasePrice = String(format: "%.2f", asset.purchasePrice)
            currentValue = String(format: "%.2f", asset.currentValue)
            notes = asset.notes ?? ""
            imageData = asset.imageData
        } else if case .addFromWish(let wishName, let wishCategory, let wishPrice) = mode {
            name = wishName
            category = wishCategory
            purchasePrice = String(format: "%.2f", wishPrice)
            currentValue = ""
            purchaseDate = Date()
        }
    }

    private func save() {
        let priceValue = Double(purchasePrice) ?? 0
        let resolvedCurrentValue: Double
        if trimmedCurrentValue.isEmpty {
            resolvedCurrentValue = asset?.currentValue ?? priceValue
        } else {
            resolvedCurrentValue = Double(trimmedCurrentValue) ?? priceValue
        }

        if let asset = asset {
            // Update existing
            asset.name = name
            asset.category = category
            asset.purchaseDate = purchaseDate
            asset.purchasePrice = priceValue
            asset.currentValue = resolvedCurrentValue
            asset.notes = notes.isEmpty ? nil : notes
            asset.imageData = imageData
            asset.updatedAt = Date()
        } else {
            // Create new
            _ = AssetItem(
                context: viewContext,
                name: name,
                category: category,
                purchaseDate: purchaseDate,
                purchasePrice: priceValue,
                currentValue: resolvedCurrentValue,
                notes: notes.isEmpty ? nil : notes,
                imageData: imageData
            )
        }

        do {
            try viewContext.save()
            dismiss()
        } catch {
            viewContext.rollback()
            saveErrorMessage = error.localizedDescription
        }
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
            if let candidatePrice = parsePrice(from: text) {
                if purchasePrice.isEmpty {
                    purchasePrice = String(format: "%.2f", candidatePrice)
                }
                if currentValue.isEmpty {
                    currentValue = String(format: "%.2f", candidatePrice)
                }
            }
            if let candidateDate = parseDate(from: text) {
                purchaseDate = candidateDate
            }
            if !name.isEmpty {
                if let suggestedCategory = try? await MockAIAnalysisService.shared.suggestCategory(itemName: name),
                   Constants.AssetCategory.all.contains(suggestedCategory) {
                    category = suggestedCategory
                }
            }

            recognitionMessage = "已识别并填入可用字段，你可以再手动调整。"
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

    private func parseDate(from text: String) -> Date? {
        let pattern = #"([0-9]{4})[-/.年]([0-9]{1,2})[-/.月]([0-9]{1,2})"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsText = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: nsText.length)),
              match.numberOfRanges == 4 else {
            return nil
        }

        let year = Int(nsText.substring(with: match.range(at: 1)))
        let month = Int(nsText.substring(with: match.range(at: 2)))
        let day = Int(nsText.substring(with: match.range(at: 3)))

        guard let year, let month, let day else { return nil }
        return Date.from(year: year, month: month, day: day)
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
    AssetFormView(mode: .add)
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}

#Preview("Edit") {
    AssetFormView(mode: .edit(AssetItem(
        context: PersistenceController.preview.container.viewContext,
        name: "iPhone",
        category: "电子产品",
        purchasePrice: 9999,
        currentValue: 8000
    )))
    .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
