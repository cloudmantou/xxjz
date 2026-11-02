import SwiftUI
import CoreData

struct AssetBatchManagementView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \AssetItem.updatedAt, ascending: false)],
        predicate: NSPredicate(
            format: "statusRaw IN %@",
            [AssetStatus.active.rawValue, "active"]
        ),
        animation: .default
    )
    private var assets: FetchedResults<AssetItem>

    @State private var selectedAssets: Set<UUID> = []
    @State private var showingDeleteConfirmation = false
    @State private var showingDisposeConfirmation = false
    @State private var saveErrorMessage: String?

    var selectedCount: Int { selectedAssets.count }

    var body: some View {
        Group {
            if assets.isEmpty {
                EmptyStateView(
                    icon: "checklist",
                    title: "没有可管理的资产",
                    message: "使用中的资产可以进行批量操作",
                    buttonTitle: nil,
                    action: nil
                )
            } else {
                VStack(spacing: 0) {
                    // Header
                    HStack {
                        Text("已选择 \(selectedCount) 项")
                            .font(.callout)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Button(selectedCount == assets.count ? "取消全选" : "全选") {
                            if selectedCount == assets.count {
                                selectedAssets.removeAll()
                            } else {
                                selectedAssets = Set(assets.map { $0.id })
                            }
                        }
                        .font(.callout)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Color.appPageBackground)

                    List {
                        ForEach(assets) { asset in
                            HStack {
                                Image(systemName: selectedAssets.contains(asset.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedAssets.contains(asset.id) ? Color.warmTeal : .secondary)
                                    .onTapGesture {
                                        toggleSelection(asset)
                                    }

                                AssetCard(asset: asset)
                                    .allowsHitTesting(false)
                            }
                            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                            .listRowBackground(Color.clear)
                        }
                    }
                    .listStyle(.plain)

                    // Action Bar
                    if selectedCount > 0 {
                        VStack(spacing: 0) {
                            Divider()
                            HStack(spacing: 24) {
                                Button {
                                    showingDisposeConfirmation = true
                                } label: {
                                    VStack(spacing: 4) {
                                        Image(systemName: "xmark.bin.fill")
                                            .font(.title2)
                                        Text("标记报废")
                                            .font(.caption)
                                    }
                                }

                                Button(role: .destructive) {
                                    showingDeleteConfirmation = true
                                } label: {
                                    VStack(spacing: 4) {
                                        Image(systemName: "trash.fill")
                                            .font(.title2)
                                        Text("批量删除")
                                            .font(.caption)
                                    }
                                }
                            }
                            .padding(.vertical, 16)
                            .frame(maxWidth: .infinity)
                            .background(Color.appCardBackground)
                        }
                    }
                }
            }
        }
        .navigationTitle("批量管理")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("确认删除", isPresented: $showingDeleteConfirmation) {
            Button("移至恢复管理 \(selectedCount) 项资产", role: .destructive) {
                batchDelete()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("资产会移至恢复管理，附加成本和卖出记录会保留。")
        }
        .confirmationDialog("确认报废", isPresented: $showingDisposeConfirmation) {
            Button("标记为已报废") {
                batchDispose()
            }
            Button("取消", role: .cancel) {}
        }
        .persistenceSaveErrorAlert($saveErrorMessage)
    }

    private func toggleSelection(_ asset: AssetItem) {
        if selectedAssets.contains(asset.id) {
            selectedAssets.remove(asset.id)
        } else {
            selectedAssets.insert(asset.id)
        }
    }

    private func batchDelete() {
        for asset in assets where selectedAssets.contains(asset.id) {
            asset.moveToRecovery()
        }
        guard let error = PersistenceSaveCoordinator.save(viewContext) else {
            selectedAssets.removeAll()
            return
        }
        saveErrorMessage = error
    }

    private func batchDispose() {
        for asset in assets where selectedAssets.contains(asset.id) {
            asset.status = .disposed
            asset.updatedAt = Date()
        }
        guard let error = PersistenceSaveCoordinator.save(viewContext) else {
            selectedAssets.removeAll()
            return
        }
        saveErrorMessage = error
    }
}

#Preview {
    NavigationView {
        AssetBatchManagementView()
    }
    .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
