import SwiftUI
import CoreData

struct WishlistView: View {
    @Environment(\.bottomBarInset) private var bottomBarInset: CGFloat
    enum SortOption: CaseIterable {
        case priority
        case name
        case targetPrice
        case createdAt

        var title: String {
            switch self {
            case .priority: return L10n.tr("优先级")
            case .name: return L10n.tr("名称")
            case .targetPrice: return L10n.tr("目标价")
            case .createdAt: return L10n.tr("添加时间")
            }
        }
    }

    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \WishlistItem.createdAt, ascending: false)],
        animation: .default
    )
    private var items: FetchedResults<WishlistItem>
    @State private var showingAddSheet = false
    @State private var searchText = ""
    @State private var sortOption: SortOption = .priority
    @State private var saveErrorMessage: String?

    private var screenWidth: CGFloat {
        UIScreen.main.bounds.width
    }

    private var pageHorizontalPadding: CGFloat {
        Constants.Layout.pageHorizontalPadding(for: screenWidth)
    }

    private var sectionSpacing: CGFloat {
        Constants.Layout.sectionSpacing(for: screenWidth)
    }

    var filteredItems: [WishlistItem] {
        var result: [WishlistItem] = Array(items)

        if !searchText.isEmpty {
            result = result.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }

        switch sortOption {
        case .priority:
            return result.sorted { $0.priority > $1.priority }
        case .name:
            return result.sorted { $0.name < $1.name }
        case .targetPrice:
            return result.sorted { $0.targetPrice < $1.targetPrice }
        case .createdAt:
            return result.sorted { $0.createdAt > $1.createdAt }
        }
    }

    var unpurchasedItems: [WishlistItem] {
        filteredItems.filter { !$0.isPurchased }
    }

    var purchasedItems: [WishlistItem] {
        filteredItems.filter { $0.isPurchased }
    }

    var totalTargetValue: Double {
        unpurchasedItems.reduce(0) { $0 + $1.targetPrice }
    }

    var averageTargetPrice: Double {
        guard !unpurchasedItems.isEmpty else { return 0 }
        return totalTargetValue / Double(unpurchasedItems.count)
    }

    var body: some View {
        NavigationView {
            Group {
                if items.isEmpty {
                    EmptyStateView(
                        icon: "heart.fill",
                        title: "心愿清单还是空的",
                        message: "先把喜欢的东西放进来，降价到位时就不会错过",
                        buttonTitle: "新建心愿"
                    ) {
                        showingAddSheet = true
                    }
                } else {
                    ScrollView {
                        VStack(spacing: sectionSpacing) {
                            // Summary Card
                            HStack {
                                VStack(alignment: .leading) {
                                    Text("目标总价")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(totalTargetValue.currencyString)
                                        .font(.title2)
                                        .fontWeight(.bold)
                                        .foregroundStyle(Color.warmCoral)
                                        .monospacedDigit()
                                }

                                Spacer()

                                VStack(alignment: .trailing) {
                                    Text("平均目标价")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(averageTargetPrice.currencyString)
                                        .font(.title3)
                                        .fontWeight(.semibold)
                                }
                            }
                            .padding(16)
                            .cardStyle()

                            // Unpurchased Items
                            if !unpurchasedItems.isEmpty {
                                wishSection(title: "\(L10n.tr("待购买")) (\(unpurchasedItems.count))", items: unpurchasedItems)
                            }

                            // Purchased Items
                            if !purchasedItems.isEmpty {
                                wishSection(title: "\(L10n.tr("已购买")) (\(purchasedItems.count))", items: purchasedItems)
                            }
                        }
                        .padding(.horizontal, pageHorizontalPadding)
                        .padding(.top, 12)
                        .padding(.bottom, 12 + bottomBarInset)
                    }
                    .background(Color.appPageBackground)
                }
            }
            .navigationTitle("心愿清单")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "搜索心愿")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        ForEach(SortOption.allCases, id: \.self) { option in
                            Button {
                                sortOption = option
                            } label: {
                                HStack {
                                    Text(option.title)
                                    if sortOption == option {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                WishlistFormView(mode: .add)
            }
            .persistenceSaveErrorAlert($saveErrorMessage)
        }
    }

    private func wishSection(title: String, items: [WishlistItem]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .padding(.horizontal, 4)

            LazyVStack(spacing: 10) {
                ForEach(items) { item in
                    NavigationLink(destination: WishlistDetailView(item: item)) {
                        WishCard(item: item)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            viewContext.delete(item)
                            saveErrorMessage = PersistenceSaveCoordinator.save(viewContext)
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    WishlistView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
