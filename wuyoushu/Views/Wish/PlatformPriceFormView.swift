import SwiftUI
import CoreData

struct PlatformPriceFormView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    let item: WishlistItem

    @State private var platform: String = WishlistPlatformPrice.platforms.first ?? ""
    @State private var price: String = ""
    @State private var url: String = ""
    @State private var saveErrorMessage: String?

    var isValid: Bool {
        !platform.isEmpty && Double(price) != nil && (Double(price) ?? 0) > 0
    }

    var body: some View {
        NavigationView {
            Form {
                Section("平台信息") {
                    Picker("平台", selection: $platform) {
                        ForEach(WishlistPlatformPrice.platforms, id: \.self) { p in
                            Text(p).tag(p)
                        }
                    }

                    HStack {
                        Text("价格")
                        Spacer()
                        TextField("0.00", text: $price)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }

                    TextField("商品链接 (选填)", text: $url)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                }

                if let priceValue = Double(price) {
                    Section("价格对比") {
                        HStack {
                            Text("目标价格")
                            Spacer()
                            Text(item.targetPrice.currencyString)
                                .foregroundStyle(.secondary)
                        }

                        HStack {
                            Text("当前价格")
                            Spacer()
                            Text(priceValue.currencyString)
                                .fontWeight(.semibold)
                                .foregroundStyle(priceValue <= item.targetPrice ? Color.profitGreen : Color.warningOrange)
                        }

                        HStack {
                            Text("状态")
                            Spacer()
                            Text(priceValue <= item.targetPrice ? "达到目标" : "未达目标")
                                .foregroundStyle(priceValue <= item.targetPrice ? Color.profitGreen : Color.secondary)
                        }
                    }
                }
            }
            .navigationTitle("添加平台价格")
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
        }
    }

    private func save() {
        let priceValue = Double(price) ?? 0

        let platformPrice = WishlistPlatformPrice(
            context: viewContext,
            platform: platform,
            price: priceValue,
            url: url.isEmpty ? nil : url
        )

        platformPrice.wishlistItem = item
        item.platformPrices.append(platformPrice)
        item.updatedAt = Date()

        guard let error = PersistenceSaveCoordinator.save(viewContext) else {
            dismiss()
            return
        }
        saveErrorMessage = error
    }
}

#Preview {
    PlatformPriceFormView(item: WishlistItem(
        context: PersistenceController.preview.container.viewContext,
        name: "iPhone",
        category: "电子产品",
        targetPrice: 8000
    ))
    .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
