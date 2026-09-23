import SwiftUI
import CoreData

struct AssetDetailView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject var asset: AssetItem
    @State private var showingEditSheet = false
    @State private var showingExtraCostSheet = false
    @State private var showingSaleRecordSheet = false
    @State private var saveErrorMessage: String?

    private var aiSummary: String {
        if asset.status == .sold {
            let total = asset.totalCost
            let profitLoss = asset.currentValue - total
            if profitLoss >= 0 {
                return "这笔资产已实现盈利，建议保留这类品类的购买与转卖记录，形成可复用经验。"
            }
            return "这笔资产卖出略有亏损，后续可重点关注保值率和维护成本，减少重复踩坑。"
        }

        if asset.dailyCost <= 10 {
            return "当前日均成本表现健康，可以继续使用并按月复盘附加成本。"
        } else if asset.dailyCost <= 30 {
            return "当前日均成本中等，建议观察未来 30 天使用频率，再决定是否升级或置换。"
        } else {
            return "当前日均成本较高，建议评估闲置风险，必要时考虑二手变现以降低沉没成本。"
        }
    }

    var body: some View {
        List {
            // Basic Info Section
            Section("基本信息") {
                DetailRow(label: "名称", value: asset.name)
                DetailRow(label: "分类", value: L10n.tr(asset.category))
                DetailRow(label: "状态", value: asset.status.localizedTitle)
                DetailRow(label: "购买日期", value: asset.purchaseDate.mediumDateString)
                DetailRow(label: "持有天数", value: "\(asset.holdingDays)天")
            }

            // Value Section
            Section("价值信息") {
                DetailRow(label: "购买价格", value: asset.purchasePrice.currencyString)
                DetailRow(label: "附加成本", value: asset.totalExtraCost.currencyString)
                DetailRow(label: "总成本", value: asset.totalCost.currencyString)
                DetailRow(label: "当前价值", value: asset.currentValue.currencyString)

                HStack {
                    Text("日均成本")
                    Spacer()
                    Text(asset.dailyCost.dailyCostString)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.warmTeal)
                }

                HStack {
                    Text("价值变化")
                    Spacer()
                    Text(asset.currentValue >= asset.totalCost ? "+" : "")
                    Text((asset.currentValue - asset.totalCost).currencyString)
                        .fontWeight(.semibold)
                        .foregroundStyle(asset.currentValue >= asset.totalCost ? Color.profitGreen : Color.lossRed)
                }
            }

            // Extra Costs Section
            Section {
                if asset.extraCosts.isEmpty {
                    Text("暂无附加成本")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(asset.extraCosts) { cost in
                        ExtraCostRowView(cost: cost)
                    }
                    .onDelete(perform: deleteExtraCosts)
                }

                Button {
                    showingExtraCostSheet = true
                } label: {
                    Label("添加附加成本", systemImage: "plus.circle.fill")
                }
            } header: {
                Text("附加成本")
            } footer: {
                Text("累计附加成本: \(asset.totalExtraCost.currencyString)")
            }

            // Sale Records Section
            if !asset.saleRecords.isEmpty {
                Section("卖出记录") {
                    ForEach(asset.saleRecords) { record in
                        SaleRecordRowView(record: record)
                    }
                    .onDelete(perform: deleteSaleRecords)
                }
            }

            // Actions Section
            Section {
                if asset.status == .active {
                    Button {
                        showingSaleRecordSheet = true
                    } label: {
                        Label("记录卖出", systemImage: "tag.fill")
                    }

                    Button(role: .destructive) {
                        asset.status = .disposed
                        saveErrorMessage = PersistenceSaveCoordinator.save(viewContext)
                    } label: {
                        Label("标记为报废", systemImage: "trash.fill")
                    }
                }
            }

            // Notes Section
            if let notes = asset.notes, !notes.isEmpty {
                Section("备注") {
                    Text(notes)
                        .font(.body)
                }
            }

            Section("AI 资产建议（Beta）") {
                Text(aiSummary)
                    .font(.subheadline)
                    .lineSpacing(2)
            }
        }
        .navigationTitle("资产详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("编辑") {
                    showingEditSheet = true
                }
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            AssetFormView(mode: .edit(asset))
        }
        .sheet(isPresented: $showingExtraCostSheet) {
            ExtraCostFormView(asset: asset)
        }
        .sheet(isPresented: $showingSaleRecordSheet) {
            SaleRecordFormView(asset: asset)
        }
        .persistenceSaveErrorAlert($saveErrorMessage)
    }

    private func deleteExtraCosts(at offsets: IndexSet) {
        for index in offsets {
            let cost = asset.extraCosts[index]
            viewContext.delete(cost)
        }
        saveErrorMessage = PersistenceSaveCoordinator.save(viewContext)
    }

    private func deleteSaleRecords(at offsets: IndexSet) {
        for index in offsets {
            let record = asset.saleRecords[index]
            viewContext.delete(record)
        }
        asset.status = .active
        saveErrorMessage = PersistenceSaveCoordinator.save(viewContext)
    }
}

struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
        }
    }
}

struct ExtraCostRowView: View {
    let cost: AssetExtraCost

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(cost.costType)
                    .font(.headline)
                Spacer()
                Text(cost.amount.currencyString)
                    .font(.callout)
                    .fontWeight(.semibold)
            }
            Text(cost.date.mediumDateString)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let notes = cost.notes, !notes.isEmpty {
                Text(notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct SaleRecordRowView: View {
    let record: AssetSaleRecord

    var profitLoss: Double {
        record.salePrice - (record.asset?.totalCost ?? 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(record.saleDate.mediumDateString)
                    .font(.headline)
                Spacer()
                VStack(alignment: .trailing) {
                    Text(record.salePrice.currencyString)
                        .font(.callout)
                        .fontWeight(.semibold)
                    Text(profitLoss >= 0 ? "盈利" : "亏损")
                        .font(.caption)
                        .foregroundStyle(profitLoss >= 0 ? Color.profitGreen : Color.lossRed)
                }
            }
            if let platform = record.platform {
                Text(platform)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    NavigationView {
        AssetDetailView(asset: AssetItem(
            context: PersistenceController.preview.container.viewContext,
            name: "iPhone 15 Pro Max",
            category: "电子产品",
            purchasePrice: 9999,
            currentValue: 8000,
            status: .active
        ))
    }
    .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
