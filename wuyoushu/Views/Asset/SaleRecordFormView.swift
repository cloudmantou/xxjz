import SwiftUI
import CoreData

struct SaleRecordFormView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    let asset: AssetItem

    @State private var salePrice: String = ""
    @State private var saleDate: Date = Date()
    @State private var platform: String = AssetSaleRecord.platforms.first ?? ""
    @State private var notes: String = ""
    @State private var saveErrorMessage: String?

    var isValid: Bool {
        Double(salePrice) != nil && (Double(salePrice) ?? 0) > 0
    }

    var profitLoss: Double {
        (Double(salePrice) ?? 0) - asset.totalCost
    }

    var body: some View {
        NavigationView {
            Form {
                Section("卖出信息") {
                    HStack {
                        Text("卖出价格")
                        Spacer()
                        TextField("0.00", text: $salePrice)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }

                    DatePicker("卖出日期", selection: $saleDate, displayedComponents: .date)

                    Picker("平台", selection: $platform) {
                        ForEach(AssetSaleRecord.platforms, id: \.self) { p in
                            Text(p).tag(p)
                        }
                    }
                }

                Section("预估盈亏") {
                    HStack {
                        Text("成本")
                        Spacer()
                        Text(asset.totalCost.currencyString)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("盈亏")
                        Spacer()
                        Text(profitLoss >= 0 ? "+" : "")
                        Text(profitLoss.currencyString)
                            .fontWeight(.semibold)
                            .foregroundStyle(profitLoss >= 0 ? Color.profitGreen : Color.lossRed)
                    }
                }

                Section("备注") {
                    TextField("选填", text: $notes)
                }
            }
            .navigationTitle("记录卖出")
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
                // Pre-fill with current value
                salePrice = String(format: "%.2f", asset.currentValue)
            }
        }
    }

    private func save() {
        let priceValue = Double(salePrice) ?? 0

        let record = AssetSaleRecord(
            context: viewContext,
            saleDate: saleDate,
            salePrice: priceValue,
            platform: platform.isEmpty ? nil : platform,
            notes: notes.isEmpty ? nil : notes
        )

        record.asset = asset
        asset.saleRecords.append(record)
        asset.status = .sold
        asset.currentValue = priceValue
        asset.updatedAt = Date()

        guard let error = PersistenceSaveCoordinator.save(viewContext) else {
            dismiss()
            return
        }
        saveErrorMessage = error
    }
}

#Preview {
    SaleRecordFormView(asset: AssetItem(
        context: PersistenceController.preview.container.viewContext,
        name: "iPhone",
        category: "电子产品",
        purchasePrice: 9999,
        currentValue: 8000
    ))
    .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
