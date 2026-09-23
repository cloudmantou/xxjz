import SwiftUI
import UIKit

private struct BottomBarInsetKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    var bottomBarInset: CGFloat {
        get { self[BottomBarInsetKey.self] }
        set { self[BottomBarInsetKey.self] = newValue }
    }
}

struct MainTabView: View {
    @EnvironmentObject private var router: AppRouter
    @State private var assetFormMode: AssetFormMode = .add

    init() {
        UITabBar.appearance().isHidden = true
    }

    private var shouldExposeLegacySearchActivities: Bool {
        if #available(iOS 16.0, *) {
            return false
        }
        return true
    }

    var body: some View {
        GeometryReader { proxy in
            let bottomInset = max(proxy.safeAreaInsets.bottom, 10)
            let reservedBarHeight = 86 + bottomInset

            ZStack(alignment: .bottom) {
                tabContent
                    .safeAreaInset(edge: .bottom) {
                        Color.clear
                            .frame(height: reservedBarHeight)
                    }
                    .environment(\.bottomBarInset, reservedBarHeight)
                    .floatingTabBarHiddenCompat()

                if !router.showQuickRecordSheet {
                    FloatingTabBar(
                        selectedTab: $router.selectedTab,
                        safeAreaBottom: proxy.safeAreaInsets.bottom,
                        quickRecordPresented: router.showQuickRecordSheet,
                        openQuickRecord: { router.trigger(.quickRecord) }
                    )
                }
            }
            .ignoresSafeArea(edges: .bottom)
            .onAppear {
                if router.selectedTab == .quick {
                    router.selectedTab = .home
                }
            }
            .fullScreenCover(
                isPresented: $router.showQuickRecordSheet,
                onDismiss: {
                    router.syncAfterQuickRecordSheetDismissed()
                }
            ) {
                NavigationView {
                    QuickRecordView(
                        showBackButton: true,
                        onDismiss: { router.dismissQuickRecord(printTargetURI: nil) }
                    )
                }
                .navigationViewStyle(.stack)
            }
        }
    }

    private var tabContent: some View {
        TabView(selection: $router.selectedTab) {
            DashboardView()
                .tabItem {
                    Label(Constants.Tab.home.title, systemImage: Constants.Tab.home.icon)
                }
                .tag(Constants.Tab.home)
                .userActivity("com.assetlife.openHome") { activity in
                    activity.isEligibleForSearch = false
                    activity.isEligibleForPrediction = false
                    activity.title = "打开小西记账主页"
                }

            StatisticsHomeView()
                .tabItem {
                    Label(Constants.Tab.record.title, systemImage: Constants.Tab.record.icon)
                }
                .tag(Constants.Tab.record)
                .userActivity("com.assetlife.openStats") { activity in
                    activity.isEligibleForSearch = shouldExposeLegacySearchActivities
                    activity.isEligibleForPrediction = shouldExposeLegacySearchActivities
                    activity.title = "打开统计页"
                }

            AssetWishTabView()
                .tabItem {
                    Label(Constants.Tab.asset.title, systemImage: Constants.Tab.asset.icon)
                }
                .tag(Constants.Tab.asset)
                .userActivity("com.assetlife.openAsset") { activity in
                    activity.isEligibleForSearch = shouldExposeLegacySearchActivities
                    activity.isEligibleForPrediction = shouldExposeLegacySearchActivities
                    activity.title = "打开资产页"
                }
                .userActivity("com.assetlife.openWish") { activity in
                    activity.isEligibleForSearch = shouldExposeLegacySearchActivities
                    activity.isEligibleForPrediction = shouldExposeLegacySearchActivities
                    activity.title = "打开心愿清单"
                }

            ProfileView()
                .tabItem {
                    Label(Constants.Tab.profile.title, systemImage: Constants.Tab.profile.icon)
                }
                .tag(Constants.Tab.profile)
                .userActivity("com.assetlife.openProfile") { activity in
                    activity.isEligibleForSearch = shouldExposeLegacySearchActivities
                    activity.isEligibleForPrediction = shouldExposeLegacySearchActivities
                    activity.title = "打开我的页面"
                }
        }
        .tint(.warmTeal)
        .sheet(isPresented: $router.showAddAssetSheet) {
            AssetFormView(mode: assetFormMode)
                .onChange(of: router.showAddAssetSheet) { isShowing in
                    if isShowing {
                        if let params = router.pendingWishToAsset {
                            assetFormMode = .addFromWish(name: params.name, category: params.category, purchasePrice: params.purchasePrice)
                            router.pendingWishToAsset = nil
                        } else {
                            assetFormMode = .add
                        }
                    }
                }
        }
        .sheet(isPresented: $router.showAddWishSheet) {
            WishlistFormView(mode: .add)
        }
    }
}

private struct AssetWishTabView: View {
    @EnvironmentObject private var router: AppRouter
    @State private var selectedSection: AppRouter.AssetSection = .asset
    @State private var previousSection: AppRouter.AssetSection = .asset
    @Namespace private var sectionToggleNamespace

    private var screenWidth: CGFloat {
        UIScreen.main.bounds.width
    }

    private var pageHorizontalPadding: CGFloat {
        Constants.Layout.pageHorizontalPadding(for: screenWidth)
    }

    var body: some View {
        VStack(spacing: 0) {
            sectionSelector
                .padding(.horizontal, pageHorizontalPadding)
                .padding(.top, 8)
                .padding(.bottom, 6)
                .background(Color.appPageBackground)

            Group {
                if selectedSection == .asset {
                    AssetListView()
                        .transition(sectionTransition(to: .asset))
                } else {
                    WishlistView()
                        .transition(sectionTransition(to: .wish))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: selectedSection)
        .onAppear {
            selectedSection = router.selectedAssetSection
            previousSection = router.selectedAssetSection
        }
        .onChange(of: router.selectedAssetSection) { newValue in
            guard newValue != selectedSection else { return }
            previousSection = selectedSection
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                selectedSection = newValue
            }
        }
        .onChange(of: selectedSection) { newValue in
            guard router.selectedAssetSection != newValue else { return }
            router.selectedAssetSection = newValue
        }
    }

    private var sectionSelector: some View {
        HStack(spacing: 6) {
            sectionButton(title: "资产", section: .asset)
            sectionButton(title: "心愿", section: .wish)
        }
        .padding(4)
        .frame(height: 42)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.secondaryCardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.borderSoft, lineWidth: 0.7)
        )
    }

    private func sectionButton(title: String, section: AppRouter.AssetSection) -> some View {
        let isSelected = selectedSection == section

        return Button {
            guard section != selectedSection else { return }
            previousSection = selectedSection
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                selectedSection = section
            }
        } label: {
            ZStack {
                if isSelected {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(Color.warmTeal)
                        .matchedGeometryEffect(id: "assetWishSectionBackground", in: sectionToggleNamespace)
                }

                Text(title)
                    .font(.system(size: 15, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? Color.white : Color.textSecondary)
                    .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, minHeight: 34, maxHeight: 34)
            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func sectionTransition(to target: AppRouter.AssetSection) -> AnyTransition {
        let targetIndex = target == .asset ? 0 : 1
        let previousIndex = previousSection == .asset ? 0 : 1
        let insertFromTrailing = targetIndex > previousIndex
        return AnyTransition.asymmetric(
            insertion: .move(edge: insertFromTrailing ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: insertFromTrailing ? .leading : .trailing).combined(with: .opacity)
        )
    }
}

private struct FloatingTabBar: View {
    @Binding var selectedTab: Constants.Tab
    let safeAreaBottom: CGFloat
    let quickRecordPresented: Bool
    let openQuickRecord: () -> Void

    var body: some View {
        let bottomPadding = max(10, safeAreaBottom)

        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.appCardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.borderSoft, lineWidth: 1)
                )
                .frame(height: 72)
                .shadow(color: Color.black.opacity(0.08), radius: 14, y: 5)

            HStack(spacing: 0) {
                regularTabButton(tab: .home)
                regularTabButton(tab: .record)
                centerQuickButton
                regularTabButton(tab: .asset)
                regularTabButton(tab: .profile)
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, bottomPadding)
    }

    private func regularTabButton(tab: Constants.Tab) -> some View {
        let isSelected = selectedTab == tab
        return Button {
            selectedTab = tab
        } label: {
            VStack(spacing: 2) {
                Image(systemName: tab.icon)
                    .font(.system(size: 18, weight: .semibold))
                Text(tab.title)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(isSelected ? .warmTeal : .textSecondary)
            .frame(maxWidth: .infinity, minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var centerQuickButton: some View {
        let isSelected = quickRecordPresented

        return Button {
            openQuickRecord()
        } label: {
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(Color.appCardBackground)
                        .frame(width: 50, height: 50)
                        .overlay(
                            Circle()
                                .stroke(Color.borderSoft, lineWidth: 0.8)
                        )
                        .shadow(color: Color.black.opacity(0.09), radius: 6, y: 2)

                    Image(systemName: "pencil")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.warmTeal)
                }
                .offset(y: -16)

                Text(Constants.Tab.quick.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(isSelected ? .primary : .textSecondary)
                    .padding(.top, -10)
            }
            .frame(maxWidth: .infinity, minHeight: 58)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private extension View {
    @ViewBuilder
    func floatingTabBarHiddenCompat() -> some View {
        if #available(iOS 16.0, *) {
            self.toolbar(.hidden, for: .tabBar)
        } else {
            self
        }
    }
}

#Preview {
    MainTabView()
        .environmentObject(AppRouter())
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
