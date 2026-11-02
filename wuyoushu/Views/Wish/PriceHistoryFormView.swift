import SwiftUI
import CoreData

struct PriceHistoryFormView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    let item: WishlistItem

    @State private var price: String = ""
    @State private var recordedAt: Date = Date()
    @State private var saveErrorMessage: String?

    var isValid: Bool {
        Double(price) != nil && (Double(price) ?? 0) > 0
    }

    var body: some View {
        NavigationView {
            Form {
                Section("价格记录") {
                    HStack {
                        Text("价格")
                        Spacer()
                        TextField("0.00", text: $price)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }

                    DatePicker("记录日期", selection: $recordedAt, displayedComponents: .date)
                }

                Section {
                    HStack {
                        Text("当前最低价")
                        Spacer()
                        if let lowestPrice = item.currentLowestPrice {
                            Text(lowestPrice.currencyString)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("暂无")
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack {
                        Text("目标价格")
                        Spacer()
                        Text(item.targetPrice.currencyString)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("参考信息")
                }
            }
            .navigationTitle("记录价格")
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

        let history = WishlistPriceHistory(
            context: viewContext,
            price: priceValue,
            recordedAt: recordedAt
        )

        history.wishlistItem = item
        item.priceHistories.append(history)
        item.updatedAt = Date()

        guard let error = PersistenceSaveCoordinator.save(viewContext) else {
            dismiss()
            return
        }
        saveErrorMessage = error
    }
}

#Preview {
    PriceHistoryFormView(item: WishlistItem(
        context: PersistenceController.preview.container.viewContext,
        name: "iPhone",
        category: "电子产品",
        targetPrice: 8000
    ))
    .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
