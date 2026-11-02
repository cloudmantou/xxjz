import SwiftUI
import CoreData

struct AssetRecoveryView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \AssetItem.updatedAt, ascending: false)],
        animation: .default
    )
    private var assets: FetchedResults<AssetItem>

    @State private var assetPendingPermanentDeletion: AssetItem?
    @State private var showingPermanentDeleteConfirmation = false
    @State private var saveErrorMessage: String?

    private var retiredAssets: [AssetItem] {
        assets.filter { $0.status != .active }
    }

    private var deletedAssets: [AssetItem] {
        retiredAssets.filter { $0.status == .deleted }
    }

    var soldAssets: [AssetItem] {
        retiredAssets.filter { $0.status == .sold }
    }

    var disposedAssets: [AssetItem] {
        retiredAssets.filter { $0.status == .disposed }
    }

    var body: some View {
        Group {
            if retiredAssets.isEmpty {
                EmptyStateView(
                    icon: "arrow.uturn.backward.circle",
                    title: "没有可恢复的资产",
                    message: "已删除、卖出或报废的资产会显示在这里",
                    buttonTitle: nil,
                    action: nil
                )
            } else {
                List {
                    if !deletedAssets.isEmpty {
                        Section("已删除 (\(deletedAssets.count))") {
                            ForEach(deletedAssets) { asset in
                                RecoveryRow(
                                    asset: asset,
                                    onRecover: { recoverAsset(asset) },
                                    onDelete: { requestPermanentDelete(asset) }
                                )
                            }
                        }
                    }

                    if !soldAssets.isEmpty {
                        Section("已卖出 (\(soldAssets.count))") {
                            ForEach(soldAssets) { asset in
                                RecoveryRow(
                                    asset: asset,
                                    onRecover: { recoverAsset(asset) },
                                    onDelete: { requestPermanentDelete(asset) }
                                )
                            }
                        }
                    }

                    if !disposedAssets.isEmpty {
                        Section("已报废 (\(disposedAssets.count))") {
                            ForEach(disposedAssets) { asset in
                                RecoveryRow(
                                    asset: asset,
                                    onRecover: { recoverAsset(asset) },
                                    onDelete: { requestPermanentDelete(asset) }
                                )
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("资产恢复")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("永久删除资产？", isPresented: $showingPermanentDeleteConfirmation) {
            Button("永久删除", role: .destructive) {
                permanentlyDeletePendingAsset()
            }
            Button("取消", role: .cancel) {
                assetPendingPermanentDeletion = nil
            }
        } message: {
            Text("资产及其附加成本、卖出记录将被永久删除，无法恢复。")
        }
        .persistenceSaveErrorAlert($saveErrorMessage)
    }

    private func recoverAsset(_ asset: AssetItem) {
        if asset.status == .deleted {
            asset.restoreFromRecovery()
        } else {
            asset.status = .active
            asset.updatedAt = Date()
        }
        saveChanges()
    }

    private func requestPermanentDelete(_ asset: AssetItem) {
        assetPendingPermanentDeletion = asset
        showingPermanentDeleteConfirmation = true
    }

    private func permanentlyDeletePendingAsset() {
        guard let asset = assetPendingPermanentDeletion else { return }
        viewContext.delete(asset)
        if saveChanges() {
            assetPendingPermanentDeletion = nil
        }
    }

    @discardableResult
    private func saveChanges() -> Bool {
        guard let error = PersistenceSaveCoordinator.save(viewContext) else { return true }
        saveErrorMessage = error
        return false
    }
}

struct RecoveryRow: View {
    let asset: AssetItem
    let onRecover: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail
            if let imageData = asset.imageData, let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 50, height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.1))
                    .frame(width: 50, height: 50)
                    .overlay {
                        Image(systemName: "creditcard.fill")
                            .foregroundStyle(.secondary)
                    }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(asset.name)
                        .font(.headline)
                    if asset.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                    }
                }
                Text(L10n.tr(asset.category))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Text(asset.currentValue.currencyString)
                        .font(.callout)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.warmTeal)
                    Spacer()
                    StatusBadge(status: asset.status)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                onRecover()
            } label: {
                Label("恢复", systemImage: "arrow.uturn.backward")
            }
            .tint(.warmTeal)
        }
    }
}

#Preview {
    NavigationView {
        AssetRecoveryView()
    }
    .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
