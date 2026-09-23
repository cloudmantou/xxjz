import SwiftUI
import CoreData

struct ExtraCostFormView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    let asset: AssetItem

    @State private var costType: String = AssetExtraCost.costTypes.first ?? ""
    @State private var amount: String = ""
    @State private var date: Date = Date()
    @State private var notes: String = ""

    var isValid: Bool {
        !costType.isEmpty && Double(amount) != nil && (Double(amount) ?? 0) > 0
    }

    var body: some View {
        NavigationView {
            Form {
                Section("费用信息") {
                    Picker("费用类型", selection: $costType) {
                        ForEach(AssetExtraCost.costTypes, id: \.self) { type in
                            Text(type).tag(type)
                        }
                    }

                    HStack {
                        Text("金额")
                        Spacer()
                        TextField("0.00", text: $amount)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }

                    DatePicker("日期", selection: $date, displayedComponents: .date)
                }

                Section("备注") {
                    TextField("选填", text: $notes)
                }
            }
            .navigationTitle("添加附加成本")
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
        }
    }

    private func save() {
        let amountValue = Double(amount) ?? 0

        let cost = AssetExtraCost(
            context: viewContext,
            costType: costType,
            amount: amountValue,
            date: date,
            notes: notes.isEmpty ? nil : notes
        )

        cost.asset = asset
        asset.extraCosts.append(cost)
        asset.updatedAt = Date()

        try? viewContext.save()
        dismiss()
    }
}

#Preview {
    ExtraCostFormView(asset: AssetItem(
        context: PersistenceController.preview.container.viewContext,
        name: "iPhone",
        category: "电子产品",
        purchasePrice: 9999,
        currentValue: 8000
    ))
    .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
