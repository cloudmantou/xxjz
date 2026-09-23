import SwiftUI
import CoreData

struct AssetListView: View {
    @Environment(\.bottomBarInset) private var bottomBarInset: CGFloat
    private enum AssetFilterToken: Hashable {
        case all
        case favorites
        case status(AssetStatus)
    }

    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \AssetItem.updatedAt, ascending: false)],
        animation: .default
    )
    private var assets: FetchedResults<AssetItem>
    @State private var showingAddSheet = false
    @State private var searchText = ""
    @State private var selectedStatus: AssetStatus? = nil
    @State private var showFavoritesOnly = false
    @Namespace private var filterChipNamespace

    private var screenWidth: CGFloat {
        UIScreen.main.bounds.width
    }

    private var pageHorizontalPadding: CGFloat {
        Constants.Layout.pageHorizontalPadding(for: screenWidth)
    }

    private var sectionSpacing: CGFloat {
        Constants.Layout.sectionSpacing(for: screenWidth)
    }

    private var heroCardMinHeight: CGFloat {
        Constants.Layout.heroCardMinHeight(for: screenWidth)
    }

    private var activeFilterToken: AssetFilterToken {
        if showFavoritesOnly { return .favorites }
        if let selectedStatus { return .status(selectedStatus) }
        return .all
    }

    var filteredAssets: [AssetItem] {
        var result: [AssetItem] = Array(assets)

        if !searchText.isEmpty {
            result = result.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }

        if let status = selectedStatus {
            result = result.filter { $0.status == status }
        }

        if showFavoritesOnly {
            result = result.filter { $0.isFavorite }
        }

        return result
    }

    var totalValue: Double {
        filteredAssets
            .filter { $0.status == .active }
            .reduce(0) { $0 + $1.currentValue }
    }

    var totalDailyCost: Double {
        filteredAssets
            .filter { $0.status == .active }
            .reduce(0) { $0 + $1.dailyCost }
    }

    var body: some View {
        NavigationView {
            Group {
                if assets.isEmpty {
                    EmptyStateView(
                        icon: "creditcard.fill",
                        title: "还没有资产记录",
                        message: "先记下第一件物品，后续价值变化会自动帮你追踪",
                        buttonTitle: "马上添加"
                    ) {
                        showingAddSheet = true
                    }
                } else {
                    ScrollView {
                        VStack(spacing: sectionSpacing) {
                        // ── 资产总览 Hero Card ──
                        ZStack {
                            RoundedRectangle(cornerRadius: CardRadius.large, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.heroGradientTop, Color.heroGradientBottom],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )

                            VStack(spacing: 12) {
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("在用资产总价值")
                                            .font(.system(size: 12, weight: .medium, design: .rounded))
                                            .foregroundStyle(Color.white.opacity(0.78))
                                        Text(totalValue.currencyString)
                                            .font(.system(size: 30, weight: .bold, design: .rounded))
                                            .foregroundStyle(Color.white)
                                            .monospacedDigit()
                                            .minimumScaleFactor(0.7)
                                            .lineLimit(1)
                                    }

                                    Spacer()

                                    // 资产数量徽章
                                    VStack(spacing: 2) {
                                        Text("\(filteredAssets.filter { $0.status == .active }.count)")
                                            .font(.system(size: 22, weight: .black, design: .rounded))
                                            .foregroundStyle(Color.white)
                                        Text("件在用")
                                            .font(.system(size: 10, weight: .medium, design: .rounded))
                                            .foregroundStyle(Color.white.opacity(0.75))
                                    }
                                    .frame(width: 56, height: 56)
                                    .background(Color.white.opacity(0.18))
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                }

                                // 分割线
                                Rectangle()
                                    .fill(Color.white.opacity(0.2))
                                    .frame(height: 0.5)

                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("日均成本")
                                            .font(.system(size: 11, design: .rounded))
                                            .foregroundStyle(Color.white.opacity(0.72))
                                        Text(totalDailyCost.dailyCostString)
                                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                                            .foregroundStyle(Color.white)
                                            .monospacedDigit()
                                    }

                                    Spacer()

                                    NavigationLink {
                                        AssetsStatisticsView()
                                    } label: {
                                        HStack(spacing: 4) {
                                            Text("查看统计")
                                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                            Image(systemName: "chevron.right")
                                                .font(.system(size: 10, weight: .bold))
                                        }
                                        .foregroundStyle(Color.white)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 7)
                                        .background(Color.white.opacity(0.2))
                                        .clipShape(Capsule())
                                    }
                                }
                            }
                            .padding(18)
                        }
                        .frame(minHeight: heroCardMinHeight)
                        .padding(.horizontal, pageHorizontalPadding)

                            // Filter Chips
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    animatedFilterChip(title: "全部", token: .all) {
                                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                        selectedStatus = nil
                                        showFavoritesOnly = false
                                        }
                                    }

                                    animatedFilterChip(title: "收藏", token: .favorites) {
                                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                            showFavoritesOnly.toggle()
                                            if showFavoritesOnly {
                                                selectedStatus = nil
                                            }
                                        }
                                    }

                                    ForEach(AssetStatus.allCases, id: \.self) { status in
                                        animatedFilterChip(
                                            title: status.localizedTitle,
                                            token: .status(status)
                                        ) {
                                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                            selectedStatus = status
                                            showFavoritesOnly = false
                                            }
                                        }
                                    }
                                }
                                .padding(.horizontal, pageHorizontalPadding)
                            }

                            // Asset List
                            LazyVStack(spacing: 10) {
                                ForEach(filteredAssets) { asset in
                                    NavigationLink(destination: AssetDetailView(asset: asset)) {
                                        AssetCard(asset: asset)
                                    }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        favoriteButton(for: asset)
                                        Divider()
                                        Button(role: .destructive) {
                                            viewContext.delete(asset)
                                            try? viewContext.save()
                                        } label: {
                                            Label("删除", systemImage: "trash")
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, pageHorizontalPadding)
                        }
                        .padding(.top, 12)
                        .padding(.bottom, 12 + bottomBarInset)
                    }
                    .background(Color.appPageBackground)
                }
            }
            .navigationTitle("资产")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "搜索资产")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 16) {
                        NavigationLink {
                            AssetsStatisticsView()
                        } label: {
                            Image(systemName: "chart.bar.xaxis")
                        }

                        Menu {
                            NavigationLink(destination: AssetBatchManagementView()) {
                                Label("批量管理", systemImage: "checklist")
                            }

                            NavigationLink(destination: AssetRecoveryView()) {
                                Label("资产恢复", systemImage: "arrow.uturn.backward.circle")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }

                        Button {
                            showingAddSheet = true
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                AssetFormView(mode: .add)
            }
        }
    }

    @ViewBuilder
    private func favoriteButton(for asset: AssetItem) -> some View {
        Button {
            asset.isFavorite.toggle()
            asset.updatedAt = Date()
            try? viewContext.save()
        } label: {
            Label(
                asset.isFavorite ? "取消收藏" : "添加收藏",
                systemImage: asset.isFavorite ? "star.slash" : "star"
            )
        }
    }

    private func animatedFilterChip(title: String, token: AssetFilterToken, action: @escaping () -> Void) -> some View {
        let isSelected = activeFilterToken == token

        return Button(action: action) {
            ZStack {
                if isSelected {
                    Capsule()
                        .fill(Color.warmTeal)
                        .matchedGeometryEffect(id: "assetFilterChipBackground", in: filterChipNamespace)
                }

                Text(title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? .white : .primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            }
            .background(
                Capsule()
                    .fill(isSelected ? Color.clear : Color.secondaryCardBackground)
            )
            .overlay(
                Capsule()
                    .stroke(isSelected ? Color.clear : Color.borderSoft, lineWidth: 0.6)
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    AssetListView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
